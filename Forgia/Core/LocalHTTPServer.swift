import Foundation
import Network
import Security

/// Un server HTTP/1.1 minimo, solo GET e HEAD, che serve risorse in memoria o
/// file su disco. Esiste per consegnare il manifest e l'IPA al programma di
/// installazione di iOS, che li scarica dal dispositivo stesso.
///
/// Con un'identità TLS parla HTTPS, altrimenti HTTP in chiaro.
final class LocalHTTPServer {
    enum Resource {
        case data(Data, contentType: String)
        case file(URL, contentType: String)
    }

    enum ServerError: LocalizedError {
        case invalidPort
        case tlsIdentityRejected

        var errorDescription: String? {
            switch self {
            case .invalidPort: return "Porta non valida."
            case .tlsIdentityRejected: return "Il certificato TLS non è utilizzabile per il server locale."
            }
        }
    }

    private let queue = DispatchQueue(label: "com.dchietti.forgia.http", qos: .userInitiated)
    private let lock = NSLock()
    private var listener: NWListener?
    private var resources: [String: Resource] = [:]

    /// Chiamata su ogni richiesta ricevuta.
    var onRequest: ((String) -> Void)?
    /// Byte appena consegnati per quel percorso.
    var onBytesSent: ((String, Int64) -> Void)?
    /// Risposta completata per quel percorso.
    var onResponseFinished: ((String) -> Void)?

    private(set) var isRunning = false
    private(set) var boundPort: UInt16 = 0

    // MARK: - Risorse

    func setResource(_ resource: Resource, at path: String) {
        lock.lock(); defer { lock.unlock() }
        resources[path] = resource
    }

    func clearResources() {
        lock.lock(); defer { lock.unlock() }
        resources.removeAll()
    }

    private func resource(at path: String) -> Resource? {
        lock.lock(); defer { lock.unlock() }
        return resources[path]
    }

    // MARK: - Ciclo di vita

    func start(port: UInt16, identity: SecIdentity?) throws {
        stop()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.invalidPort
        }

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        var tlsOptions: NWProtocolTLS.Options?
        if let identity {
            guard let secIdentity = sec_identity_create(identity) else {
                throw ServerError.tlsIdentityRejected
            }
            let options = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(options.securityProtocolOptions, secIdentity)
            sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
            tlsOptions = options
        }

