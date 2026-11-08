import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: Store
    @State private var importMessage: String?

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Libreria", systemImage: "square.stack.3d.up") }
            IdentitiesView()
                .tabItem { Label("Certificati", systemImage: "lock.doc") }
            SettingsView()
                .tabItem { Label("Impostazioni", systemImage: "gearshape") }
        }
        // Un .ipa aperto da File, da Safari o condiviso verso Forgia.
        .onOpenURL { url in
            handleIncoming(url)
        }
        .alert("Apertura del file", isPresented: .constant(importMessage != nil)) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func handleIncoming(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        Task {
            do {
                switch ext {
                case "ipa", "tipa":
                    let app = try await store.importIPA(from: url)
                    importMessage = "\(app.displayName) aggiunta alla libreria."
                default:
                    importMessage = "Forgia apre solo file .ipa. Per i certificati usa la scheda Certificati."
                }
            } catch {
                importMessage = error.localizedDescription
            }
            // I file consegnati nella Inbox restano lì: vanno ripuliti.
            if url.path.contains("/Inbox/") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
