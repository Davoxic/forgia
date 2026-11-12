import Foundation
import Combine

/// Stato dell'app: la libreria delle app e i certificati importati, con la loro
/// persistenza su disco.
@MainActor
final class Store: ObservableObject {
    @Published var apps: [LibraryApp] = []
    @Published var identities: [SigningIdentity] = []
    @Published var lastError: String?

    init() {
        Paths.bootstrap()
        IPAArchive.registerExtensions()
        load()
    }

    // MARK: - Persistenza

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Paths.libraryIndex) {
            apps = (try? decoder.decode([LibraryApp].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: Paths.identityIndex) {
            identities = (try? decoder.decode([SigningIdentity].self, from: data)) ?? []
        }
        // Scarta le voci la cui cartella è sparita.
        apps = apps.filter { FileManager.default.fileExists(atPath: $0.sourceIPA.path) }
        identities = identities.filter { FileManager.default.fileExists(atPath: $0.p12URL.path) }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(apps) {
            try? data.write(to: Paths.libraryIndex, options: .atomic)
        }
        if let data = try? encoder.encode(identities) {
            try? data.write(to: Paths.identityIndex, options: .atomic)
        }
    }

    // MARK: - Libreria

    /// Importa un IPA: lo copia nel container, ne legge i metadati e l'icona.
    /// L'estrazione gira fuori dal main actor, altrimenti un IPA grosso
    /// bloccherebbe l'interfaccia.
    func importIPA(from source: URL) async throws -> LibraryApp {
        let app = try await Self.prepareImport(from: source)
        apps.insert(app, at: 0)
        save()
        return app
    }

    nonisolated private static func prepareImport(from source: URL) async throws -> LibraryApp {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let work = Paths.newWorkDir("import")
            defer { try? fm.removeItem(at: work) }

            // Il file scelto col picker va letto subito: il permesso è temporaneo.
            let staged = work.appendingPathComponent(source.lastPathComponent)
            let needsScope = source.startAccessingSecurityScopedResource()
            defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                do { try fm.copyItem(at: readable, to: staged) }
                catch { copyError = error }
            }
            if let coordinationError { throw coordinationError }
            if let copyError { throw copyError }

            let extractDir = work.appendingPathComponent("x", isDirectory: true)
            let payload = try IPAArchive.extract(ipa: staged, into: extractDir)
            let bundle = try IPAArchive.appBundle(inPayload: payload)
            let metadata = try IPAArchive.metadata(ofAppBundle: bundle)

            var app = LibraryApp(
                displayName: metadata.displayName,
                bundleIdentifier: metadata.bundleIdentifier,
                version: metadata.version,
                build: metadata.build,
                minimumOSVersion: metadata.minimumOSVersion
            )

            try fm.createDirectory(at: app.directory, withIntermediateDirectories: true)
            try? fm.removeItem(at: app.sourceIPA)
            try fm.moveItem(at: staged, to: app.sourceIPA)

            app.sourceSizeBytes = Int64(
                (try? app.sourceIPA.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            )
            app.hasIcon = IPAArchive.extractIcon(
                fromAppBundle: bundle,
                baseNames: metadata.iconFileNames,
                to: app.iconFile
            )

            let existing = IPAArchive.signature(ofAppBundle: bundle)
            app.sourceIsSigned = existing.isSigned
            app.sourceProfile = existing.profile

            return app
        }.value
    }

    func update(_ app: LibraryApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index] = app
        save()
    }

    func delete(_ app: LibraryApp) {
        try? FileManager.default.removeItem(at: app.directory)
        apps.removeAll { $0.id == app.id }
        save()
    }

    func discardSignature(of app: LibraryApp) {
        var app = app
        try? FileManager.default.removeItem(at: app.signedIPA)
        app.signature = nil
        update(app)
    }

    // MARK: - Certificati

    func importIdentity(p12: URL, provision: URL, password: String, label: String?) throws -> SigningIdentity {
        let profile = try ProvisioningProfile.parse(contentsOf: provision)

        let identity = SigningIdentity(
            label: label?.isEmpty == false ? label! : profile.name,
            profile: profile
        )

        let dir = Paths.identityDir(identity.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try copy(p12, to: identity.p12URL)
        try copy(provision, to: identity.provisionURL)

        guard SigningService.passwordOpens(
            p12: identity.p12URL,
            provision: identity.provisionURL,
            password: password
        ) else {
            try? FileManager.default.removeItem(at: dir)
            throw SigningError.wrongPassword
        }
        Keychain.setPassword(password, for: identity.id)

        identities.insert(identity, at: 0)
        save()
        return identity
    }

    func delete(_ identity: SigningIdentity) {
        try? FileManager.default.removeItem(at: Paths.identityDir(identity.id))
        Keychain.deletePassword(for: identity.id)
        identities.removeAll { $0.id == identity.id }
        save()
    }

    /// Il certificato da proporre per primo: valido, e con più tempo davanti.
    var preferredIdentity: SigningIdentity? {
        identities
            .filter { !$0.profile.isExpired }
            .max { ($0.profile.expirationDate ?? .distantPast) < ($1.profile.expirationDate ?? .distantPast) }
            ?? identities.first
    }

    var totalStorageBytes: Int64 {
        Paths.directorySize(Paths.apps)
    }

    private func copy(_ source: URL, to destination: URL) throws {
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
