import Foundation
import Security

/// Minimal Keychain wrapper for small secrets (crypt keys, OAuth token JSON).
enum KeychainStore {
    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrAccount as String: key] as CFDictionary)
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

    func saveCryptKeys(password: String, salt: String) {
        KeychainStore.set(password, for: SecretKey.cryptPassword)
        KeychainStore.set(salt, for: SecretKey.cryptSalt)
    }

    // Per-profile crypt keys (each vault/tab has its own).
    func cryptPassword(profile id: String) -> String { KeychainStore.get("crypt.password.\(id)") ?? "" }
    func cryptSalt(profile id: String) -> String { KeychainStore.get("crypt.salt.\(id)") ?? "" }
    func saveCryptKeys(profile id: String, password: String, salt: String) {
        KeychainStore.set(password, for: "crypt.password.\(id)")
        KeychainStore.set(salt, for: "crypt.salt.\(id)")
    }
    func deleteCryptKeys(profile id: String) {
        KeychainStore.delete("crypt.password.\(id)")
        KeychainStore.delete("crypt.salt.\(id)")
    }

    // Per-profile WebDAV credentials.
    func webdavUser(profile id: String) -> String { KeychainStore.get("webdav.user.\(id)") ?? "" }
    func webdavPass(profile id: String) -> String { KeychainStore.get("webdav.pass.\(id)") ?? "" }
    func saveWebDAV(profile id: String, user: String, pass: String) {
        KeychainStore.set(user, for: "webdav.user.\(id)")
        KeychainStore.set(pass, for: "webdav.pass.\(id)")
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

    func saveToken(_ t: OAuthToken) {
        // Never downgrade a still-valid write-scoped token to a lesser-scoped one. This is the
        // last line of defense against token-refresh races (a background tab refreshing an older
        // readonly token) clobbering a freshly-granted write token in the Keychain.
        if let existing = loadToken(), existing.isValid, existing.canWrite, !t.canWrite {
            return
        }
        if let d = try? JSONEncoder().encode(t), let s = String(data: d, encoding: .utf8) {
            KeychainStore.set(s, for: SecretKey.oauthToken)
        }
    }
}
