import SwiftUI

struct InstallSheet: View {
    let appID: UUID

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var installer: InstallService
    @Environment(\.dismiss) private var dismiss

    private var app: LibraryApp? { store.apps.first(where: { $0.id == appID }) }

    var body: some View {
        NavigationStack {
            List {
                if let app {
                    Section {
                        HStack(spacing: 12) {
                            AppIconView(app: app, side: 44)
                            VStack(alignment: .leading) {
                                Text(app.signature?.signedDisplayName ?? app.displayName)
                                    .font(.body.weight(.medium))
                                Text(app.signature?.signedBundleIdentifier ?? app.bundleIdentifier)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Modalità") {
                    DetailRow(label: "Consegna", value: settings.installMode.title)
                    DetailRow(label: "Porta", value: String(settings.serverPort))
                    if settings.installMode == .remoteManifest {
                        DetailRow(label: "Indirizzo", value: settings.useLoopback ? "127.0.0.1" : (NetworkInterface.localIPv4() ?? "non disponibile"))
                    } else {
                        DetailRow(label: "Nome host", value: settings.tlsCommonName.isEmpty ? "non impostato" : settings.tlsCommonName)
                    }
                }

                Section("Stato") {
                    statusView
                    if !installer.events.isEmpty {
                        ForEach(Array(installer.events.enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    if installer.phase.isBusy {
                        Button(role: .destructive) {
                            installer.cancel()
                        } label: {
                            Label("Interrompi e spegni il server", systemImage: "stop.circle")
                        }
                        Button {
                            installer.markDelivered()
                        } label: {
                            Label("L'installazione è partita", systemImage: "checkmark.circle")
                        }
                    } else {
                        Button {
                            start()
                        } label: {
                            Label("Avvia l'installazione", systemImage: "arrow.down.app")
                        }
                    }
                } footer: {
                    Text("iOS chiede conferma e scarica il pacchetto dal server che Forgia tiene aperto. Non chiudere l'app finché l'icona non è comparsa nella schermata Home.")
                }
            }
            .navigationTitle("Installa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") {
                        installer.cancel()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch installer.phase {
        case .idle:
            Text("In attesa").foregroundStyle(.secondary)
        case .preparing:
            HStack { ProgressView(); Text("Preparazione del server") }
        case .handedToSystem:
            HStack { ProgressView(); Text("In attesa di iOS") }
        case .transferring:
            HStack { ProgressView(); Text("Trasferimento del pacchetto") }
        case .delivered:
            Label("Consegnato a iOS", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private func start() {
        guard let app else { return }
        Task { await installer.install(app: app, settings: settings) }
    }
}
