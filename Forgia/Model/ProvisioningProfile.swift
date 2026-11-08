import Foundation
import Security

/// Dati leggibili estratti da un file .mobileprovision.
///
/// Il file è una struttura CMS (DER) con dentro un plist XML. Su iOS non ci sono
/// le API CMSDecoder, quindi si ritaglia il plist cercando i suoi delimitatori:
/// è quello che fanno tutti gli strumenti di sideloading.
struct ProvisioningProfile: Codable, Hashable {
    var name: String
    var uuid: String
    var appIDName: String
    var teamName: String
    var teamIdentifier: String
    var applicationIdentifier: String
    var creationDate: Date?
    var expirationDate: Date?
    var provisionedDevices: [String]
    var platforms: [String]
    var certificateNames: [String]
    var provisionsAllDevices: Bool
    var getTaskAllow: Bool

    /// Profilo con App ID jolly (`TEAMID.*`): può firmare qualsiasi bundle id.
    var isWildcard: Bool { applicationIdentifier.hasSuffix(".*") }

    /// Un profilo enterprise non elenca i device.
    var isEnterprise: Bool { provisionsAllDevices }

    var kindDescription: String {
        if isEnterprise { return "Enterprise (in-house)" }
        if getTaskAllow { return "Development" }
        return "Ad Hoc / Distribution"
    }

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < Date()
    }

    var daysUntilExpiry: Int? {
        guard let expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
    }

    /// Il prefisso di bundle id consentito, senza il team id davanti.
    /// Per `ABCDE12345.com.tizio.*` restituisce `com.tizio.*`.
    var bundleIDPattern: String {
        let parts = applicationIdentifier.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count == 2 ? String(parts[1]) : applicationIdentifier
    }

    /// Dice se questo profilo può firmare il bundle id indicato.
    func allows(bundleID: String) -> Bool {
        let pattern = bundleIDPattern
        if pattern == "*" { return true }
        if pattern.hasSuffix(".*") {
            let prefix = String(pattern.dropLast(1)) // "com.tizio."
            return bundleID.hasPrefix(prefix)
        }
        return pattern == bundleID
    }
}

enum ProvisioningProfileError: LocalizedError {
    case plistNotFound
    case malformed

    var errorDescription: String? {
        switch self {
        case .plistNotFound:
            return "Nel file .mobileprovision non è stato trovato un profilo leggibile."
        case .malformed:
            return "Il profilo è in un formato non riconosciuto."
        }
    }
}

extension ProvisioningProfile {
    static func parse(contentsOf url: URL) throws -> ProvisioningProfile {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> ProvisioningProfile {
        guard let plistData = embeddedPlist(in: data) else {
            throw ProvisioningProfileError.plistNotFound
        }
        guard let dict = try PropertyListSerialization.propertyList(
            from: plistData, options: [], format: nil
        ) as? [String: Any] else {
            throw ProvisioningProfileError.malformed
        }

        let entitlements = dict["Entitlements"] as? [String: Any] ?? [:]
        let certData = dict["DeveloperCertificates"] as? [Data] ?? []

        return ProvisioningProfile(
            name: dict["Name"] as? String ?? "Profilo senza nome",
            uuid: dict["UUID"] as? String ?? "",
            appIDName: dict["AppIDName"] as? String ?? "",
            teamName: dict["TeamName"] as? String ?? "",
            teamIdentifier: (dict["TeamIdentifier"] as? [String])?.first ?? "",
            applicationIdentifier: entitlements["application-identifier"] as? String ?? "",
            creationDate: dict["CreationDate"] as? Date,
            expirationDate: dict["ExpirationDate"] as? Date,
            provisionedDevices: dict["ProvisionedDevices"] as? [String] ?? [],
            platforms: dict["Platform"] as? [String] ?? [],
            certificateNames: certData.compactMap(commonName(ofCertificate:)),
            provisionsAllDevices: dict["ProvisionsAllDevices"] as? Bool ?? false,
            getTaskAllow: entitlements["get-task-allow"] as? Bool ?? false
        )
    }

    /// Ritaglia il plist XML incapsulato nel blob CMS.
    private static func embeddedPlist(in data: Data) -> Data? {
        // Se è già un plist (xml o binario), prendilo così com'è.
        if (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil {
            return data
        }
        guard let open = "<?xml".data(using: .utf8),
              let close = "</plist>".data(using: .utf8),
              let start = data.range(of: open),
              let end = data.range(of: close, options: .backwards)
        else { return nil }
        guard start.lowerBound < end.upperBound else { return nil }
        return data.subdata(in: start.lowerBound..<end.upperBound)
    }

    private static func commonName(ofCertificate der: Data) -> String? {
        guard let cert = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        return SecCertificateCopySubjectSummary(cert) as String?
    }
}
