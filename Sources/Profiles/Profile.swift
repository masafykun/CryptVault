import Foundation

/// One vault: a Drive folder + its own crypt keys, shown as a tab. The Google account (OAuth
/// token) and client id are shared across profiles; only the folder and keys differ.
struct Profile: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var folderName: String
    var kind: BackendKind = .googleDrive   // default keeps existing profiles on Google Drive
    var webdavURL: String = ""             // WebDAV base URL (e.g. https://u123.your-storagebox.de)
}

/// Stores the list of profiles + which one is active. Profile metadata lives in UserDefaults;
/// each profile's crypt password/salt live in the Keychain keyed by profile id.
@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeID: String = ""

    private static let profilesKey = "profiles.v1"
    private static let activeKey = "profiles.active"
    private let secrets = SecretsStore()

    init() {
        profiles = Self.loadProfiles()
        activeID = UserDefaults.standard.string(forKey: Self.activeKey) ?? ""
        if profiles.isEmpty { seedFromLegacyConfig() }
        if activeID.isEmpty || !profiles.contains(where: { $0.id == activeID }) {
            activeID = profiles.first?.id ?? ""
        }
        persist()
    }

    static func loadProfiles() -> [Profile] {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let list = try? JSONDecoder().decode([Profile].self, from: data) else { return [] }
        return list
    }

    static func profile(forID id: String) -> Profile? {
        loadProfiles().first { $0.id == id }
    }

    /// Live folder lookup by id (so folder edits take effect without recreating a view model).
    static func folderName(forID id: String) -> String {
        let f = loadProfiles().first { $0.id == id }?.folderName ?? ""
        return f.isEmpty ? "comfyui-backup" : f
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
        }
        UserDefaults.standard.set(activeID, forKey: Self.activeKey)
    }

    /// First run of the profiles feature: seed one profile from the app's previous single config,
    /// migrating the existing global crypt keys into it so nothing breaks.
    private func seedFromLegacyConfig() {
        let folder = UserDefaults.standard.string(forKey: "rootFolderName") ?? "comfyui-backup"
        let id = UUID().uuidString
        profiles = [Profile(id: id, name: "ComfyUI", folderName: folder.isEmpty ? "comfyui-backup" : folder)]
        activeID = id
        let pw = KeychainStore.get(SecretKey.cryptPassword) ?? ""
        let salt = KeychainStore.get(SecretKey.cryptSalt) ?? ""
        if !pw.isEmpty { secrets.saveCryptKeys(profile: id, password: pw, salt: salt) }
    }

    @discardableResult
    func add(name: String, folderName: String) -> Profile {
        let p = Profile(id: UUID().uuidString,
                        name: name.isEmpty ? "新規Vault" : name,
                        folderName: folderName)
        profiles.append(p)
        activeID = p.id
        persist()
        return p
    }

    func update(_ p: Profile) {
        if let i = profiles.firstIndex(where: { $0.id == p.id }) { profiles[i] = p; persist() }
    }

    func remove(_ p: Profile) {
        profiles.removeAll { $0.id == p.id }
        secrets.deleteCryptKeys(profile: p.id)
        secrets.deleteWebDAV(profile: p.id)
        if activeID == p.id { activeID = profiles.first?.id ?? "" }
        persist()
    }

    func setActive(_ id: String) { activeID = id; persist() }
}
