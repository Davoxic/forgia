import SwiftUI

@main
struct ForgiaApp: App {
    @StateObject private var store = Store()
    @StateObject private var settings = AppSettings()
    @StateObject private var installer = InstallService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(installer)
        }
    }
}
