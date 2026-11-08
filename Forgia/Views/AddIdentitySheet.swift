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
    @State private var pickingTarget: Picking?
    @State private var errorMessage: String?
    @State private var preview: ProvisioningProfile?

    private enum Picking {
        case p12, provision
    }

    private var canSave: Bool { p12URL != nil && provisionURL != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    pickerRow(
                        title: "File .p12",
                        detail: p12URL?.lastPathComponent,
                        icon: "key.fill"
                    ) { pickingTarget = .p12; showingPicker = true }

                    pickerRow(
                        title: "File .mobileprovision",
                        detail: provisionURL?.lastPathComponent,
                        icon: "doc.badge.gearshape"
                    ) { pickingTarget = .provision; showingPicker = true }
                } footer: {
                    Text("Sono i due file che esporti dal portale Apple Developer: il .p12 con la chiave privata del certificato, e il provisioning profile dell'App ID.")
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
                allowsMultipleSelection: false
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

    private func handlePick(_ result: Result<[URL], Error>) {
        let target = pickingTarget
        pickingTarget = nil
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
            return
        }

        let ext = url.pathExtension.lowercased()
        switch target {
        case .p12:
            guard ext == "p12" || ext == "pfx" else {
                errorMessage = "Serve un file .p12."
                return
            }
        case .provision:
            guard ext == "mobileprovision" else {
                errorMessage = "Serve un file .mobileprovision."
                return
            }
        case nil:
            return
        }

        // Il permesso sull'URL del picker vale una volta sola: appena chiuso non
        // si riapre. Quindi il file va messo al sicuro adesso, e da qui in poi si
        // lavora sulla copia.
        let staged: URL
        do {
            staged = try stage(url)
        } catch {
            errorMessage = "Non riesco a leggere \(url.lastPathComponent): \(error.localizedDescription)"
            return
        }

        switch target {
        case .p12:
            p12URL = staged
        case .provision:
            provisionURL = staged
            loadPreview(staged)
        case nil:
            break
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
