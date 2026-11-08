import SwiftUI

struct SignSheet: View {
    let appID: UUID

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIdentityID: UUID?
    @State private var options = SigningOptions()
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
                } header: {
                    Text("Bundle identifier")
                } footer: {
                    if mismatch, let identity {
                        Text("Il profilo copre \(identity.profile.bundleIDPattern): con questo bundle id la firma verrà rifiutata da iOS. Cambialo in qualcosa che rientri nel profilo.")
                            .foregroundStyle(.red)
                    } else if let identity, identity.profile.isWildcard {
                        Text("Il profilo ha un App ID jolly: va bene qualunque bundle id che inizi per \(identity.profile.bundleIDPattern.replacingOccurrences(of: "*", with: ""))")
                    }
                }

                Section("Opzionali") {
                    TextField("Nome visualizzato", text: $options.customDisplayName)
                    TextField("Versione", text: $options.customVersion)
                        .keyboardType(.numbersAndPunctuation)
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
        }
    }

    private func run() {
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
