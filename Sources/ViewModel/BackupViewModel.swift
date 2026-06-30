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
    @Published var previewImage: UIImage?
    @Published var thumbnails: [String: UIImage] = [:]   // fileID -> decrypted thumbnail
    @Published var visibleCount = 20                      // how many cells are shown (grows on scroll)
    private var thumbOrder: [String] = []                 // FIFO eviction order
    private let thumbCap = 400                            // bound thumbnail memory in cache
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
            thumbnails = [:]; thumbOrder = []
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
    func loadThumbnail(for file: DriveFile) async {
        if thumbnails[file.id] != nil { return }
        guard let token, let c = crypt() else { return }
        do {
            let client = DriveClient(accessToken: token.accessToken)
            let blob = try await client.downloadMedia(fileID: file.id)
            let plain = try c.decryptContent([UInt8](blob))
            if let img = Self.downsample(Data(plain), maxPixel: 300) {
                cacheThumbnail(img, for: file.id)
            }
        } catch {
            // leave uncached; the cell keeps its placeholder and may retry on reappear
        }
    }

    private func cacheThumbnail(_ img: UIImage, for id: String) {
        thumbnails[id] = img
        thumbOrder.append(id)
        if thumbOrder.count > thumbCap {
            let evicted = thumbOrder.removeFirst()
            thumbnails[evicted] = nil
        }
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
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

    func open(_ file: DriveFile) async {
        guard let token, let c = crypt() else { return }
        isBusy = true; defer { isBusy = false }
        do {
            status = "復号中… \(file.displayName)"
            let client = DriveClient(accessToken: token.accessToken)
            let blob = try await client.downloadMedia(fileID: file.id)
            let plain = try c.decryptContent([UInt8](blob))
            if let img = UIImage(data: Data(plain)) {
                previewImage = img
                status = file.displayName
            } else {
                status = "画像として表示できません（\(plain.count) bytes 復号済み）"
            }
        } catch {
            status = "復号失敗: \(error.localizedDescription)"
        }
    }
}
