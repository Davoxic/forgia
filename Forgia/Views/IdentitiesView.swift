import SwiftUI

struct IdentitiesView: View {
    @EnvironmentObject private var store: Store
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if store.identities.isEmpty {
                    EmptyStateView(
                        icon: "lock.doc",
                        title: "Nessun certificato",
                        message: "Aggiungi la coppia .p12 e .mobileprovision del tuo account sviluppatore. La password del .p12 finisce nel Keychain, non in un file."
                    )
                } else {
                    List {
                        ForEach(store.identities) { identity in
                            NavigationLink {
                                IdentityDetailView(identityID: identity.id)
                            } label: {
                                row(identity)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { store.delete(store.identities[index]) }
                        }
                    }
                }
            }
            .navigationTitle("Certificati")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Label("Aggiungi", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddIdentitySheet()
            }
            .onChange(of: store.pendingBump) { _, _ in
                showingAdd = true
            }
            .onAppear {
                if store.pendingP12 != nil || store.pendingProvision != nil {
                    showingAdd = true
                }
            }
        }
    }

    private func row(_ identity: SigningIdentity) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(identity.label).font(.body.weight(.medium)).lineLimit(1)
            Text(identity.subtitle).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                StatusChip(
                    text: identity.profile.isExpired ? "Scaduto" : "Valido",
                    tone: identity.profile.isExpired ? .danger : .ok,
                    icon: identity.profile.isExpired ? "xmark.seal" : "checkmark.seal"
                )
                StatusChip(text: identity.profile.bundleIDPattern, tone: .neutral)
            }
        }
        .padding(.vertical, 3)
    }
}

struct IdentityDetailView: View {
    let identityID: UUID
    @EnvironmentObject private var store: Store

    private var identity: SigningIdentity? {
        store.identities.first(where: { $0.id == identityID })
    }

    var body: some View {
        Group {
            if let identity {
                List {
                    Section("Profilo") {
                        DetailRow(label: "Nome", value: identity.profile.name)
                        DetailRow(label: "App ID", value: identity.profile.appIDName)
                        DetailRow(label: "Identificatore", value: identity.profile.applicationIdentifier, monospaced: true)
                        DetailRow(label: "Tipo", value: identity.profile.kindDescription)
                        DetailRow(label: "UUID", value: identity.profile.uuid, monospaced: true)
                    }
                    Section("Team") {
                        DetailRow(label: "Nome", value: identity.profile.teamName)
                        DetailRow(label: "Team ID", value: identity.profile.teamIdentifier, monospaced: true)
                        ForEach(identity.profile.certificateNames, id: \.self) { name in
                            DetailRow(label: "Certificato", value: name)
                        }
                    }
                    Section("Validità") {
                        HStack {
                            Text("Stato").foregroundStyle(.secondary)
                            Spacer()
                            StatusChip(
                                text: identity.expiryDescription,
                                tone: identity.profile.isExpired ? .danger : .ok
                            )
                        }
                        if let created = identity.profile.creationDate {
                            DetailRow(label: "Creato", value: created.shortItalian)
                        }
                    }
                    Section {
                        if identity.profile.isEnterprise {
                            Text("Profilo enterprise: installa su qualsiasi dispositivo, non serve registrare l'UDID.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if identity.profile.provisionedDevices.isEmpty {
                            Text("Questo profilo non elenca dispositivi: le app firmate potrebbero non installarsi.")
                                .font(.footnote).foregroundStyle(.orange)
                        } else {
                            ForEach(identity.profile.provisionedDevices, id: \.self) { udid in
                                Text(udid).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Dispositivi autorizzati (\(identity.profile.provisionedDevices.count))")
                    } footer: {
                        if !identity.profile.isEnterprise {
                            Text("L'UDID del tuo iPhone deve essere in questa lista, altrimenti iOS rifiuta l'installazione.")
                        }
                    }
                    Section {
                        Button(role: .destructive) {
                            store.delete(identity)
                        } label: {
                            Label("Elimina il certificato", systemImage: "trash")
                        }
                    }
                }
                .navigationTitle(identity.label)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                EmptyStateView(icon: "questionmark.folder", title: "Non trovato", message: "Il certificato è stato rimosso.")
            }
        }
    }
}
