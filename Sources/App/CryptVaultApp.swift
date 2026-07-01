import SwiftUI

@main
struct CryptVaultApp: App {
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .privacyShield()
                .environmentObject(lock)
                .task { lock.authenticate() }
                .onChange(of: phase) { newPhase in
                    switch newPhase {
                    case .active:
                        lock.authenticate()
                    case .background:
                        lock.lockIfNeeded()
                        // Plaintext media temp files never outlive the foreground session,
                        // whether or not the app lock is enabled.
                        BackupViewModel.purgeAllVideoTemps()
                    default:
                        break
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 772)
        #endif
    }
}
