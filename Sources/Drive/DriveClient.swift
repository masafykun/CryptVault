import Foundation

enum DriveError: Error, LocalizedError {
    case http(Int)
    var errorDescription: String? { if case let .http(c) = self { return "Drive API HTTP \(c)" }; return nil }
}

/// Thin Google Drive v3 REST client (read-only). Bring your own access token.
/// NOTE(skeleton): pagination (`nextPageToken`) is not yet handled — see TODO in `rawList`.
struct DriveClient {
    let accessToken: String
    private let base = "https://www.googleapis.com/drive/v3"

    func findFolderID(named name: String, parent: String? = nil) async throws -> String? {
        var q = "name = '\(name)' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        if let parent { q += " and '\(parent)' in parents" }
        return try await rawList(query: q).first?.id
    }

    func listChildren(folderID: String) async throws -> [DriveFile] {
        try await rawList(query: "'\(folderID)' in parents and trashed = false")
    }

    /// Recursively walk a folder, returning every leaf file with its full *encrypted* path.
    func walk(folderID: String, prefix: String = "") async throws -> [DriveFile] {
        var out = [DriveFile]()
        for child in try await listChildren(folderID: folderID) {
            let path = prefix.isEmpty ? child.encryptedName : prefix + "/" + child.encryptedName
            if child.isFolder {
                out += try await walk(folderID: child.id, prefix: path)
            } else {
                out.append(DriveFile(id: child.id, encryptedName: child.encryptedName,
                                     encryptedPath: path, decryptedPath: nil,
                                     isFolder: false, size: child.size))
            }
        }
        return out
    }

    func downloadMedia(fileID: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "\(base)/files/\(fileID)?alt=media")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw DriveError.http(code) }
        return data
    }

    private func rawList(query: String) async throws -> [DriveFile] {
        var comps = URLComponents(string: "\(base)/files")!
        comps.queryItems = [
            .init(name: "q", value: query),
            .init(name: "fields", value: "files(id,name,mimeType,size)"),
            .init(name: "pageSize", value: "1000"),    // TODO: follow nextPageToken for >1000
            .init(name: "spaces", value: "drive"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw DriveError.http(code) }
        struct R: Codable {
            let files: [F]
            struct F: Codable { let id: String; let name: String; let mimeType: String; let size: String? }
        }
        let r = try JSONDecoder().decode(R.self, from: data)
        return r.files.map {
            DriveFile(id: $0.id, encryptedName: $0.name, encryptedPath: $0.name, decryptedPath: nil,
                      isFolder: $0.mimeType == "application/vnd.google-apps.folder",
                      size: $0.size.flatMap { Int64($0) })
        }
    }
}
