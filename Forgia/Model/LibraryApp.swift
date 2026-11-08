import Foundation

/// Una app nella libreria: l'IPA originale e, se c'è, la sua versione firmata.
struct LibraryApp: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var displayName: String
    var bundleIdentifier: String
    var version: String
    var build: String
    var minimumOSVersion: String
    var hasIcon: Bool = false
    var sourceSizeBytes: Int64 = 0
    var importedAt: Date = Date()

    /// Compilato quando l'app è stata firmata almeno una volta.
    var signature: SignatureInfo?

    struct SignatureInfo: Codable, Hashable {
        var identityID: UUID
        var identityLabel: String
        var signedBundleIdentifier: String
        var signedDisplayName: String
        var signedVersion: String
        var signedAt: Date
        var sizeBytes: Int64
        var profileExpiration: Date?
    }

    var directory: URL { Paths.appDir(id) }
    var sourceIPA: URL { directory.appendingPathComponent("source.ipa") }
    var signedIPA: URL { directory.appendingPathComponent("signed.ipa") }
    var iconFile: URL { directory.appendingPathComponent("icon.png") }

    var isSigned: Bool {
        signature != nil && FileManager.default.fileExists(atPath: signedIPA.path)
    }

    var versionDescription: String {
        build.isEmpty || build == version ? version : "\(version) (\(build))"
    }
}
