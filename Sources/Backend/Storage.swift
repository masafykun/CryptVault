import Foundation

/// Which storage a profile talks to.
enum BackendKind: String, Codable, CaseIterable, Identifiable {
    case googleDrive, webdav
    var id: String { rawValue }
    var label: String {
        switch self {
        case .googleDrive: return "Google Drive"
        case .webdav: return "WebDAV（Hetzner等）"
        }
    }
}

/// Everything a storage operation needs, captured as a Sendable value so it can cross actors.
enum BackendConfig: Sendable {
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
        case let .drive(token, _):
            try await DriveClient(accessToken: token).trash(fileID: file.id)
        case let .webdav(base, user, pass, root):
            let client = WebDAVClient(baseURL: base, user: user, pass: pass)
            try await client.delete(path: WebDAVClient.normalize(root) + "/" + file.id)
        }
    }
}