        let parameters = NWParameters(tls: tlsOptions, tcp: tcp)
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = false

        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)

        self.listener = listener
        self.boundPort = port
        self.isRunning = true
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        boundPort = 0
    }

    // MARK: - Connessioni

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(on: connection, buffer: Data())
    }

    private func readRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] chunk, _, isComplete, error in
            guard let self else { return }

            var buffer = buffer
            if let chunk { buffer.append(chunk) }

            if error != nil {
                connection.cancel()
                return
            }

            // Le intestazioni finiscono con una riga vuota.
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headData = Data(buffer[buffer.startIndex..<headerEnd.lowerBound])
                let head = String(data: headData, encoding: .utf8) ?? ""
                self.respond(to: head, on: connection)
                return
            }

            if isComplete || buffer.count > 128 * 1024 {
                connection.cancel()
                return
            }
            self.readRequest(on: connection, buffer: buffer)
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        let lines = head.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }

        let parts = requestLine.split(separator: " ").map(String.init)
        guard parts.count >= 2 else {
            send(status: "400 Bad Request", body: Data(), on: connection)
            return
        }
        let method = parts[0].uppercased()
        let target = parts[1]
        let path = String(target.split(separator: "?").first ?? "")

        onRequest?(path)

        guard method == "GET" || method == "HEAD" else {
            send(status: "405 Method Not Allowed", body: Data(), on: connection)
            return
        }

        guard let resource = resource(at: path) else {
            send(status: "404 Not Found", body: Data("not found".utf8), on: connection)
            return
        }

        let rangeHeader = lines.first {
            $0.lowercased().hasPrefix("range:")
        }?.dropFirst("range:".count).trimmingCharacters(in: .whitespaces)

        switch resource {
        case .data(let data, let contentType):
            serve(data: data, contentType: contentType, range: rangeHeader,
                  headOnly: method == "HEAD", path: path, on: connection)
        case .file(let url, let contentType):
            serveFile(url, contentType: contentType, range: rangeHeader,
                      headOnly: method == "HEAD", path: path, on: connection)
        }
    }

    // MARK: - Risposte

    /// Interpreta `bytes=start-end`. Restituisce nil se il formato non è gestito.
    private func parseRange(_ header: String?, totalSize: Int64) -> (Int64, Int64)? {
        guard let header, header.hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst("bytes=".count)
        guard !spec.contains(",") else { return nil }
        let bounds = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard bounds.count == 2 else { return nil }

        if bounds[0].isEmpty {
            // bytes=-N : gli ultimi N byte
            guard let suffix = Int64(bounds[1]), suffix > 0 else { return nil }
            let start = max(0, totalSize - suffix)
            return (start, totalSize - 1)
        }
        guard let start = Int64(bounds[0]), start < totalSize else { return nil }
        let end = bounds[1].isEmpty ? totalSize - 1 : min(Int64(bounds[1]) ?? totalSize - 1, totalSize - 1)
        guard end >= start else { return nil }
        return (start, end)
    }

    private func headerData(
        status: String,
        contentType: String,
        contentLength: Int64,
        contentRange: String? = nil
    ) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(contentLength)\r\n"
        head += "Accept-Ranges: bytes\r\n"
        if let contentRange { head += "Content-Range: \(contentRange)\r\n" }
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8)
    }

    private func send(status: String, body: Data, on connection: NWConnection) {
        var payload = headerData(status: status, contentType: "text/plain; charset=utf-8",
                                 contentLength: Int64(body.count))
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func serve(
        data: Data,
        contentType: String,
        range: String?,
        headOnly: Bool,
        path: String,
        on connection: NWConnection
    ) {
        let total = Int64(data.count)
        var slice = data
        var status = "200 OK"
        var contentRange: String?

        if let (start, end) = parseRange(range, totalSize: total) {
            let lower = data.index(data.startIndex, offsetBy: Int(start))
            let upper = data.index(data.startIndex, offsetBy: Int(end) + 1)
            slice = data[lower..<upper]
            status = "206 Partial Content"
            contentRange = "bytes \(start)-\(end)/\(total)"
        }

        var payload = headerData(status: status, contentType: contentType,
                                 contentLength: Int64(slice.count), contentRange: contentRange)
        if !headOnly { payload.append(slice) }
        connection.send(content: payload, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { [weak self] _ in
            self?.onResponseFinished?(path)
            connection.cancel()
        })
    }

    private func serveFile(
        _ url: URL,
        contentType: String,
        range: String?,
        headOnly: Bool,
        path: String,
        on connection: NWConnection
    ) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            send(status: "404 Not Found", body: Data("missing".utf8), on: connection)
            return
        }

        let total = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        var start: Int64 = 0
        var end: Int64 = max(0, total - 1)
        var status = "200 OK"
        var contentRange: String?

        if let parsed = parseRange(range, totalSize: total) {
            start = parsed.0
            end = parsed.1
            status = "206 Partial Content"
            contentRange = "bytes \(start)-\(end)/\(total)"
        }

        let length = total == 0 ? 0 : end - start + 1
        let header = headerData(status: status, contentType: contentType,
                                contentLength: length, contentRange: contentRange)

        if headOnly || length == 0 {
            try? handle.close()
            connection.send(content: header, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { [weak self] _ in
                self?.onResponseFinished?(path)
                connection.cancel()
            })
            return
        }

        try? handle.seek(toOffset: UInt64(start))
        connection.send(content: header, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                try? handle.close()
                connection.cancel()
                return
            }
            self.streamBody(handle: handle, remaining: length, path: path, on: connection)
        })
    }

    /// Manda il corpo a blocchi, chiedendo il blocco successivo solo quando il
    /// precedente è stato consegnato: così un IPA da centinaia di MB non finisce
    /// tutto in memoria.
    private func streamBody(
        handle: FileHandle,
        remaining: Int64,
        path: String,
        on connection: NWConnection
    ) {
        let chunkSize = 256 * 1024
        guard remaining > 0 else {
            try? handle.close()
            // finalMessage chiude il lato in uscita solo dopo che tutto il
            // corpo e' stato davvero scritto: chiudere prima tronca la coda.
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { [weak self] _ in
                self?.onResponseFinished?(path)
                connection.cancel()
            })
            return
        }

        let take = Int(min(Int64(chunkSize), remaining))
        let chunk = (try? handle.read(upToCount: take)) ?? Data()
        guard !chunk.isEmpty else {
            try? handle.close()
            connection.cancel()
            return
        }

        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                try? handle.close()
                connection.cancel()
                return
            }
            self.onBytesSent?(path, Int64(chunk.count))
            self.streamBody(
                handle: handle,
                remaining: remaining - Int64(chunk.count),
                path: path,
                on: connection
            )
        })
    }
}
