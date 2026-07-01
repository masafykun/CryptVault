import SwiftUI
import ImageIO
import AVFoundation
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

    /// The plaintext Drive folder that holds the rclone crypt remote (configurable in Settings).
    var rootFolderName: String {
        let v = UserDefaults.standard.string(forKey: "rootFolderName") ?? ""
        return v.isEmpty ? "comfyui-backup" : v
    }

    private let secrets = SecretsStore()
    private let auth = DriveAuth()
    private var token: OAuthToken?
    private var refreshTask: Task<OAuthToken?, Never>?   // dedup concurrent refreshes

    /// A currently-valid access token, refreshing (once, shared) if the stored one has expired.
    /// Returns nil and flips `isConnected` off if there's no token / refresh fails — that makes
    /// the "接続" button reappear so the user can re-login.
    private func ensureValidToken() async -> OAuthToken? {
        guard let t = token else { isConnected = false; return nil }
        if t.isValid { return t }
        if let task = refreshTask { return await task.value }
        let task = Task { () -> OAuthToken? in try? await auth.refresh(t) }
        refreshTask = task
        let fresh = await task.value
        refreshTask = nil
        if let fresh {
            token = fresh; secrets.saveToken(fresh); isConnected = true
        } else {
            isConnected = false
            status = "認証が切れました。「接続」で再ログインしてください"
        }
        return fresh
    }

    init() {
        token = secrets.loadToken()
        isConnected = token != nil
        if let raw = UserDefaults.standard.string(forKey: "sortOrder"), let o = SortOrder(rawValue: raw) {
            sortOrder = o
        }
        Self.purgeTempDir()   // remove decrypted videos left over from a previous run
    }

    private var cryptEngine: RcloneCrypt?   // derived ONCE per refresh — scrypt is expensive

    /// Derive the crypt keys once (off the main thread) and cache the engine for reuse.
    private func makeCryptIfNeeded() async {
        let pw = secrets.cryptPassword, salt = secrets.cryptSalt
        guard !pw.isEmpty else { cryptEngine = nil; return }
        cryptEngine = await Self.deriveCrypt(pw: pw, salt: salt)
    }

    nonisolated private static func deriveCrypt(pw: String, salt: String) async -> RcloneCrypt? {
        try? RcloneCrypt(password: pw, salt: salt)
    }

    nonisolated private static func decryptNames(_ files: [DriveFile], crypt: RcloneCrypt) async -> [DriveFile] {
        var out = files
        for i in out.indices { out[i].decryptedPath = crypt.decryptName(out[i].encryptedPath) }
        return out
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
        guard token != nil else { status = "未接続です"; return }
        isBusy = true; defer { isBusy = false }
        guard let tok = await ensureValidToken() else { return }
        await makeCryptIfNeeded()
        guard let c = cryptEngine else { status = "暗号パスワード未設定（⚙️設定から入力）"; return }
        do {
            status = "一覧取得中…"
            let client = DriveClient(accessToken: tok.accessToken)
            let folder = rootFolderName
            guard let rootID = try await client.findFolderID(named: folder) else {
                status = "「\(folder)」フォルダが見つかりません"; return
            }
            let raw = try await client.walk(folderID: rootID)
            let found = await Self.decryptNames(raw, crypt: c)
            allFiles = found
            files = found
            applySort()
            thumbCache = [:]; thumbOrder = []
            clearVideoTemps()
            status = "\(files.count) 件 / \(sections.count) フォルダ"
        } catch DriveError.http(401) {
            isConnected = false
            status = "認証が切れました。「接続」で再ログインしてください"
        } catch {
            status = "取得失敗: \(error.localizedDescription)"
        }
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
        guard let c = cryptEngine, let token = await ensureValidToken() else { return nil }
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
            img = await Self.fetchThumbnail(id: id, token: token, crypt: c)
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
        guard let c = cryptEngine, let token = await ensureValidToken() else { return nil }
        let ext = file.fileExtension.isEmpty ? "mp4" : file.fileExtension
        guard let url = await Self.decryptToTemp(id: id, token: token, crypt: c, ext: ext) else { return nil }
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
        guard let c = cryptEngine, let token = await ensureValidToken() else { return nil }
        return await Self.fetchFull(id: file.id, token: token, crypt: c)
    }

    private func cacheThumbnail(_ img: PlatformImage, for id: String) {
        thumbCache[id] = img
        thumbOrder.append(id)
        if thumbOrder.count > thumbCap { thumbCache[thumbOrder.removeFirst()] = nil }
    }

    // Heavy work below is `nonisolated` so it runs OFF the main actor — scrolling stays smooth.
    nonisolated private static func fetchThumbnail(id: String, token: OAuthToken, crypt: RcloneCrypt) async -> PlatformImage? {
        guard let blob = try? await DriveClient(accessToken: token.accessToken).downloadMedia(fileID: id),
              let plain = try? crypt.decryptContent([UInt8](blob)) else { return nil }
        return downsample(Data(plain), maxPixel: 300)
    }

    nonisolated private static func fetchFull(id: String, token: OAuthToken, crypt: RcloneCrypt) async -> PlatformImage? {
        guard let blob = try? await DriveClient(accessToken: token.accessToken).downloadMedia(fileID: id),
              let plain = try? crypt.decryptContent([UInt8](blob)) else { return nil }
        return PlatformImage(data: Data(plain))
    }

    nonisolated private static var mediaTempDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cryptvault-media", isDirectory: true)
    }

    nonisolated private static func purgeTempDir() {
        try? FileManager.default.removeItem(at: mediaTempDir)
    }

    /// Download + decrypt a whole file to a temp file on disk (needed because AVFoundation
    /// plays/thumbnails from a URL, not raw bytes). Extension is preserved for type inference.
    nonisolated private static func decryptToTemp(id: String, token: OAuthToken, crypt: RcloneCrypt, ext: String) async -> URL? {
        guard let blob = try? await DriveClient(accessToken: token.accessToken).downloadMedia(fileID: id),
              let plain = try? crypt.decryptContent([UInt8](blob)) else { return nil }
        let dir = mediaTempDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(id).\(ext)")
        do { try Data(plain).write(to: url, options: .atomic); return url }
        catch { return nil }
    }

    nonisolated private static func videoThumbnail(url: URL, maxPixel: CGFloat) async -> PlatformImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
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
