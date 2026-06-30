import SwiftUI
import UIKit
import ImageIO
import RcloneCryptKit

@MainActor
final class BackupViewModel: ObservableObject {
    @Published var files: [DriveFile] = []
    @Published var status = ""
    @Published var isConnected = false
    @Published var isBusy = false
    @Published var selected: DriveFile?                   // file shown full-screen (set on tap)
    @Published var visibleCount = 20                      // how many cells are shown (grows on scroll)
    private var thumbCache: [String: UIImage] = [:]       // fileID -> thumbnail; NOT @Published (per-cell @State drives UI)
    private var thumbOrder: [String] = []                 // FIFO eviction order
    private let thumbCap = 400                            // bound thumbnail memory in cache
    private let limiter = AsyncSemaphore(6)               // cap concurrent thumbnail jobs
    static let pageSize = 20

    /// The plaintext Drive folder that holds the rclone crypt remote (configurable in Settings).
    var rootFolderName: String {
        let v = UserDefaults.standard.string(forKey: "rootFolderName") ?? ""
        return v.isEmpty ? "comfyui-backup" : v
    }

    private let secrets = SecretsStore()
    private let auth = DriveAuth()
    private var token: OAuthToken?

    init() {
        token = secrets.loadToken()
        isConnected = token != nil
    }

    private func crypt() -> RcloneCrypt? {
        let pw = secrets.cryptPassword
        guard !pw.isEmpty else { return nil }
        return try? RcloneCrypt(password: pw, salt: secrets.cryptSalt)
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
        guard let token else { status = "未接続です"; return }
        guard let c = crypt() else { status = "暗号パスワード未設定（⚙️設定から入力）"; return }
        isBusy = true; defer { isBusy = false }
        do {
            status = "一覧取得中…"
            let client = DriveClient(accessToken: token.accessToken)
            let folder = rootFolderName
            guard let rootID = try await client.findFolderID(named: folder) else {
                status = "「\(folder)」フォルダが見つかりません"; return
            }
            var found = try await client.walk(folderID: rootID)
            for i in found.indices { found[i].decryptedPath = c.decryptName(found[i].encryptedPath) }
            found.sort { ($0.decryptedPath ?? "") < ($1.decryptedPath ?? "") }
            files = found
            thumbCache = [:]; thumbOrder = []
            visibleCount = min(Self.pageSize, files.count)
            status = "\(files.count) 件"
        } catch {
            status = "取得失敗: \(error.localizedDescription)"
        }
    }

    /// Reveal the next page of cells (called when the last visible cell appears).
    func loadMore() {
        guard visibleCount < files.count else { return }
        visibleCount = min(visibleCount + Self.pageSize, files.count)
    }

    /// Download + decrypt + downsample one image into a cached thumbnail (no-op if already cached).
    /// Decrypted thumbnail from cache, or downloaded+decrypted+downsampled off the main thread.
    /// Returns the image to the calling cell (which stores it in its own @State) — so loading
    /// one thumbnail does NOT re-render the whole grid.
    func thumbnail(for file: DriveFile) async -> UIImage? {
        let id = file.id
        if let cached = thumbCache[id] { return cached }
        guard let token, let c = crypt() else { return nil }
        await limiter.wait()
        let img = await Self.fetchThumbnail(id: id, token: token, crypt: c)
        await limiter.signal()
        if let img { cacheThumbnail(img, for: id) }
        return img
    }

    func cachedThumbnail(_ id: String) -> UIImage? { thumbCache[id] }

    /// Full-resolution decrypted image for the viewer (decoded off the main thread).
    func fullImage(for file: DriveFile) async -> UIImage? {
        guard let token, let c = crypt() else { return nil }
        return await Self.fetchFull(id: file.id, token: token, crypt: c)
    }

    private func cacheThumbnail(_ img: UIImage, for id: String) {
        thumbCache[id] = img
        thumbOrder.append(id)
        if thumbOrder.count > thumbCap { thumbCache[thumbOrder.removeFirst()] = nil }
    }

    // Heavy work below is `nonisolated` so it runs OFF the main actor — scrolling stays smooth.
    nonisolated private static func fetchThumbnail(id: String, token: OAuthToken, crypt: RcloneCrypt) async -> UIImage? {
        guard let blob = try? await DriveClient(accessToken: token.accessToken).downloadMedia(fileID: id),
              let plain = try? crypt.decryptContent([UInt8](blob)) else { return nil }
        return downsample(Data(plain), maxPixel: 300)
    }

    nonisolated private static func fetchFull(id: String, token: OAuthToken, crypt: RcloneCrypt) async -> UIImage? {
        guard let blob = try? await DriveClient(accessToken: token.accessToken).downloadMedia(fileID: id),
              let plain = try? crypt.decryptContent([UInt8](blob)) else { return nil }
        return UIImage(data: Data(plain))
    }

    nonisolated private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
