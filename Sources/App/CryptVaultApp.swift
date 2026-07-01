import SwiftUI

@main
struct CryptVaultApp: App {
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                if !lock.unlocked { LockScreen(lock: lock) }
            }
            .task { lock.authenticate() }
            .onChange(of: phase) { newPhase in
                switch newPhase {
                case .active:     lock.authenticate()
                case .background: lock.lockIfNeeded()
                default:          break
                }
            }
        }
    }
}
