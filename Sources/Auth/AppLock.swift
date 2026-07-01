import SwiftUI
import LocalAuthentication

extension Notification.Name {
    /// Posted when the app locks. View models drop key material and decrypted artifacts
    /// (derived keys, thumbnail cache, decrypted media temp files, the open viewer).
    static let cryptVaultDidLock = Notification.Name("cryptVaultDidLock")
}

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

    /// Re-lock (e.g. when the app goes to the background). Locking also tells view models to
    /// wipe decrypted state, so the lock is more than a visual overlay.
    func lockIfNeeded() {
        guard enabled else { return }
        unlocked = false
        NotificationCenter.default.post(name: .cryptVaultDidLock, object: nil)
    }

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

/// Opaque cover for brief inactive states (app switcher, notification shade), so decrypted
/// content never appears in the system app-switcher snapshot. No unlock button: the cover
/// lifts by itself when the scene becomes active again.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Color.appBackground).ignoresSafeArea()
            Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.secondary)
        }
    }
}

/// Overlays the lock screen / privacy cover on any view hierarchy. Applied to the app root AND
/// to full-screen presentations (viewers), because presented layers render above the root ZStack
/// and would otherwise stay visible over the lock.
struct PrivacyShield: ViewModifier {
    @EnvironmentObject private var lock: AppLock
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        ZStack {
            content
            if !lock.unlocked {
                LockScreen(lock: lock)
            } else if coverInactive {
                PrivacyCover()
            }
        }
    }

    /// iOS only: cover the content during brief inactive states (app switcher snapshot).
    /// On macOS windows are routinely "inactive" while fully visible, so no cover there.
    private var coverInactive: Bool {
        #if os(iOS)
        return phase != .active
        #else
        return false
        #endif
    }
}

extension View {
    func privacyShield() -> some View { modifier(PrivacyShield()) }
}
