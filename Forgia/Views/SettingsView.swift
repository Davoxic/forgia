import UniformTypeIdentifiers
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: Store

    @State private var portText = ""
    @State private var showingTLSImporter = false
    @State private var tlsPassword = ""
    @State private var askingTLSPassword = false
    @State private var pendingTLSURL: URL?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Consegna", selection: $settings.installMode) {
                        ForEach(InstallMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } header: {
                    Text("Installazione")
                } footer: {
                    Text(settings.installMode.explanation)
                }

                Section("Server locale") {
                    HStack {
                        Text("Porta")
                        Spacer()
                        TextField("8898", text: $portText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .onSubmit(applyPort)
                    }
                    if settings.installMode == .remoteManifest {
                        Toggle("Usa 127.0.0.1", isOn: $settings.useLoopback)
                    }
                }

                if settings.installMode == .remoteManifest {
                    Section {
                        TextField("URL del servizio", text: $settings.manifestServiceURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption.monospaced())
                        Button("Ripristina quello predefinito") {
                            settings.resetManifestService()
                        }
                    } header: {
                        Text("Servizio manifest")
                    } footer: {
                        Text("iOS accetta il manifest di installazione solo via HTTPS con un certificato valido, cosa che un server sul telefono non può avere. Questo servizio genera quel piccolo file al posto nostro: riceve nome, bundle id e versione dell'app, non il pacchetto. Se preferisci non usarlo, passa alla modalità tutta locale o esporta l'IPA firmato.")
                    }
                }

                if settings.installMode == .fullyLocal {
                    Section {
                        TextField("es. local.miodominio.it", text: $settings.tlsCommonName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())

                        HStack {
                            Text("Certificato")
                            Spacer()
                            if TLSIdentityStore.isConfigured {
                                StatusChip(text: "importato", tone: .ok, icon: "checkmark")
                            } else {
                                StatusChip(text: "assente", tone: .warning)
                            }
                        }

                        Button("Importa un .p12 TLS") { showingTLSImporter = true }

                        if TLSIdentityStore.isConfigured {
                            Button(role: .destructive) {
                                TLSIdentityStore.remove()
                                message = "Certificato TLS rimosso."
                            } label: {
                                Text("Rimuovi il certificato TLS")
                            }
                        }
                    } header: {
                        Text("HTTPS locale")
                    } footer: {
                        Text("Serve un certificato per un nome host che risolva a 127.0.0.1, rilasciato da una CA che il telefono già si fida (quindi un dominio tuo con un record A su 127.0.0.1), oppure una CA tua installata e abilitata in Impostazioni → Generali → Info → Impostazioni di attendibilità certificati.")
                    }
                }

                Section("Spazio") {
                    DetailRow(label: "App in libreria", value: String(store.apps.count))
                    DetailRow(label: "Occupato", value: Paths.byteString(store.totalStorageBytes))
                }

                Section {
                    DetailRow(label: "Versione", value: Bundle.main.shortVersion)
                    DetailRow(
                        label: "Bundle id di questa app",
                        value: Bundle.main.bundleIdentifier ?? "sconosciuto",
                        monospaced: true
                    )
                    DetailRow(label: "Motore di firma", value: "zsign")
                } header: {
                    Text("SborrSign")
                } footer: {
                    Text("Firma solo app che hai il diritto di installare. Il certificato e la sua password restano sul telefono.")
                }
            }
            .navigationTitle("Impostazioni")
            .onAppear { portText = String(settings.serverPort) }
            .onChange(of: portText) { _, _ in applyPort() }
            .fileImporter(
                isPresented: $showingTLSImporter,
                allowedContentTypes: [UTType.item],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    pendingTLSURL = url
                    tlsPassword = ""
                    askingTLSPassword = true
                }
            }
            .alert("Password del certificato", isPresented: $askingTLSPassword) {
                SecureField("Password", text: $tlsPassword)
                Button("Importa") { importTLS() }
                Button("Annulla", role: .cancel) { pendingTLSURL = nil }
            }
            .alert("Impostazioni", isPresented: .constant(message != nil)) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func applyPort() {
        guard let value = Int(portText), value > 1024, value < 65535 else { return }
        settings.serverPort = value
    }

    private func importTLS() {
        guard let url = pendingTLSURL else { return }
        pendingTLSURL = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try TLSIdentityStore.store(p12: url, password: tlsPassword)
            message = "Certificato TLS importato."
        } catch {
            message = error.localizedDescription
        }
    }
}

extension Bundle {
    var shortVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
