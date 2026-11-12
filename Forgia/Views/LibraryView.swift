import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var store: Store
    @State private var showingImporter = false
    @State private var importing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.apps.isEmpty && !importing {
                    EmptyStateView(
                        icon: "tray.and.arrow.down",
                        title: "Nessuna app",
                        message: "Importa un file .ipa non firmato per cominciare. Puoi anche aprirlo da File o condividerlo verso Forgia."
                    )
                } else {
                    List {
                        if importing {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Importazione in corso…").foregroundStyle(.secondary)
                            }
                        }
                        ForEach(store.apps) { app in
                            NavigationLink(value: app.id) {
                                row(for: app)
                            }
                        }
                        .onDelete(perform: deleteRows)
                    }
                }
            }
            .navigationTitle("Libreria")
            .navigationDestination(for: UUID.self) { id in
                if let app = store.apps.first(where: { $0.id == id }) {
                    AppDetailView(appID: app.id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Importa IPA", systemImage: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [UTType.item],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .alert("Importazione non riuscita", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func row(for app: LibraryApp) -> some View {
        HStack(spacing: 12) {
            AppIconView(app: app)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StatusChip(text: app.versionDescription, tone: .neutral)
                    if app.isSigned {
                        StatusChip(text: "Firmata qui", tone: .ok, icon: "checkmark.seal")
                    } else if app.sourceIsSigned {
                        StatusChip(text: "Già firmata", tone: .ok, icon: "seal")
                    } else {
                        StatusChip(text: "Non firmata", tone: .warning, icon: "exclamationmark.triangle")
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func deleteRows(_ offsets: IndexSet) {
        for index in offsets {
            store.delete(store.apps[index])
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
            return
        }
        let candidates = urls.filter { ["ipa", "tipa"].contains($0.pathExtension.lowercased()) }
        guard !candidates.isEmpty else {
            errorMessage = "Seleziona un file con estensione .ipa."
            return
        }

        importing = true
        Task {
            for url in candidates {
                do {
                    _ = try await store.importIPA(from: url)
                } catch {
                    errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
            importing = false
        }
    }
}
