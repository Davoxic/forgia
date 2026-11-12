import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: Store
    @State private var importMessage: String?
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem { Label("Libreria", systemImage: "square.stack.3d.up") }
                .tag(0)
            IdentitiesView()
                .tabItem { Label("Certificati", systemImage: "lock.doc") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Impostazioni", systemImage: "gearshape") }
                .tag(2)
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
                case "p12", "pfx", "mobileprovision":
                    let name = try store.acceptIncomingCertificateFile(url)
                    selectedTab = 1
                    importMessage = "\(name) ricevuto. Completa nella scheda Certificati."
                default:
                    importMessage = "Forgia apre file .ipa, .p12 e .mobileprovision."
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
