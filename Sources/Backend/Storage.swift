import Foundation

/// Which storage a profile talks to.
enum BackendKind: String, Codable, CaseIterable, Identifiable {
    case local, webdav, googleDrive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .local:       return "この端末（ローカル）"
        case .webdav:      return "WebDAV（Hetzner / NAS 等）"
        case .googleDrive: return "Google Drive"
        }
    }
    /// Backends offered in the UI. Google Drive is kept in the model for compatibility but not
    /// selectable (public Drive access needs Google's OAuth verification + CASA review).
    static var selectable: [BackendKind] { [.local, .webdav] }
}

/// Everything a storage operation needs, captured as a Sendable value so it can cross actors.
enum BackendConfig: Sendable {
    case local(rootPath: String)
    case drive(accessToken: String, folderName: String)
    case webdav(baseURL: String, user: String, pass: String, rootPath: String)
}

/// Backend-agnostic storage operations. The view model works only through these; encryption is
/// applied by the caller (files here are always ciphertext).
enum Storage {

    /// Every leaf file under the vault root. `encryptedPath` is relative to the root; `id` is a
    /// retrieval handle (Drive fileId, or the encrypted relative path for WebDAV).
    static func list(_ cfg: BackendConfig) async throws -> [DriveFile] {
        switch cfg {
        case let .local(root):
            return try LocalStore.list(rootPath: root)

        case let .drive(token, folder):
            let client = DriveClient(accessToken: token)
            guard let rootID = try await client.findFolderID(named: folder) else { return [] }
            return try await client.walk(folderID: rootID)

        case let .webdav(base, user, pass, root):
            let client = WebDAVClient(baseURL: base, user: user, pass: pass)
            let rootNorm = WebDAVClient.normalize(root)
            let items = try await client.walk(root: rootNorm)
            let prefix = rootNorm + "/"
            return items.compactMap { item in
                let full = WebDAVClient.normalize(item.path)
                guard full.hasPrefix(prefix) else { return nil }
                let rel = String(full.dropFirst(prefix.count))
                guard !rel.isEmpty else { return nil }
                return DriveFile(id: rel, encryptedName: (rel as NSString).lastPathComponent,
                                 encryptedPath: rel, decryptedPath: nil, isFolder: false,
                                 size: item.size, modifiedTime: item.modified)
            }
        }
    }

    static func download(_ file: DriveFile, _ cfg: BackendConfig) async throws -> Data {
        switch cfg {
        case let .local(root):
            return try LocalStore.read(rootPath: root, id: file.id)
        case let .drive(token, _):
            return try await DriveClient(accessToken: token).downloadMedia(fileID: file.id)
        case let .webdav(base, user, pass, root):
            let client = WebDAVClient(baseURL: base, user: user, pass: pass)
            return try await client.get(path: WebDAVClient.normalize(root) + "/" + file.id)
        }
    }

    /// Upload ciphertext to `encryptedRelativePath` (relative to the vault root), creating any
    /// intermediate folders.
    static func upload(encryptedRelativePath encPath: String, data: Data, _ cfg: BackendConfig) async throws {
        switch cfg {
        case let .local(root):
            try LocalStore.write(rootPath: root, encPath: encPath, data: data)

        case let .drive(token, folder):
            let client = DriveClient(accessToken: token)
            let rootID: String
            if let found = try await client.findFolderID(named: folder) { rootID = found }
            else { rootID = try await client.createFolder(name: folder, parentID: nil) }
            var parent = rootID
            let segs = encPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            for seg in segs.dropLast() {
                if let existing = try await client.findFolderID(named: seg, parent: parent) { parent = existing }
                else { parent = try await client.createFolder(name: seg, parentID: parent) }
            }
            _ = try await client.uploadFile(name: segs.last ?? encPath, parentID: parent, data: data)

        case let .webdav(base, user, pass, root):
            let client = WebDAVClient(baseURL: base, user: user, pass: pass)
            let full = WebDAVClient.normalize(root) + "/" + encPath
            try await client.ensureParents(of: full)
            try await client.put(path: full, data: data)
        }
    }

    static func delete(_ file: DriveFile, _ cfg: BackendConfig) async throws {
        switch cfg {
        case let .local(root):
            try LocalStore.delete(rootPath: root, id: file.id)
        case let .drive(token, _):
            try await DriveClient(accessToken: token).trash(fileID: file.id)
        case let .webdav(base, user, pass, root):
            let client = WebDAVClient(baseURL: base, user: user, pass: pass)
            try await client.delete(path: WebDAVClient.normalize(root) + "/" + file.id)
        }
    }
}

/// On-device vault: rclone-crypt ciphertext stored under Application Support, so files are
/// encrypted at rest and portable to a WebDAV backend using the same keys. No network, no
/// account — works offline out of the box.
enum LocalStore {
    /// Base directory that holds every local vault folder.
    static var base: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CryptVault/Vaults", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Absolute path of a vault whose folder name is `folderName`. The name is reduced to safe
    /// path components — "/", "." and ".." segments can never escape the Vaults directory.
    static func rootPath(forFolder folderName: String) -> String {
        let parts = folderName.components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != ".." && !$0.hasPrefix(".") }
        let safe = parts.joined(separator: "_")
        return base.appendingPathComponent(safe.isEmpty ? "vault" : safe, isDirectory: true).path
    }

    private static func rootURL(_ rootPath: String) -> URL { URL(fileURLWithPath: rootPath, isDirectory: true) }

    static func ensureRoot(_ rootPath: String) {
        try? FileManager.default.createDirectory(at: rootURL(rootPath), withIntermediateDirectories: true)
    }

    static func list(rootPath: String) throws -> [DriveFile] {
        let root = rootURL(rootPath)
        ensureRoot(rootPath)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var out: [DriveFile] = []
        for case let url as URL in en {
            let name = url.lastPathComponent
            if name.hasPrefix(".") { continue }                       // skip .DS_Store etc.
            let vals = try? url.resourceValues(forKeys: Set(keys))
            guard vals?.isRegularFile == true else { continue }
            guard url.path.hasPrefix(prefix) else { continue }
            let rel = String(url.path.dropFirst(prefix.count))
            guard !rel.isEmpty else { continue }
            out.append(DriveFile(id: rel, encryptedName: name, encryptedPath: rel,
                                 decryptedPath: nil, isFolder: false,
                                 size: vals?.fileSize.map(Int64.init),
                                 modifiedTime: vals?.contentModificationDate))
        }
        return out
    }

    static func read(rootPath: String, id: String) throws -> Data {
        try Data(contentsOf: rootURL(rootPath).appendingPathComponent(id))
    }

    static func write(rootPath: String, encPath: String, data: Data) throws {
        let dest = rootURL(rootPath).appendingPathComponent(encPath)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: dest, options: .atomic)
    }

    static func delete(rootPath: String, id: String) throws {
        try FileManager.default.removeItem(at: rootURL(rootPath).appendingPathComponent(id))
    }
}
