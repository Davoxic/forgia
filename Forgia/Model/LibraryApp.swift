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

    /// Compilato quando l'app è stata firmata almeno una volta da Forgia.
    var signature: SignatureInfo?

    /// L'archivio importato era già firmato da qualcun altro.
    var sourceIsSigned: Bool = false
    /// Il profilo incorporato nell'archivio importato, se c'era.
    var sourceProfile: ProvisioningProfile?

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

    // MARK: - Cosa si installa

    /// L'archivio da consegnare a iOS: quello firmato qui se c'è,
    /// altrimenti l'originale, ma solo se portava già una firma sua.
    var installableIPA: URL? {
        if isSigned { return signedIPA }
        guard sourceIsSigned,
              FileManager.default.fileExists(atPath: sourceIPA.path) else { return nil }
        return sourceIPA
    }

    var canInstall: Bool { installableIPA != nil }

    var installBundleIdentifier: String {
        signature?.signedBundleIdentifier ?? bundleIdentifier
    }

    var installDisplayName: String {
        signature?.signedDisplayName ?? displayName
    }

    var installVersion: String {
        signature?.signedVersion ?? version
    }

    /// Quando scade la firma con cui verrà installata.
    var installExpiration: Date? {
        isSigned ? signature?.profileExpiration : sourceProfile?.expirationDate
    }
}
