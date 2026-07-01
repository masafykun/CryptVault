import Foundation

/// A file or folder on Google Drive. Names/paths are the *encrypted* (rclone crypt)
/// values as stored on Drive; `decryptedPath` is filled in after name decryption.
struct DriveFile: Identifiable, Hashable {
    let id: String                 // Drive fileId
    let encryptedName: String      // raw name on Drive (ciphertext, base32hex)
    let encryptedPath: String      // full encrypted relative path from the backup root
    var decryptedPath: String?     // real path, e.g. "output/_audit0630/24_...png"
    let isFolder: Bool
    let size: Int64?

    var displayName: String {
        if let p = decryptedPath { return (p as NSString).lastPathComponent }
        return encryptedName
    }
    var decryptedDir: String {
        guard let p = decryptedPath else { return "" }
        return (p as NSString).deletingLastPathComponent
    }

    var fileExtension: String {
        (displayName as NSString).pathExtension.lowercased()
    }
    /// Formats AVFoundation can both thumbnail and play back.
    var isPlayableVideo: Bool {
        ["mp4", "mov", "m4v"].contains(fileExtension)
    }
    /// Broader set treated as "video" for the ▶️ badge. Some (webm/mkv/avi) can't
    /// actually be decoded by AVFoundation — the viewer shows a graceful fallback.
    var isVideo: Bool {
        isPlayableVideo || ["webm", "mkv", "avi"].contains(fileExtension)
    }
}

/// A group of files that share the same decrypted folder path (one grid section).
struct FolderSection: Identifiable {
    var id: String { dir }
    let dir: String
    let files: [DriveFile]
}
