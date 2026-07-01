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
    var modifiedTime: Date?        // Drive modifiedTime (≈ when it was backed up); drives date sort

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
    /// Formats AVFoundation plays natively (hardware decode + native scrubber controls,
    /// and thumbnails via AVAssetImageGenerator).
    var usesAVFoundation: Bool {
        ["mp4", "mov", "m4v"].contains(fileExtension)
    }
    /// Formats AVFoundation can't decode but VLC (MobileVLCKit) can.
    var usesVLC: Bool {
        ["webm", "mkv", "avi", "flv", "wmv", "mpg", "mpeg", "ts", "m2ts",
         "3gp", "ogv", "vob", "asf", "rm", "rmvb"].contains(fileExtension)
    }
    /// Any playable video (drives the ▶️ badge and full-screen routing).
    var isVideo: Bool { usesAVFoundation || usesVLC }
}

/// A group of files that share the same decrypted folder path (one folder in the picker).
struct FolderSection: Identifiable, Hashable {
    var id: String { dir }
    let dir: String
    let files: [DriveFile]

    var count: Int { files.count }
    var latestModified: Date? { files.compactMap { $0.modifiedTime }.max() }
    /// Display name for the folder row: the path relative to the top "output/" prefix when present.
    var displayName: String {
        if dir.isEmpty { return "(ルート)" }
        if dir == "output" { return "output" }
        if dir.hasPrefix("output/") { return String(dir.dropFirst("output/".count)) }
        return dir
    }
}

/// User-selectable ordering for folders and files. Persisted in UserDefaults.
enum SortOrder: String, CaseIterable, Identifiable {
    case modifiedDesc, modifiedAsc, name
    var id: String { rawValue }
    var label: String {
        switch self {
        case .modifiedDesc: return "更新日（新しい順）"
        case .modifiedAsc:  return "更新日（古い順）"
        case .name:         return "名前順"
        }
    }
}

/// Navigation value for drilling into a folder's grid.
struct FolderRoute: Hashable { let dir: String }
