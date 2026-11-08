import Foundation
import Security
import UIKit

/// Avvia il server locale, costruisce il manifest e passa la palla a iOS.
@MainActor
final class InstallService: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case handedToSystem
        case transferring
        case delivered
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .preparing, .handedToSystem, .transferring: return true
            default: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var events: [String] = []
    @Published private(set) var servedBytes: Int64 = 0

    private let server = LocalHTTPServer()
    private let keeper = BackgroundKeeper()
    private var autoStopTask: Task<Void, Never>?

    var isServerRunning: Bool { server.isRunning }

    // MARK: - Avvio

    func install(app: LibraryApp, settings: AppSettings) async {
        cancel()
        phase = .preparing
        events = []
        servedBytes = 0

        guard app.isSigned, let signature = app.signature else {
            fail("Questa app non è ancora firmata.")
            return
        }

        let identifier = app.id.uuidString.lowercased()
        let port = UInt16(clamping: settings.serverPort)

        do {
            switch settings.installMode {
            case .fullyLocal:
                try await startFullyLocal(
                    app: app, signature: signature,
                    identifier: identifier, port: port, settings: settings
                )
            case .remoteManifest:
                try await startWithRemoteManifest(
                    app: app, signature: signature,
                    identifier: identifier, port: port, settings: settings
                )
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: - Modalità con manifest esterno

    private func startWithRemoteManifest(
        app: LibraryApp,
        signature: LibraryApp.SignatureInfo,
        identifier: String,
        port: UInt16,
        settings: AppSettings
    ) async throws {
        let host: String
        if settings.useLoopback {
            host = "127.0.0.1"
        } else {
            guard let ip = NetworkInterface.localIPv4() else {
                throw InstallError.noLocalAddress
            }
            host = ip
        }

        try startServer(app: app, identifier: identifier, port: port, tls: false)
        log("Server in ascolto su http://\(host):\(port)")

        let packageURL = url(scheme: "http", host: host, port: port, path: "/\(identifier).ipa")

        guard var components = URLComponents(string: settings.manifestServiceURL) else {
            throw InstallError.badManifestService
        }
        components.queryItems = [
            URLQueryItem(name: "bundleid", value: signature.signedBundleIdentifier),
            URLQueryItem(name: "name", value: signature.signedDisplayName),
            URLQueryItem(name: "version", value: signature.signedVersion),
            URLQueryItem(name: "fetchurl", value: packageURL.absoluteString)
        ]
        guard let manifestURL = components.url else { throw InstallError.badManifestService }

        log("Manifest richiesto a \(components.host ?? "servizio esterno")")
        try await handOff(manifestURLString: manifestURL.absoluteString)
    }

    // MARK: - Modalità tutta locale

    private func startFullyLocal(
        app: LibraryApp,
        signature: LibraryApp.SignatureInfo,
        identifier: String,
        port: UInt16,
        settings: AppSettings
    ) async throws {
        guard TLSIdentityStore.isConfigured else { throw InstallError.noTLSCertificate }
        let host = settings.tlsCommonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw InstallError.noTLSHostname }

        let identity = try TLSIdentityStore.loadIdentity()
        try startServer(app: app, identifier: identifier, port: port, tls: true, identity: identity)
        log("Server HTTPS in ascolto su https://\(host):\(port)")

        let manifest = InstallManifest(
            bundleIdentifier: signature.signedBundleIdentifier,
            version: signature.signedVersion,
            title: signature.signedDisplayName,
            packageURL: url(scheme: "https", host: host, port: port, path: "/\(identifier).ipa"),
            displayImageURL: url(scheme: "https", host: host, port: port, path: "/\(identifier)-57.png"),
            fullSizeImageURL: url(scheme: "https", host: host, port: port, path: "/\(identifier)-512.png")
        )
        server.setResource(
            .data(manifest.data, contentType: "text/xml; charset=utf-8"),
            at: "/\(identifier).plist"
        )

        let manifestURL = url(scheme: "https", host: host, port: port, path: "/\(identifier).plist")
        try await handOff(manifestURLString: manifestURL.absoluteString)
    }

    // MARK: - Parti comuni

    private func startServer(
        app: LibraryApp,
        identifier: String,
        port: UInt16,
        tls: Bool,
        identity: SecIdentity? = nil
    ) throws {
        server.clearResources()
        server.onRequest = { [weak self] path in
            Task { @MainActor in self?.note(request: path) }
        }
        server.setResource(
            .file(app.signedIPA, contentType: "application/octet-stream"),
            at: "/\(identifier).ipa"
        )

        let small = iconData(for: app, side: 57)
        let large = iconData(for: app, side: 512)
        server.setResource(.data(small, contentType: "image/png"), at: "/\(identifier)-57.png")
        server.setResource(.data(large, contentType: "image/png"), at: "/\(identifier)-512.png")

        try server.start(port: port, identity: tls ? identity : nil)
        keeper.start()
    }

    private func handOff(manifestURLString: String) async throws {
        let encoded = manifestURLString
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? manifestURLString
        guard let itms = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") else {
            throw InstallError.badManifestService
        }

        phase = .handedToSystem
        log("Richiesta di installazione inviata a iOS")
        _ = await UIApplication.shared.open(itms)

        // Dopo un po' senza richieste il server si spegne da solo.
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000)
            await MainActor.run { self?.cancel() }
        }
    }

    private func note(request path: String) {
        if path.hasSuffix(".ipa") {
            if phase != .transferring { log("iOS sta scaricando il pacchetto") }
            phase = .transferring
            servedBytes += 1
        } else if path.hasSuffix(".plist") {
            log("Manifest consegnato")
        }
    }

    /// Da chiamare quando l'utente conferma che l'installazione è partita.
    func markDelivered() {
        guard phase != .idle else { return }
        phase = .delivered
    }

    func cancel() {
        autoStopTask?.cancel()
        autoStopTask = nil
        server.stop()
        server.clearResources()
        keeper.stop()
        if phase.isBusy { phase = .idle }
    }

    // MARK: - Utilità

    private func url(scheme: String, host: String, port: UInt16, path: String) -> URL {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host
        comps.port = Int(port)
        comps.path = path
        return comps.url!
    }

    private func iconData(for app: LibraryApp, side: CGFloat) -> Data {
        if app.hasIcon, let image = UIImage(contentsOfFile: app.iconFile.path) {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
            return renderer.pngData { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.pngData { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private func log(_ message: String) {
        events.append(message)
    }

    private func fail(_ message: String) {
        cancel()
        phase = .failed(message)
        log("Errore: \(message)")
    }

    enum InstallError: LocalizedError {
        case noLocalAddress
        case badManifestService
        case noTLSCertificate
        case noTLSHostname

        var errorDescription: String? {
            switch self {
            case .noLocalAddress:
                return "Non riesco a leggere l'indirizzo del telefono sulla rete. Attiva il Wi-Fi o usa l'indirizzo di loopback."
            case .badManifestService:
                return "L'indirizzo del servizio manifest non è valido."
            case .noTLSCertificate:
                return "Nessun certificato TLS importato: serve per la modalità tutta locale."
            case .noTLSHostname:
                return "Manca il nome host del certificato TLS nelle impostazioni."
            }
        }
    }
}
