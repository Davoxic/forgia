import Foundation
import Combine

/// Come consegnare l'app firmata a iOS.
enum InstallMode: Int, CaseIterable, Identifiable {
    /// Server locale in HTTP, manifest generato da un servizio HTTPS esterno.
    /// iOS pretende HTTPS solo per il manifest, non per il pacchetto.
    case remoteManifest = 0
    /// Tutto in locale via HTTPS, con un certificato TLS che importi tu.
    case fullyLocal = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .remoteManifest: return "Manifest esterno"
        case .fullyLocal:     return "Tutto in locale (HTTPS)"
        }
    }

    var explanation: String {
        switch self {
        case .remoteManifest:
            return "Il pacchetto resta sul telefono e viene servito in HTTP; solo il piccolo file manifest passa da un servizio HTTPS esterno, che riceve nome, bundle id e versione dell'app. Serve una connessione a internet. Non richiede alcun certificato."
        case .fullyLocal:
            return "Niente esce dal telefono, ma iOS accetta il manifest solo via HTTPS con un certificato valido: devi importare un .p12 TLS per un dominio che punta a 127.0.0.1."
        }
    }
}

final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var installMode: InstallMode {
        didSet { defaults.set(installMode.rawValue, forKey: Keys.installMode) }
    }
    @Published var serverPort: Int {
        didSet { defaults.set(serverPort, forKey: Keys.serverPort) }
    }
    @Published var manifestServiceURL: String {
        didSet { defaults.set(manifestServiceURL, forKey: Keys.manifestService) }
    }
    /// Se attivo il manifest punta a 127.0.0.1, altrimenti all'IP del telefono
    /// sulla rete locale. Il primo funziona quasi sempre; il secondo è il
    /// ripiego se il loopback viene rifiutato.
    @Published var useLoopback: Bool {
        didSet { defaults.set(useLoopback, forKey: Keys.useLoopback) }
    }
    /// Il nome host del certificato TLS importato, usato in modalità locale.
    @Published var tlsCommonName: String {
        didSet { defaults.set(tlsCommonName, forKey: Keys.tlsCommonName) }
    }

    static let defaultManifestService = "https://api.palera.in/genPlist"

    private enum Keys {
        static let installMode = "forgia.installMode"
        static let serverPort = "forgia.serverPort"
        static let manifestService = "forgia.manifestService"
        static let useLoopback = "forgia.useLoopback"
        static let tlsCommonName = "forgia.tlsCommonName"
    }

    init() {
        installMode = InstallMode(rawValue: defaults.integer(forKey: Keys.installMode)) ?? .remoteManifest
        let port = defaults.integer(forKey: Keys.serverPort)
        serverPort = port == 0 ? 8898 : port
        manifestServiceURL = defaults.string(forKey: Keys.manifestService) ?? Self.defaultManifestService
        useLoopback = defaults.object(forKey: Keys.useLoopback) as? Bool ?? true
        tlsCommonName = defaults.string(forKey: Keys.tlsCommonName) ?? ""
    }

    func resetManifestService() {
        manifestServiceURL = Self.defaultManifestService
    }
}
