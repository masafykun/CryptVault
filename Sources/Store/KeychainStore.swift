import Foundation
import Security

/// Minimal Keychain wrapper for small secrets (crypt keys, WebDAV credentials, OAuth token JSON).
///
/// Security properties (deliberate):
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: items are readable only while the device is
///   unlocked and are NEVER restored onto another device via iCloud/Finder backups. Moving a
///   vault to a new device is done by backing up the crypt key itself (設定 > 鍵を表示).
/// - On macOS items live in the data-protection keychain (per-app), not the shared login keychain.
/// - Writes are update-in-place and status-checked. The old value is never deleted first, so a
///   failed write can't destroy an existing key (crypt keys are unrecoverable by design).
enum KeychainStore {
    private static let service = "com.masafy.cryptvault"

    private static func baseQuery(_ key: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        #if os(macOS)
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }

    /// Store `value` for `key`. Returns false if the Keychain refused the write — callers that
    /// persist crypt keys MUST check this and refuse to encrypt data with an unsaved key.
    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        let attrs: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery(key) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(key)
            attrs.forEach { add[$0.key] = $0.value }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        var q = baseQuery(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data {
            return String(data: data, encoding: .utf8)
        }
        return migrateLegacyItem(key)
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
        // Also remove any pre-hardening copy (no service attribute / login keychain on macOS).
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrAccount as String: key] as CFDictionary)
    }

    /// One-time migration for items written by builds before the service/accessibility hardening
    /// (no `kSecAttrService`, default accessibility, login keychain on macOS). Re-stores the value
    /// under the hardened attributes and removes the old copy — but only after the new write stuck.
    private static func migrateLegacyItem(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecReturnPersistentRef as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let item = out as? [String: Any],
              let data = item[kSecValueData as String] as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        if set(value, for: key), let ref = item[kSecValuePersistentRef as String] {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                           kSecMatchItemList as String: [ref]] as CFDictionary)
        }
        return value
    }
}

enum SecretKey {
    static let cryptPassword = "crypt.password"
    static let cryptSalt = "crypt.salt"
    static let oauthToken = "oauth.token.json"
}

/// Typed access to the secrets we persist on-device.
struct SecretsStore {
    var cryptPassword: String { KeychainStore.get(SecretKey.cryptPassword) ?? "" }
    var cryptSalt: String { KeychainStore.get(SecretKey.cryptSalt) ?? "" }

    // Per-profile crypt keys (each vault/tab has its own).
    func cryptPassword(profile id: String) -> String { KeychainStore.get("crypt.password.\(id)") ?? "" }
    func cryptSalt(profile id: String) -> String { KeychainStore.get("crypt.salt.\(id)") ?? "" }

    /// Persist a vault's crypt keys. False means the Keychain write failed — the caller must not
    /// encrypt anything with these keys (data written under an unsaved key is lost on relaunch).
    @discardableResult
    func saveCryptKeys(profile id: String, password: String, salt: String) -> Bool {
        let pwOK = KeychainStore.set(password, for: "crypt.password.\(id)")
        let saltOK = KeychainStore.set(salt, for: "crypt.salt.\(id)")
        return pwOK && saltOK
    }
    func deleteCryptKeys(profile id: String) {
        KeychainStore.delete("crypt.password.\(id)")
        KeychainStore.delete("crypt.salt.\(id)")
    }

    // Per-profile WebDAV credentials.
    func webdavUser(profile id: String) -> String { KeychainStore.get("webdav.user.\(id)") ?? "" }
    func webdavPass(profile id: String) -> String { KeychainStore.get("webdav.pass.\(id)") ?? "" }
    @discardableResult
    func saveWebDAV(profile id: String, user: String, pass: String) -> Bool {
        let userOK = KeychainStore.set(user, for: "webdav.user.\(id)")
        let passOK = KeychainStore.set(pass, for: "webdav.pass.\(id)")
        return userOK && passOK
    }
    func deleteWebDAV(profile id: String) {
        KeychainStore.delete("webdav.user.\(id)")
        KeychainStore.delete("webdav.pass.\(id)")
    }

    func loadToken() -> OAuthToken? {
        guard let s = KeychainStore.get(SecretKey.oauthToken),
              let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OAuthToken.self, from: d)
    }

    @discardableResult
    func saveToken(_ t: OAuthToken) -> Bool {
        // Never downgrade a still-valid write-scoped token to a lesser-scoped one. This is the
        // last line of defense against token-refresh races (a background tab refreshing an older
        // readonly token) clobbering a freshly-granted write token in the Keychain.
        if let existing = loadToken(), existing.isValid, existing.canWrite, !t.canWrite {
            return true
        }
        guard let d = try? JSONEncoder().encode(t), let s = String(data: d, encoding: .utf8) else {
            return false
        }
        return KeychainStore.set(s, for: SecretKey.oauthToken)
    }
}
