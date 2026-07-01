import Foundation

/// One vault: a Drive folder + its own crypt keys, shown as a tab. The Google account (OAuth
/// token) and client id are shared across profiles; only the folder and keys differ.
struct Profile: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var folderName: String
    var kind: BackendKind = .local         // new vaults default to the on-device (local) backend
    var webdavURL: String = ""             // WebDAV base URL (e.g. https://example.your-storagebox.de)

    init(id: String, name: String, folderName: String, kind: BackendKind = .local, webdavURL: String = "") {
        self.id = id; self.name = name; self.folderName = folderName
        self.kind = kind; self.webdavURL = webdavURL
    }

    enum CodingKeys: String, CodingKey { case id, name, folderName, kind, webdavURL }

    /// Tolerant decode: a profile saved by an older build may lack `kind`/`webdavURL`. Fall back to
    /// Google Drive for those (that's what old profiles were) instead of throwing and wiping data.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        folderName = try c.decode(String.self, forKey: .folderName)
        kind = (try? c.decode(BackendKind.self, forKey: .kind)) ?? .googleDrive
        webdavURL = (try? c.decode(String.self, forKey: .webdavURL)) ?? ""
    }
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
        if profiles.isEmpty { seedDefaultProfile() }
        if activeID.isEmpty || !profiles.contains(where: { $0.id == activeID }) {
            activeID = profiles.first?.id ?? ""
        }
        persist()
        #if DEBUG
        Screenshot.seedIfNeeded()
        #endif
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
        return f.isEmpty ? "vault" : f
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
        }
        UserDefaults.standard.set(activeID, forKey: Self.activeKey)
    }

    /// First launch: seed one ready-to-use on-device vault. Local vaults auto-generate their crypt
    /// key on first use, so the app works with zero setup. If the user is upgrading from an older
    /// build that stored global crypt keys, migrate those into the seeded vault.
    private func seedDefaultProfile() {
        let id = UUID().uuidString
        profiles = [Profile(id: id, name: "マイVault", folderName: "vault", kind: .local)]
        activeID = id
        let pw = KeychainStore.get(SecretKey.cryptPassword) ?? ""
        let salt = KeychainStore.get(SecretKey.cryptSalt) ?? ""
        if !pw.isEmpty { secrets.saveCryptKeys(profile: id, password: pw, salt: salt) }
    }

    @discardableResult
    func add(name: String, folderName: String, kind: BackendKind = .local) -> Profile {
        let p = Profile(id: UUID().uuidString,
                        name: name.isEmpty ? "新規Vault" : name,
                        folderName: folderName.isEmpty ? "vault-\(UUID().uuidString.prefix(6).lowercased())" : folderName,
                        kind: kind)
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
