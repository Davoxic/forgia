import SwiftUI

struct AppDetailView: View {
    let appID: UUID

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var installer: InstallService

    @State private var showingSignSheet = false
    @State private var showingInstallSheet = false

    private var app: LibraryApp? { store.apps.first(where: { $0.id == appID }) }

    var body: some View {
        Group {
            if let app {
                content(app)
            } else {
                EmptyStateView(icon: "questionmark.folder", title: "App non trovata", message: "È stata rimossa dalla libreria.")
            }
        }
    }

    private func content(_ app: LibraryApp) -> some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AppIconView(app: app, side: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.displayName).font(.title3.weight(.semibold))
                        Text(app.bundleIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Versione \(app.versionDescription)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Pacchetto originale") {
                DetailRow(label: "Dimensione", value: Paths.byteString(app.sourceSizeBytes))
                if !app.minimumOSVersion.isEmpty {
                    DetailRow(label: "iOS minimo", value: app.minimumOSVersion)
                }
                DetailRow(label: "Importata", value: app.importedAt.shortItalian)
            }

            if let signature = app.signature, app.isSigned {
                Section("Firma") {
                    DetailRow(label: "Certificato", value: signature.identityLabel)
                    DetailRow(label: "Bundle id", value: signature.signedBundleIdentifier, monospaced: true)
                    DetailRow(label: "Nome", value: signature.signedDisplayName)
                    DetailRow(label: "Versione", value: signature.signedVersion)
                    DetailRow(label: "Dimensione", value: Paths.byteString(signature.sizeBytes))
                    DetailRow(label: "Firmata il", value: signature.signedAt.shortItalian)
                    if let expiry = signature.profileExpiration {
                        DetailRow(label: "Il profilo scade", value: expiry.shortItalian)
                    }
                }
            }

            Section {
                Button {
                    showingSignSheet = true
                } label: {
                    Label(app.isSigned ? "Firma di nuovo" : "Firma", systemImage: "signature")
                }
                .disabled(store.identities.isEmpty)

                if app.isSigned {
                    Button {
                        showingInstallSheet = true
                    } label: {
                        Label("Installa sul telefono", systemImage: "arrow.down.app")
                    }
                    ShareLink(item: app.signedIPA) {
                        Label("Esporta l'IPA firmato", systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                if store.identities.isEmpty {
                    Text("Importa prima un certificato nella scheda Certificati.")
                } else if app.isSigned {
                    Text("Se l'installazione via iOS non va a buon fine, esporta l'IPA e installalo con Sideloadly o AltStore: il file è già firmato.")
                }
            }

            if app.isSigned {
                Section {
                    Button(role: .destructive) {
                        store.discardSignature(of: app)
                    } label: {
                        Label("Elimina la versione firmata", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSignSheet) {
            SignSheet(appID: app.id)
        }
        .sheet(isPresented: $showingInstallSheet) {
            InstallSheet(appID: app.id)
        }
    }
}
