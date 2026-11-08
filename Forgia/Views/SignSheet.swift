import SwiftUI
import PhotosUI

struct SignSheet: View {
    let appID: UUID

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIdentityID: UUID?
    @State private var options = SigningOptions()
    @State private var iconItem: PhotosPickerItem?
    @State private var iconPreview: UIImage?
    @State private var stage: SigningStage?
    @State private var errorMessage: String?
    @State private var finished = false

    private var app: LibraryApp? { store.apps.first(where: { $0.id == appID }) }
    private var identity: SigningIdentity? {
        store.identities.first(where: { $0.id == selectedIdentityID })
    }

    /// Il bundle id che finirà nell'app firmata.
    private var effectiveBundleID: String {
        options.customBundleIdentifier.isEmpty
            ? (app?.bundleIdentifier ?? "")
            : options.customBundleIdentifier
    }

    /// Il bundle id imposto dal profilo è quello che occupa SborrSign stesso.
    private var collidesWithSelf: Bool {
        guard let own = Bundle.main.bundleIdentifier else { return false }
        return !effectiveBundleID.isEmpty && effectiveBundleID == own
    }

    private var mismatch: Bool {
        guard let identity, !options.adhoc, !effectiveBundleID.isEmpty else { return false }
        return !identity.profile.allows(bundleID: effectiveBundleID)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let app {
                    Section {
                        HStack(spacing: 12) {
                            AppIconView(app: app, side: 44)
                            VStack(alignment: .leading) {
                                Text(app.displayName).font(.body.weight(.medium))
                                Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Certificato") {
                    if store.identities.isEmpty {
                        Text("Nessun certificato importato.").foregroundStyle(.secondary)
                    } else {
                        Picker("Identità", selection: $selectedIdentityID) {
                            ForEach(store.identities) { candidate in
                                Text(candidate.label).tag(Optional(candidate.id))
                            }
                        }
                        if let identity {
                            DetailRow(label: "Copre", value: identity.profile.bundleIDPattern, monospaced: true)
                            DetailRow(label: "Tipo", value: identity.profile.kindDescription)
                            HStack {
                                Text("Validità").foregroundStyle(.secondary)
                                Spacer()
                                StatusChip(
                                    text: identity.expiryDescription,
                                    tone: identity.profile.isExpired ? .danger : .ok
                                )
                            }
                        }
                    }
                }

                Section {
                    TextField("Lascia vuoto per non cambiarlo", text: $options.customBundleIdentifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())

                    if let identity, !identity.profile.bundleIDPattern.contains("*") {
                        Button("Usa l'App ID del profilo") {
                            options.customBundleIdentifier = identity.profile.bundleIDPattern
                        }
                        .font(.callout)
                    }
                } header: {
                    Text("Bundle identifier")
                } footer: {
                    if collidesWithSelf {
                        Text("È lo stesso bundle id di SborrSign: installare questa app cancellerebbe SborrSign dal telefono. Mettine uno diverso.")
                            .foregroundStyle(.red)
                    } else if mismatch, let identity {
                        Text("Fuori dall'App ID del profilo (\(identity.profile.bundleIDPattern)). Puoi firmare lo stesso, ma se iOS lo rifiuta in installazione è questo il motivo. Ogni app deve comunque avere un bundle id suo: due app con lo stesso identificativo si sostituiscono a vicenda.")
                            .foregroundStyle(.orange)
                    } else if let identity, identity.profile.isWildcard {
                        Text("Il profilo ha un App ID jolly: va bene qualunque bundle id che inizi per \(identity.profile.bundleIDPattern.replacingOccurrences(of: "*", with: ""))")
                    } else {
                        Text("Vuoto significa che l'app tiene il suo bundle id originale. Cambialo solo se sai perché: due app con lo stesso identificativo si sostituiscono a vicenda.")
                    }
                }

                Section {
                    TextField(app?.displayName ?? "Nome visualizzato", text: $options.customDisplayName)

                    PhotosPicker(selection: $iconItem, matching: .images) {
                        HStack {
                            Label("Icona", systemImage: "photo")
                            Spacer()
                            if let iconPreview {
                                Image(uiImage: iconPreview)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else {
                                Text("Scegli una foto")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if options.customIconFile != nil {
                        Button("Rimetti l'icona originale", role: .destructive) {
                            options.customIconFile = nil
                            iconPreview = nil
                            iconItem = nil
                        }
                    }

                    TextField("Versione", text: $options.customVersion)
                        .keyboardType(.numbersAndPunctuation)
                } header: {
                    Text("Aspetto")
                } footer: {
                    Text("Il nome è quello sotto l'icona nella schermata Home. La foto viene ritagliata al centro in un quadrato e scritta nel bundle al posto dell'icona: su qualche app non attecchisce, perché l'icona sta in un catalogo compilato che non si può riscrivere.")
                }

                Section {
                    Toggle("Non incorporare il profilo", isOn: $options.removeProvision)
                    Toggle("Firma adhoc", isOn: $options.adhoc)
                } footer: {
                    Text("La firma adhoc non usa nessun certificato: serve solo con TrollStore o per ispezionare il bundle. Per installare normalmente lasciala spenta.")
                }

                if let stage {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: stage.fraction)
                            Text(stage.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Firma")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                        .disabled(stage != nil && !finished)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Firma") { run() }
                        .disabled(identity == nil || (stage != nil && !finished))
                }
            }
            .alert("Firma non riuscita", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil; stage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                if selectedIdentityID == nil {
                    selectedIdentityID = store.preferredIdentity?.id
                }
            }
            .onChange(of: iconItem) { _, item in
                Task { await loadIcon(item) }
            }
        }
    }

    /// Porta la foto scelta in un file, pronto per la firma.
    @MainActor private func loadIcon(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            errorMessage = "Non riesco a leggere quella foto."
            return
        }

        let destination = Paths.newWorkDir("icon").appendingPathComponent("icon.png")
        guard let png = image.pngData(), (try? png.write(to: destination)) != nil else {
            errorMessage = "Non riesco a preparare l'icona."
            return
        }

        iconPreview = image
        options.customIconFile = destination
    }

    @MainActor private func run() {
        guard let app, let identity else { return }
        stage = .preparing
        finished = false

        Task {
            do {
                let result = try await SigningService.sign(
                    app: app,
                    identity: identity,
                    options: options,
                    progress: { newStage in
                        Task { @MainActor in stage = newStage }
                    }
                )

                var updated = app
                updated.signature = LibraryApp.SignatureInfo(
                    identityID: identity.id,
                    identityLabel: identity.label,
                    signedBundleIdentifier: result.metadata.bundleIdentifier,
                    signedDisplayName: result.metadata.displayName,
                    signedVersion: result.metadata.version,
                    signedAt: Date(),
                    sizeBytes: result.sizeBytes,
                    profileExpiration: identity.profile.expirationDate
                )
                store.update(updated)
                finished = true
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
