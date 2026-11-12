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
            .fileImporter(
                isPresented: $showingPicker,
                allowedContentTypes: [UTType.item],
                allowsMultipleSelection: true
            ) { result in
                handlePick(result)
            }
            .alert("Non riuscito", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
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
    private func handlePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
            return
        case .success(let urls):
            guard !urls.isEmpty else {
                errorMessage = "Non è stato selezionato nessun file."
                return
            }

            var problems: [String] = []
            var accepted = 0

            for url in urls {
                let ext = url.pathExtension.lowercased()
                guard ext == "p12" || ext == "pfx" || ext == "mobileprovision" else {
                    problems.append("\(url.lastPathComponent): estensione .\(ext.isEmpty ? "(nessuna)" : ext) non riconosciuta")
                    continue
                }

                let staged: URL
                do {
                    staged = try stage(url)
                } catch {
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
    }

    /// Copia il file scelto in una cartella di lavoro, finché il permesso è valido.
    private func stage(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var readError: NSError?
        var payload: Data?
        var coordinationError: Error?

        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &readError) { readable in
            do { payload = try Data(contentsOf: readable) }
            catch { coordinationError = error }
        }
        if let readError { throw readError }
        if let coordinationError { throw coordinationError }
        guard let payload else { throw CocoaError(.fileReadUnknown) }

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
