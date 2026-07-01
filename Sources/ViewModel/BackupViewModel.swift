import SwiftUI
import ImageIO
import AVFoundation
import PhotosUI
import Security
import RcloneCryptKit

@MainActor
final class BackupViewModel: ObservableObject {
    @Published var files: [DriveFile] = []
    @Published var status = ""
    @Published var isConnected = false
    @Published var isBusy = false
    @Published var selected: DriveFile?                   // file shown full-screen (set on tap)
    @Published var sections: [FolderSection] = []         // files grouped by folder (folder picker)
    @Published var sortOrder: SortOrder = .modifiedDesc { // default: newest first
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder")
            applySort()
        }
    }
    private var allFiles: [DriveFile] = []                // unsorted master; re-sorted into `sections`
    private var thumbCache: [String: PlatformImage] = [:]       // fileID -> thumbnail; NOT @Published (per-cell @State drives UI)
    private var thumbOrder: [String] = []                 // FIFO eviction order
    private let thumbCap = 400                            // bound thumbnail memory in cache
    private let limiter = AsyncSemaphore(6)               // cap concurrent thumbnail jobs
    private var videoTempURLs: [String: URL] = [:]        // fileID -> decrypted temp file (reused for thumb + playback)
    private var videoTempOrder: [String] = []             // FIFO eviction order (deletes file from disk)
    private let videoTempCap = 12                          // keep only a few decrypted videos on disk at once

    /// Which vault (profile) this view model serves. Folder + crypt keys come from the profile;
    /// the Google token/client id are shared across profiles.
    let profileID: String

    /// The plaintext Drive folder that holds this profile's rclone crypt remote (read live so
    /// folder edits in Settings take effect on the next refresh).
    var rootFolderName: String { ProfileStore.folderName(forID: profileID) }

    private var profile: Profile? { ProfileStore.profile(forID: profileID) }
    private var backendKind: BackendKind { profile?.kind ?? .local }

    /// Build the storage config for this profile's backend (local dir, Drive token, or WebDAV creds).
    private func backendConfig() async -> BackendConfig? {
        switch backendKind {
        case .local:
            let path = LocalStore.rootPath(forFolder: rootFolderName)
            LocalStore.ensureRoot(path)
            isConnected = true
            return .local(rootPath: path)
        case .googleDrive:
            guard let tok = await ensureValidToken() else { return nil }
            return .drive(accessToken: tok.accessToken, folderName: rootFolderName)
        case .webdav:
            guard let p = profile, !p.webdavURL.isEmpty else { isConnected = false; return nil }
            let user = secrets.webdavUser(profile: profileID)
            let pass = secrets.webdavPass(profile: profileID)
            guard !user.isEmpty else { isConnected = false; return nil }
            isConnected = true
            return .webdav(baseURL: p.webdavURL, user: user, pass: pass, rootPath: "/" + rootFolderName)
        }
    }

    private let secrets = SecretsStore()
    private let auth = DriveAuth()
    private var token: OAuthToken?
    private var refreshTask: Task<OAuthToken?, Never>?   // dedup concurrent refreshes
    private var lockObserver: NSObjectProtocol?          // wipes decrypted state on app lock

    /// A currently-valid access token, refreshing (once, shared) if the stored one has expired.
    /// Returns nil and flips `isConnected` off if there's no token / refresh fails — that makes
    /// the "接続" button reappear so the user can re-login.
    private func ensureValidToken() async -> OAuthToken? {
        // Always start from the latest stored token: Settings or another tab may have just saved a
        // freshly-scoped token, and we must NOT refresh (and overwrite) a still-valid newer token
        // with an older one held in this tab's memory.
        token = secrets.loadToken()
        guard let t = token else { isConnected = false; return nil }
        if t.isValid { isConnected = true; return t }
        if let task = refreshTask { return await task.value }
        let task = Task { () -> OAuthToken? in try? await auth.refresh(t) }
        refreshTask = task
        let fresh = await task.value
        refreshTask = nil
        // If Settings/another tab saved a newer valid token while we were refreshing, keep THAT —
        // never clobber a fresh (possibly write-scoped) token with our older refresh result.
        if let latest = secrets.loadToken(), latest.isValid, latest.accessToken != t.accessToken {
            token = latest; isConnected = true
            return latest
        }
        if let fresh {
            token = fresh; secrets.saveToken(fresh); isConnected = true
        } else {
            isConnected = false
            status = "認証が切れました。「接続」で再ログインしてください"
        }
        return fresh
    }

    init(profileID: String) {
        self.profileID = profileID
        if let raw = UserDefaults.standard.string(forKey: "sortOrder"), let o = SortOrder(rawValue: raw) {
            sortOrder = o
        }
        reloadConnection()
        Self.purgeTempDir()   // remove decrypted videos left over from a previous run
        lockObserver = NotificationCenter.default.addObserver(
            forName: .cryptVaultDidLock, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wipeSensitiveState() }
        }
    }

    deinit {
        if let o = lockObserver { NotificationCenter.default.removeObserver(o) }
    }

    /// Drop key material and decrypted artifacts when the app locks: the derived keys, the
    /// thumbnail cache, decrypted media files on disk, and the open viewer. The (already
    /// name-decrypted) file list stays so the vault reopens instantly after unlock; keys are
    /// re-derived lazily on the next decrypt.
    private func wipeSensitiveState() {
        wipeGeneration &+= 1
        cryptEngine = nil
        cryptTask = nil
        thumbCache = [:]; thumbOrder = []
        clearVideoTemps()
        selected = nil          // dismisses the full-screen viewer (it renders decrypted content)
    }

    private var cryptEngine: RcloneCrypt?               // derived once and cached — scrypt is expensive
    private var cryptTask: Task<RcloneCrypt?, Never>?   // dedup concurrent derivations
    private var wipeGeneration = 0                      // invalidates derivations racing a lock

    /// Derive the crypt keys (off the main thread) and cache the engine for reuse.
    /// A brand-new *local* vault has no keys yet, so we generate a strong random key and store it
    /// on-device — this makes local vaults usable with zero setup while keeping the keys portable
    /// (reveal them in Settings to reuse the same vault on another device or a WebDAV server).
    private func makeCryptIfNeeded() async {
        var pw = secrets.cryptPassword(profile: profileID), salt = secrets.cryptSalt(profile: profileID)
        if pw.isEmpty, backendKind == .local {
            pw = Self.randomKey(); salt = Self.randomKey()
            // If the Keychain refused the write, DO NOT encrypt anything with the unsaved key —
            // data encrypted under a key that vanishes on relaunch is unrecoverable.
            guard secrets.saveCryptKeys(profile: profileID, password: pw, salt: salt) else {
                cryptEngine = nil
                status = "暗号キーを保存できませんでした（Keychainエラー）。安全のため処理を中止しました"
                return
            }
        }
        guard !pw.isEmpty else { cryptEngine = nil; return }
        let task: Task<RcloneCrypt?, Never>
        let isOwner: Bool
        if let running = cryptTask {
            task = running; isOwner = false
        } else {
            task = Task { await Self.deriveCrypt(pw: pw, salt: salt) }
            cryptTask = task; isOwner = true
        }
        let gen = wipeGeneration
        let engine = await task.value
        if isOwner { cryptTask = nil }
        guard gen == wipeGeneration else { return }   // locked while deriving — stay wiped
        cryptEngine = engine
    }

    /// Cheap variant for read paths (thumbnails/viewer): derive only if no engine is cached,
    /// e.g. after an app-lock wipe.
    private func ensureCrypt() async {
        if cryptEngine == nil { await makeCryptIfNeeded() }
    }

    /// 32-hex-char (128-bit) random string for an auto-generated local vault key.
    static func randomKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // A failed CSPRNG must never silently become an all-zero vault key.
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func deriveCrypt(pw: String, salt: String) async -> RcloneCrypt? {
        try? RcloneCrypt(password: pw, salt: salt)
    }

    nonisolated private static func decryptNames(_ files: [DriveFile], crypt: RcloneCrypt) async -> [DriveFile] {
        var out = files
        for i in out.indices { out[i].decryptedPath = crypt.decryptName(out[i].encryptedPath) }
        return out
    }

    /// Refresh `isConnected` for this profile's backend (Drive: has a token; WebDAV: has creds).
    /// Cheap; called when a vault tab appears.
    func reloadConnection() {
        switch backendKind {
        case .local:
            isConnected = true
        case .googleDrive:
            token = secrets.loadToken(); isConnected = token != nil
        case .webdav:
            isConnected = !(profile?.webdavURL ?? "").isEmpty && !secrets.webdavUser(profile: profileID).isEmpty
        }
    }

    func connect() async {
        isBusy = true; defer { isBusy = false }
        do {
            status = "Google 認証中…"
            let t = try await auth.authorize()
            token = t; secrets.saveToken(t); isConnected = true
            status = "接続しました。「更新」で一覧取得"
        } catch DriveAuthError.noClientID {
            status = "⚙️設定で Google クライアントID を入力してください"
        } catch {
            status = "認証失敗: \(error.localizedDescription)"
        }
    }

    func loadList() async {
        isBusy = true; defer { isBusy = false }
        guard let cfg = await backendConfig() else { status = "接続情報が未設定です（⚙️設定）"; return }
        await makeCryptIfNeeded()
        guard let c = cryptEngine else { status = "暗号パスワード未設定（⚙️設定から入力）"; return }
        do {
            status = "一覧取得中…"
            let raw = try await Storage.list(cfg)
            let found = await Self.decryptNames(raw, crypt: c)
            allFiles = found
            files = found
            applySort()
            thumbCache = [:]; thumbOrder = []
            clearVideoTemps()
            status = "\(files.count) 件 / \(sections.count) フォルダ"
        } catch let DriveError.httpBody(code, body) {
            status = "取得失敗(\(code)): \(body.replacingOccurrences(of: "\n", with: " ").prefix(140))"
        } catch DriveError.http(401) {
            isConnected = false
            status = "認証が切れました。「接続」で再ログインしてください"
        } catch {
            status = "取得失敗: \(error.localizedDescription)"
        }
    }

    // MARK: - Write (encrypt + upload, delete)

    /// Encrypt the given local files and upload them into `dir` (a decrypted path relative to the
    /// vault root; "" = root). Creates encrypted intermediate folders as needed, then refreshes.
    func addFiles(_ urls: [URL], toDir dir: String) async {
        reloadConnection()
        guard let cfg = await backendConfig() else { status = "接続情報が未設定です（⚙️設定）"; return }
        await makeCryptIfNeeded()
        guard let c = cryptEngine else { status = "暗号キー未設定（⚙️設定から入力）"; return }
        isBusy = true; defer { isBusy = false }
        do {
            var done = 0
            for url in urls {
                let ok = url.startAccessingSecurityScopedResource()
                let cipher = await Self.readAndEncrypt(url: url, crypt: c)
                if ok { url.stopAccessingSecurityScopedResource() }
                guard let cipher else { continue }
                let encRel = encryptedRelPath(dir: dir, name: url.lastPathComponent, crypt: c)
                try await Storage.upload(encryptedRelativePath: encRel, data: Data(cipher), cfg)
                done += 1
                status = "アップロード中… \(done)/\(urls.count)"
            }
            status = "\(done) 件アップロードしました"
            await loadList()
        } catch let DriveError.httpBody(code, body) {
            status = "失敗(\(code)): \(body.replacingOccurrences(of: "\n", with: " ").prefix(140))"
        } catch {
            status = "アップロード失敗: \(error.localizedDescription)"
        }
    }

    /// Encrypt and upload items picked from the photo library (PhotosPicker) into `dir`.
    func addPhotos(_ items: [PhotosPickerItem], toDir dir: String) async {
        reloadConnection()
        guard let cfg = await backendConfig() else { status = "接続情報が未設定です（⚙️設定）"; return }
        await makeCryptIfNeeded()
        guard let c = cryptEngine else { status = "暗号キー未設定（⚙️設定から入力）"; return }
        isBusy = true; defer { isBusy = false }
        do {
            var done = 0
            for (i, item) in items.enumerated() {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
                let name = Self.photoName(index: i, ext: ext)
                let cipher = await Self.encrypt(data, crypt: c)
                let encRel = encryptedRelPath(dir: dir, name: name, crypt: c)
                try await Storage.upload(encryptedRelativePath: encRel, data: Data(cipher), cfg)
                done += 1
                status = "アップロード中… \(done)/\(items.count)"
            }
            status = "\(done) 件アップロードしました"
            await loadList()
        } catch let DriveError.httpBody(code, body) {
            status = "失敗(\(code)): \(body.replacingOccurrences(of: "\n", with: " ").prefix(140))"
        } catch {
            status = "アップロード失敗: \(error.localizedDescription)"
        }
    }

    /// Encrypted path of `name` inside decrypted `dir`, relative to the vault root ("encA/encB").
    private func encryptedRelPath(dir: String, name: String, crypt c: RcloneCrypt) -> String {
        let decRel = dir.isEmpty ? name : dir + "/" + name
        return c.encryptName(decRel)
    }

    nonisolated private static func encrypt(_ data: Data, crypt c: RcloneCrypt) async -> [UInt8] {
        c.encryptContent([UInt8](data))
    }

    nonisolated private static func photoName(index: Int, ext: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        return "IMG_\(f.string(from: Date()))_\(index).\(ext)"
    }

    /// Delete a file (Drive: trash/recoverable, WebDAV: permanent) and drop it from the model.
    func deleteFile(_ file: DriveFile) async {
        guard let cfg = await backendConfig() else { return }
        do {
            try await Storage.delete(file, cfg)
            allFiles.removeAll { $0.id == file.id }
            files = allFiles
            applySort()
            thumbCache[file.id] = nil
            status = "「\(file.displayName)」を削除しました"
        } catch let DriveError.httpBody(code, body) {
            status = "削除失敗(\(code)): \(body.replacingOccurrences(of: "\n", with: " ").prefix(140))"
        } catch {
            status = "削除失敗: \(error.localizedDescription)"
        }
    }

    /// Read a local file and encrypt it — off the main actor (files can be large).
    nonisolated private static func readAndEncrypt(url: URL, crypt c: RcloneCrypt) async -> [UInt8]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return c.encryptContent([UInt8](data))
    }

    /// Re-group `allFiles` into folder sections using the current sort order (folders and the
    /// files inside them). Cheap enough to run on every sort-order change.
    func applySort() {
        sections = Self.makeSections(allFiles, order: sortOrder)
    }

    static func sortFiles(_ files: [DriveFile], order: SortOrder) -> [DriveFile] {
        switch order {
        case .name:
            return files.sorted { ($0.decryptedPath ?? "") < ($1.decryptedPath ?? "") }
        case .modifiedDesc:
            return files.sorted { ($0.modifiedTime ?? .distantPast) > ($1.modifiedTime ?? .distantPast) }
        case .modifiedAsc:
            return files.sorted { ($0.modifiedTime ?? .distantPast) < ($1.modifiedTime ?? .distantPast) }
        }
    }

    /// Bucket files by folder, sort within each folder, then order the folders themselves.
    static func makeSections(_ files: [DriveFile], order: SortOrder) -> [FolderSection] {
        var byDir: [String: [DriveFile]] = [:]
        for f in files { byDir[f.decryptedDir, default: []].append(f) }
        var sections = byDir.map { FolderSection(dir: $0.key, files: sortFiles($0.value, order: order)) }
        switch order {
        case .name:
            sections.sort { $0.dir < $1.dir }
        case .modifiedDesc:
            sections.sort { ($0.latestModified ?? .distantPast) > ($1.latestModified ?? .distantPast) }
        case .modifiedAsc:
            sections.sort { ($0.latestModified ?? .distantPast) < ($1.latestModified ?? .distantPast) }
        }
        return sections
    }

    /// Decrypted thumbnail from cache, or downloaded+decrypted+downsampled off the main thread.
    /// Returns the image to the calling cell (which stores it in its own @State) — so loading
    /// one thumbnail does NOT re-render the whole grid.
    func thumbnail(for file: DriveFile) async -> PlatformImage? {
        let id = file.id
        if let cached = thumbCache[id] { return cached }
        await ensureCrypt()   // re-derive lazily after an app-lock wipe
        guard let c = cryptEngine, let cfg = await backendConfig() else { return nil }
        await limiter.wait()
        let img: PlatformImage?
        if file.usesAVFoundation {
            // Decrypt to a temp file (reused for playback) and grab a frame for the thumbnail.
            if let url = await videoURL(for: file) {
                img = await Self.videoThumbnail(url: url, maxPixel: 300)
            } else {
                img = nil
            }
        } else if file.usesVLC {
            // Non-Apple formats: decrypt to a temp file (reused for playback) and let VLC
            // generate a still-frame thumbnail.
            if let url = await videoURL(for: file) {
                img = await VLCThumbnailer.thumbnail(url: url, maxPixel: 300)
            } else {
                img = nil
            }
        } else {
            img = await Self.fetchThumbnail(file: file, cfg: cfg, crypt: c)
        }
        await limiter.signal()
        if let img { cacheThumbnail(img, for: id) }
        return img
    }

    func cachedThumbnail(_ id: String) -> PlatformImage? { thumbCache[id] }

    /// Decrypted local file URL for a video, written to the temp dir and reused for both the
    /// thumbnail and full-screen playback. Cached so tapping a cell reuses the decrypted file.
    func videoURL(for file: DriveFile) async -> URL? {
        let id = file.id
        if let u = videoTempURLs[id], FileManager.default.fileExists(atPath: u.path) { return u }
        await ensureCrypt()
        guard let c = cryptEngine, let cfg = await backendConfig() else { return nil }
        let ext = file.fileExtension.isEmpty ? "mp4" : file.fileExtension
        guard let url = await Self.decryptToTemp(file: file, cfg: cfg, crypt: c, ext: ext) else { return nil }
        cacheVideoTemp(url, for: id)
        return url
    }

    private func cacheVideoTemp(_ url: URL, for id: String) {
        videoTempURLs[id] = url
        videoTempOrder.append(id)
        if videoTempOrder.count > videoTempCap {
            let old = videoTempOrder.removeFirst()
            if let u = videoTempURLs.removeValue(forKey: old) { try? FileManager.default.removeItem(at: u) }
        }
    }

    private func clearVideoTemps() {
        for u in videoTempURLs.values { try? FileManager.default.removeItem(at: u) }
        videoTempURLs = [:]; videoTempOrder = []
    }

    /// Full-resolution decrypted image for the viewer (decoded off the main thread).
    func fullImage(for file: DriveFile) async -> PlatformImage? {
        await ensureCrypt()
        guard let c = cryptEngine, let cfg = await backendConfig() else { return nil }
        return await Self.fetchFull(file: file, cfg: cfg, crypt: c)
    }

    private func cacheThumbnail(_ img: PlatformImage, for id: String) {
        thumbCache[id] = img
        thumbOrder.append(id)
        if thumbOrder.count > thumbCap { thumbCache[thumbOrder.removeFirst()] = nil }
    }

    // Heavy work below is `nonisolated` so it runs OFF the main actor — scrolling stays smooth.
    nonisolated private static func fetchThumbnail(file: DriveFile, cfg: BackendConfig, crypt: RcloneCrypt) async -> PlatformImage? {
        guard let blob = try? await Storage.download(file, cfg),
              let plain = try? crypt.decryptContent([UInt8](blob)) else { return nil }
        return downsample(Data(plain), maxPixel: 400)
    }

    nonisolated private static func fetchFull(file: DriveFile, cfg: BackendConfig, crypt: RcloneCrypt) async -> PlatformImage? {
        guard let blob = try? await Storage.download(file, cfg),
              let plain = try? crypt.decryptContent([UInt8](blob)) else { return nil }
        return PlatformImage(data: Data(plain))
    }

    nonisolated private static var mediaTempDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cryptvault-media", isDirectory: true)
    }

    nonisolated private static func purgeTempDir() {
        try? FileManager.default.removeItem(at: mediaTempDir)
    }

    /// Remove every decrypted media temp file, app-wide. Called when the app backgrounds (and on
    /// launch via init), so plaintext media never outlives the foreground session. Live view
    /// models re-check file existence before reusing a cached temp URL, so this is always safe.
    nonisolated static func purgeAllVideoTemps() {
        purgeTempDir()
    }

    /// Download + decrypt a whole file to a temp file on disk (needed because AVFoundation
    /// plays/thumbnails from a URL, not raw bytes). Extension is preserved for type inference.
    /// The plaintext temp is written with the strongest file-protection class available.
    nonisolated private static func decryptToTemp(file: DriveFile, cfg: BackendConfig, crypt: RcloneCrypt, ext: String) async -> URL? {
        guard let blob = try? await Storage.download(file, cfg),
              let plain = try? crypt.decryptContent([UInt8](blob)) else { return nil }
        let dir = mediaTempDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = file.id.replacingOccurrences(of: "/", with: "_")   // WebDAV ids contain "/"
        let url = dir.appendingPathComponent("\(safe).\(ext)")
        #if os(iOS)
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]
        #else
        let options: Data.WritingOptions = [.atomic]
        #endif
        do { try Data(plain).write(to: url, options: options); return url }
        catch { return nil }
    }

    nonisolated private static func videoThumbnail(url: URL, maxPixel: CGFloat) async -> PlatformImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 400, height: 400)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cg = try? await gen.image(at: time).image else { return nil }
        return PlatformImage.fromCG(cg)
    }

    nonisolated private static func downsample(_ data: Data, maxPixel: CGFloat) -> PlatformImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return PlatformImage.fromCG(cg)
    }
}
