import Foundation

/// Una coppia certificato: il .p12 con la chiave privata e il .mobileprovision.
struct SigningIdentity: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String
    var profile: ProvisioningProfile
    var addedAt: Date = Date()

    /// La password sta nel Keychain, non qui dentro.
    var p12URL: URL { Paths.identityDir(id).appendingPathComponent("cert.p12") }
    var provisionURL: URL { Paths.identityDir(id).appendingPathComponent("profile.mobileprovision") }

    var password: String { Keychain.password(for: id) ?? "" }

    var subtitle: String {
        var parts: [String] = []
        if !profile.teamName.isEmpty { parts.append(profile.teamName) }
        parts.append(profile.kindDescription)
        return parts.joined(separator: " · ")
    }

    var expiryDescription: String {
        guard let date = profile.expirationDate else { return "Scadenza sconosciuta" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale(identifier: "it_IT")
        if profile.isExpired { return "Scaduto il \(f.string(from: date))" }
        if let days = profile.daysUntilExpiry {
            return "Scade il \(f.string(from: date)) · \(days) giorni"
        }
        return "Scade il \(f.string(from: date))"
    }
}

/// Le password dei .p12 nel Keychain, non nei file di configurazione.
enum Keychain {
    private static let service = "com.dchietti.forgia.p12"

    static func setPassword(_ password: String, for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = Data(password.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func password(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
