import SwiftUI
import UniformTypeIdentifiers

struct AddIdentitySheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var p12URL: URL?
    @State private var provisionURL: URL?
    @State private var password = ""
    @State private var label = ""
    @State private var showingPicker = false
    @State private var diagnostics: [String] = []
    @State private var errorMessage: String?
    @State private var preview: ProvisioningProfile?

    private var canSave: Bool { p12URL != nil && provisionURL != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    pickerRow(
                        title: "File .p12",
                        detail: p12URL?.lastPathComponent,
                        icon: "key.fill"
                    ) { showingPicker = true }

                    pickerRow(
                        title: "File .mobileprovision",
                        detail: provisionURL?.lastPathComponent,
                        icon: "doc.badge.gearshape"
                    ) { showingPicker = true }
                } footer: {
                    Text("Sono i due file che esporti dal portale Apple Developer: il .p12 con la chiave privata del certificato, e il provisioning profile dell'App ID. Puoi selezionarli anche insieme: Forgia capisce dall'estensione qual è quale.")
                }

                Section("Password del .p12") {
                    SecureField("Lascia vuoto se non ne ha", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Nome") {
                    TextField(preview?.name ?? "Opzionale", text: $label)
                }

                if !diagnostics.isEmpty {
                    Section("Diagnostica") {
                        ForEach(Array(diagnostics.enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let preview {
                    Section("Letto dal profilo") {
                        DetailRow(label: "Team", value: preview.teamName)
                        DetailRow(label: "Copre", value: preview.bundleIDPattern, monospaced: true)
                        DetailRow(label: "Tipo", value: preview.kindDescription)
                        DetailRow(label: "Dispositivi", value: preview.isEnterprise ? "tutti" : String(preview.provisionedDevices.count))
                        if let expiry = preview.expirationDate {
                            HStack {
                                Text("Scadenza").foregroundStyle(.secondary)
                                Spacer()
                                StatusChip(
                                    text: expiry.shortItalian,
                                    tone: preview.isExpired ? .danger : .ok
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nuovo certificato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }.disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingPicker) {
                DocumentPicker(
                    onPick: { urls in
                        showingPicker = false
                        handlePick(urls)
                    },
                    onCancel: { showingPicker = false }
                )
                .ignoresSafeArea()
            }
            .alert("Non riuscito", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { collectIncoming() }
        }
    }

    private func pickerRow(
        title: String,
        detail: String?,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text(detail ?? "Scegli")
                    .font(.caption)
                    .foregroundStyle(detail == nil ? .secondary : .primary)
                    .lineLimit(1)
            }
        }
    }

    /// Smista i file scelti guardando l'estensione, non quale pulsante è stato
    /// premuto: così non c'è nessuno stato da perdere fra l'apertura del
    /// selettore e la risposta.
    private func handlePick(_ urls: [URL]) {
        note("Selettore: \(urls.count) file")
        guard !urls.isEmpty else {
            errorMessage = "Non è stato selezionato nessun file."
            return
        }

        var problems: [String] = []
        var accepted = 0

        for url in urls {
            let ext = url.pathExtension.lowercased()
            note("· \(url.lastPathComponent) [.\(ext.isEmpty ? "nessuna estensione" : ext)]")

            guard ext == "p12" || ext == "pfx" || ext == "mobileprovision" else {
                problems.append("\(url.lastPathComponent): estensione non riconosciuta")
                continue
            }

            let staged: URL
            do {
                staged = try stage(url)
                note("  copiato, \(Paths.byteString(Int64((try? staged.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)))")
            } catch {
                note("  errore: \(error.localizedDescription)")
                problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }

            if ext == "mobileprovision" {
                provisionURL = staged
                loadPreview(staged)
            } else {
                p12URL = staged
            }
            accepted += 1
        }

        if accepted == 0 {
            errorMessage = problems.isEmpty
                ? "Nessun file utilizzabile: servono un .p12 e un .mobileprovision."
                : problems.joined(separator: "\n")
        } else if !problems.isEmpty {
            errorMessage = problems.joined(separator: "\n")
        }
    }

    /// Raccoglie i file arrivati tramite Condividi o "Apri in Forgia".
    private func collectIncoming() {
        if let incoming = store.pendingP12 {
            p12URL = incoming
            store.pendingP12 = nil
            note("Ricevuto da fuori: \(incoming.lastPathComponent)")
        }
        if let incoming = store.pendingProvision {
            provisionURL = incoming
            store.pendingProvision = nil
            note("Ricevuto da fuori: \(incoming.lastPathComponent)")
            loadPreview(incoming)
        }
    }

    private func note(_ line: String) {
        diagnostics.append(line)
    }

    /// Porta il file in una cartella di lavoro nostra. Il selettore lo consegna
    /// gia' copiato nella cartella temporanea, che iOS puo' svuotare quando
    /// vuole: qui diventa stabile fino al salvataggio.
    private func stage(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let payload = try Data(contentsOf: url)
        let destination = Paths.newWorkDir("pick").appendingPathComponent(url.lastPathComponent)
        try payload.write(to: destination, options: .atomic)
        return destination
    }

    private func loadPreview(_ url: URL) {
        do {
            preview = try ProvisioningProfile.parse(contentsOf: url)
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let p12URL, let provisionURL else { return }
        do {
            _ = try store.importIdentity(
                p12: p12URL,
                provision: provisionURL,
                password: password,
                label: label.isEmpty ? nil : label
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
