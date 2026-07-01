import SwiftUI
import LocalAuthentication

/// Gates the app behind Face ID / Touch ID, falling back to the device passcode.
/// Controlled by the "appLockEnabled" setting (on by default).
@MainActor
final class AppLock: ObservableObject {
    @Published var unlocked = false
    private var authenticating = false

    private var enabled: Bool {
        #if DEBUG
        if Screenshot.disableLock { return false }   // screenshot harness
        #endif
        return (UserDefaults.standard.object(forKey: "appLockEnabled") as? Bool) ?? true
    }

    /// Re-lock (e.g. when the app goes to the background).
    func lockIfNeeded() { if enabled { unlocked = false } }

    func authenticate() {
        guard enabled else { unlocked = true; return }
        guard !unlocked, !authenticating else { return }

        let ctx = LAContext()
        ctx.localizedFallbackTitle = "パスコードを入力"
        var err: NSError?
        // No biometrics AND no passcode configured -> can't gate, so allow through.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            unlocked = true
            return
        }
        authenticating = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "Vault のロックを解除します") { success, _ in
            Task { @MainActor in
                self.authenticating = false
                self.unlocked = success
            }
        }
    }
}

/// Opaque cover shown while locked (nothing decrypted peeks through).
struct LockScreen: View {
    @ObservedObject var lock: AppLock
    var body: some View {
        ZStack {
            Rectangle().fill(Color.appBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.secondary)
                Text("ロックされています").font(.headline)
                Button { lock.authenticate() } label: {
                    Label("ロック解除", systemImage: "faceid")
                        .padding(.horizontal, 10).padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
