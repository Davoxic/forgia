import Foundation

/// Tutte le cartelle usate dall'app, dentro il container Documents.
enum Paths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Archivi delle app importate: Apps/<uuid>/
    static var apps: URL { documents.appendingPathComponent("Apps", isDirectory: true) }

    /// Certificati importati: Identities/<uuid>/
    static var identities: URL { documents.appendingPathComponent("Identities", isDirectory: true) }

    /// Cartella di lavoro, svuotata a ogni avvio.
    static var work: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("work", isDirectory: true)
    }

    static var libraryIndex: URL { documents.appendingPathComponent("library.json") }
    static var identityIndex: URL { documents.appendingPathComponent("identities.json") }

    static func appDir(_ id: UUID) -> URL {
        apps.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func identityDir(_ id: UUID) -> URL {
        identities.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Crea le cartelle di base e pulisce la cartella di lavoro.
    static func bootstrap() {
        let fm = FileManager.default
        for dir in [apps, identities] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? fm.removeItem(at: work)
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
    }

    /// Una sottocartella di lavoro nuova e vuota.
    static func newWorkDir(_ tag: String = "job") -> URL {
        let dir = work.appendingPathComponent("\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func byteString(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB, .useKB]
        return f.string(fromByteCount: bytes)
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let item as URL in e {
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
