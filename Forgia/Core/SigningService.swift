import Foundation
import Zsign
import ZsignC

/// Le scelte fatte nel pannello di firma.
struct SigningOptions: Equatable {
    var customBundleIdentifier: String = ""
    var customDisplayName: String = ""
    var customVersion: String = ""
    /// Firma adhoc: nessuna identità, utile solo con TrollStore o per prove.
    var adhoc: Bool = false
    /// Non scrivere `embedded.mobileprovision` nel bundle.
    var removeProvision: Bool = false
}

/// A che punto è la firma, per la barra di avanzamento.
enum SigningStage: Equatable {
    case preparing
    case extracting
    case signing
    case packaging
    case done

    var label: String {
        switch self {
        case .preparing:  return "Preparazione"
        case .extracting: return "Estrazione dell'archivio"
        case .signing:    return "Firma del bundle"
        case .packaging:  return "Ricostruzione dell'IPA"
        case .done:       return "Completato"
        }
    }

    var fraction: Double {
        switch self {
        case .preparing:  return 0.05
        case .extracting: return 0.25
        case .signing:    return 0.65
        case .packaging:  return 0.9
        case .done:       return 1.0
        }
    }
}

enum SigningError: LocalizedError {
    case wrongPassword
    case zsignFailed
    case profileExpired
    case bundleNotAllowed(pattern: String, bundleID: String)

    var errorDescription: String? {
        switch self {
        case .wrongPassword:
            return "La password del .p12 non è corretta."
        case .zsignFailed:
            return "zsign non è riuscito a firmare il bundle. Controlla che il .p12 e il .mobileprovision siano la coppia giusta."
        case .profileExpired:
            return "Il provisioning profile è scaduto: va rigenerato sul portale Apple Developer."
        case .bundleNotAllowed(let pattern, let bundleID):
            return "Il profilo copre \(pattern) e non può firmare \(bundleID). Cambia il bundle id nelle opzioni di firma, oppure usa un profilo con App ID jolly."
        }
    }
}

/// Esito della firma.
struct SigningResult {
    var signedIPA: URL
    var metadata: BundleMetadata
    var sizeBytes: Int64
}

enum SigningService {
    /// Verifica che la password apra il .p12, senza firmare niente.
    ///
    /// Serve anche il profilo, per una ragione poco ovvia: il controllo di zsign
    /// carica esplicitamente il provider "legacy" di OpenSSL per leggere i .p12
    /// vecchio stile, e in OpenSSL 3 caricare un provider a mano impedisce il
    /// caricamento automatico di quello di default — che è dove sta SHA-1, usato
    /// per verificare il MAC del .p12. Senza SHA-1 la verifica fallisce anche con
    /// la password giusta. Aprire prima una struttura CMS (il profilo è una
    /// struttura CMS) forza l'inizializzazione del provider di default, così
    /// restano attivi entrambi. zsign espone questo rimedio come
    /// `password_check_fix`.
    static func passwordOpens(p12 url: URL, provision: URL, password: String) -> Bool {
        password_check_fix(provision.path)
        defer { password_check_fix_free(provision.path) }
        return p12_password_check(url.path, password)
    }

    /// Firma una app della libreria e produce `signed.ipa` nella sua cartella.
    static func sign(
        app: LibraryApp,
        identity: SigningIdentity,
        options: SigningOptions,
        progress: @escaping (SigningStage) -> Void
    ) async throws -> SigningResult {
        progress(.preparing)

        if identity.profile.isExpired { throw SigningError.profileExpired }

        let password = identity.password
        if !options.adhoc,
           !passwordOpens(p12: identity.p12URL, provision: identity.provisionURL, password: password) {
            throw SigningError.wrongPassword
        }

        let targetBundleID = options.customBundleIdentifier.isEmpty
            ? app.bundleIdentifier
            : options.customBundleIdentifier

        if !options.adhoc, !identity.profile.allows(bundleID: targetBundleID) {
            throw SigningError.bundleNotAllowed(
                pattern: identity.profile.bundleIDPattern,
                bundleID: targetBundleID
            )
        }

        let work = Paths.newWorkDir("sign")
        defer { try? FileManager.default.removeItem(at: work) }

        progress(.extracting)
        let payload = try IPAArchive.extract(ipa: app.sourceIPA, into: work)
        let bundle = try IPAArchive.appBundle(inPayload: payload)

        progress(.signing)
        let ok = Zsign.sign(
            appPath: bundle.path,
            provisionPath: options.adhoc ? "" : identity.provisionURL.path,
            p12Path: options.adhoc ? "" : identity.p12URL.path,
            p12Password: options.adhoc ? "" : password,
            entitlementsPath: "",
            customIdentifier: options.customBundleIdentifier,
            customName: options.customDisplayName,
            customVersion: options.customVersion,
            adhoc: options.adhoc,
            removeProvision: options.removeProvision
        )
        guard ok else { throw SigningError.zsignFailed }

        progress(.packaging)
        let metadata = try IPAArchive.metadata(ofAppBundle: bundle)
        try IPAArchive.pack(payload: payload, to: app.signedIPA)

        let size = Int64((try? app.signedIPA.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        progress(.done)

        return SigningResult(signedIPA: app.signedIPA, metadata: metadata, sizeBytes: size)
    }
}
