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
                HStack {
                    Text("Firma").foregroundStyle(.secondary)
                    Spacer()
                    if app.sourceIsSigned {
                        StatusChip(text: "già firmato", tone: .ok, icon: "checkmark.seal")
                    } else {
                        StatusChip(text: "non firmato", tone: .warning, icon: "exclamationmark.triangle")
                    }
                }
            }

            if let profile = app.sourceProfile, !app.isSigned {
                Section {
                    DetailRow(label: "Team", value: profile.teamName)
                    DetailRow(label: "App ID", value: profile.applicationIdentifier, monospaced: true)
                    DetailRow(label: "Tipo", value: profile.kindDescription)
                    HStack {
                        Text("Validità").foregroundStyle(.secondary)
                        Spacer()
                        StatusChip(
                            text: profile.expirationDate?.shortItalian ?? "sconosciuta",
                            tone: profile.isExpired ? .danger : .ok
                        )
                    }
                    if !profile.isEnterprise {
                        DetailRow(
                            label: "Dispositivi",
                            value: String(profile.provisionedDevices.count)
                        )
                    }
                } header: {
                    Text("Firma già presente nell'archivio")
                } footer: {
                    if profile.isExpired {
                        Text("Questo profilo è scaduto: iOS rifiuterà l'installazione. Rifirma l'app con un tuo certificato.")
                            .foregroundStyle(.red)
                    } else if !profile.isEnterprise && !profile.provisionedDevices.isEmpty {
                        Text("Si installerà solo se l'UDID di questo iPhone è tra quelli del profilo. Se iOS rifiuta, rifirmala con il tuo certificato.")
                    }
                }
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
                if app.canInstall {
                    Button {
                        showingInstallSheet = true
                    } label: {
                        Label("Installa sul telefono", systemImage: "arrow.down.app")
                    }
                }

                Button {
                    showingSignSheet = true
                } label: {
                    Label(app.isSigned ? "Firma di nuovo" : "Firma con un mio certificato",
                          systemImage: "signature")
                }
                .disabled(store.identities.isEmpty)

                if let package = app.installableIPA {
                    ShareLink(item: package) {
                        Label("Esporta l'IPA", systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                if !app.canInstall {
                    Text("L'archivio non porta nessuna firma, quindi iOS lo rifiuterebbe. Firmalo con un tuo certificato e poi installalo.")
                } else if !app.isSigned {
                    Text("L'archivio è già firmato: puoi installarlo così com'è. Rifirmalo solo se la sua firma è scaduta, se non copre questo iPhone, o se vuoi cambiargli nome o icona.")
                } else {
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
