import Foundation
import Security

/// Il certificato TLS usato dal server locale in modalità "tutto in locale".
/// È un .p12 che importi tu, per un nome host che risolve su 127.0.0.1.
enum TLSIdentityStore {
    static var p12URL: URL { Paths.documents.appendingPathComponent("tls-server.p12") }

    static var isConfigured: Bool {
        FileManager.default.fileExists(atPath: p12URL.path)
    }

    private static let keychainAccount = "forgia.tls.p12"

    static func store(p12 source: URL, password: String) throws {
        let data = try Data(contentsOf: source)
        // Verifica che si apra prima di salvarlo.
        _ = try identity(from: data, password: password)
        try data.write(to: p12URL, options: .atomic)
        setPassword(password)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: p12URL)
        setPassword(nil)
    }

    /// Carica l'identità TLS salvata, pronta per NWListener.
    static func loadIdentity() throws -> SecIdentity {
        let data = try Data(contentsOf: p12URL)
        return try identity(from: data, password: password() ?? "")
    }

    enum TLSError: LocalizedError {
        case importFailed(OSStatus)
        case noIdentity

        var errorDescription: String? {
            switch self {
            case .importFailed(let status) where status == errSecAuthFailed:
                return "Password del certificato TLS errata."
            case .importFailed(let status):
                return "Importazione del certificato TLS non riuscita (codice \(status))."
            case .noIdentity:
                return "Il file .p12 non contiene una chiave privata con il suo certificato."
            }
        }
    }

    private static func identity(from data: Data, password: String) throws -> SecIdentity {
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var rawItems: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &rawItems)
        guard status == errSecSuccess else { throw TLSError.importFailed(status) }

        guard let items = rawItems as? [[String: Any]],
              let first = items.first,
              let value = first[kSecImportItemIdentity as String],
              CFGetTypeID(value as CFTypeRef) == SecIdentityGetTypeID()
        else { throw TLSError.noIdentity }

        return value as! SecIdentity
    }

    // MARK: - Password nel Keychain

    private static func setPassword(_ password: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.dchietti.forgia.tls",
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        guard let password else { return }

        var add = query
        add[kSecValueData as String] = Data(password.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func password() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.dchietti.forgia.tls",
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
