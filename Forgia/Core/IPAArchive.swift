import Foundation
import Zip

/// I metadati che interessano dentro l'Info.plist di un bundle .app.
struct BundleMetadata {
    var displayName: String
    var bundleIdentifier: String
    var version: String
    var build: String
    var minimumOSVersion: String
    var iconFileNames: [String]
}

enum IPAError: LocalizedError {
    case noPayload
    case noAppBundle
    case noInfoPlist
    case notAnIPA

    var errorDescription: String? {
        switch self {
        case .noPayload:    return "L'archivio non contiene una cartella Payload: non è un IPA valido."
        case .noAppBundle:  return "Dentro Payload non c'è nessun bundle .app."
        case .noInfoPlist:  return "Il bundle .app non ha un Info.plist leggibile."
        case .notAnIPA:     return "Il file non sembra un archivio IPA."
        }
    }
}

/// Estrazione, lettura e ricompattazione degli archivi IPA.
enum IPAArchive {
    /// Zip rifiuta le estensioni che non conosce: va registrata una volta sola.
    static func registerExtensions() {
        Zip.addCustomFileExtension("ipa")
        Zip.addCustomFileExtension("tipa")
    }

    /// Estrae l'IPA in `destination`, che deve essere vuota.
    /// Restituisce l'URL della cartella `Payload`.
    static func extract(ipa: URL, into destination: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try Zip.unzipFile(ipa, destination: destination, overwrite: true, password: nil)

        let payload = destination.appendingPathComponent("Payload", isDirectory: true)
        if fm.fileExists(atPath: payload.path) { return payload }

        // Qualche IPA ha un livello di cartelle in più: cerca una Payload più in basso.
        if let found = try? fm.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
            .compactMap({ dir -> URL? in
                let candidate = dir.appendingPathComponent("Payload", isDirectory: true)
                return fm.fileExists(atPath: candidate.path) ? candidate : nil
            }).first {
            return found
        }
        throw IPAError.noPayload
    }

    /// Il bundle .app dentro una cartella Payload.
    static func appBundle(inPayload payload: URL) throws -> URL {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: payload, includingPropertiesForKeys: nil
        )) ?? []
        guard let app = contents.first(where: { $0.pathExtension.lowercased() == "app" }) else {
            throw IPAError.noAppBundle
        }
        return app
    }

    static func metadata(ofAppBundle app: URL) throws -> BundleMetadata {
        let plistURL = app.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any]
        else { throw IPAError.noInfoPlist }

        let name = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? app.deletingPathExtension().lastPathComponent

        return BundleMetadata(
            displayName: name,
            bundleIdentifier: dict["CFBundleIdentifier"] as? String ?? "",
            version: dict["CFBundleShortVersionString"] as? String ?? "1.0",
            build: dict["CFBundleVersion"] as? String ?? "",
            minimumOSVersion: dict["MinimumOSVersion"] as? String ?? "",
            iconFileNames: iconBaseNames(from: dict)
        )
    }

    private static func iconBaseNames(from info: [String: Any]) -> [String] {
        var names: [String] = []
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] {
            names += primary["CFBundleIconFiles"] as? [String] ?? []
            if let single = primary["CFBundleIconName"] as? String { names.append(single) }
        }
        names += info["CFBundleIconFiles"] as? [String] ?? []
        if let single = info["CFBundleIconFile"] as? String { names.append(single) }
        return names
    }

    /// Cerca il PNG dell'icona più grande dentro il bundle e lo copia in `destination`.
    @discardableResult
    static func extractIcon(fromAppBundle app: URL, baseNames: [String], to destination: URL) -> Bool {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: app, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let pngs = files.filter { $0.pathExtension.lowercased() == "png" }

        func size(_ url: URL) -> Int {
            (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }

        var candidates = pngs.filter { url in
            let stem = url.deletingPathExtension().lastPathComponent
            return baseNames.contains { !$0.isEmpty && stem.hasPrefix($0) }
        }
        if candidates.isEmpty {
            candidates = pngs.filter {
                let stem = $0.deletingPathExtension().lastPathComponent.lowercased()
                return stem.hasPrefix("appicon") || stem.hasPrefix("icon")
            }
        }
        guard let best = candidates.max(by: { size($0) < size($1) }) else { return false }

        try? fm.removeItem(at: destination)
        do {
            try fm.copyItem(at: best, to: destination)
            return true
        } catch {
            return false
        }
    }

    /// Ricompatta una cartella Payload in un IPA.
    static func pack(payload: URL, to ipa: URL) throws {
        try? FileManager.default.removeItem(at: ipa)
        try Zip.zipFiles(paths: [payload], zipFilePath: ipa, password: nil, progress: nil)
    }
}
