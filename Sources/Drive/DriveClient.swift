import Foundation

enum DriveError: Error, LocalizedError {
    case http(Int)
    case httpBody(Int, String)      // carries Google's error body for diagnosis
    var errorDescription: String? {
        switch self {
        case .http(let c): return "Drive API HTTP \(c)"
        case .httpBody(let c, let b): return "HTTP \(c): \(b)"
        }
    }
}

private extension Data {
    mutating func appendString(_ s: String) { append(Data(s.utf8)) }
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
                                     isFolder: false, size: child.size,
                                     modifiedTime: child.modifiedTime))
            }
        }
        return out
    }

    /// Upload a new file (raw bytes) into a parent folder via multipart. Returns the new fileId.
    func uploadFile(name: String, parentID: String, data: Data,
                    mimeType: String = "application/octet-stream") async throws -> String {
        let boundary = "cryptvault-\(UUID().uuidString)"
        var body = Data()
        let meta: [String: Any] = ["name": name, "parents": [parentID]]
        let metaData = try JSONSerialization.data(withJSONObject: meta)
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metaData)
        body.appendString("\r\n--\(boundary)\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.appendString("\r\n--\(boundary)--\r\n")

        var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (respData, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw DriveError.httpBody(code, String(data: respData, encoding: .utf8) ?? "") }
        struct R: Codable { let id: String }
        return try JSONDecoder().decode(R.self, from: respData).id
    }

    /// Create a folder. `parentID == nil` creates it at My Drive root (used for the vault root).
    func createFolder(name: String, parentID: String?) async throws -> String {
        var meta: [String: Any] = ["name": name,
                                   "mimeType": "application/vnd.google-apps.folder"]
        if let parentID { meta["parents"] = [parentID] }
        var req = URLRequest(url: URL(string: "\(base)/files?fields=id")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: meta)
        let (respData, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw DriveError.httpBody(code, String(data: respData, encoding: .utf8) ?? "") }
        struct R: Codable { let id: String }
        return try JSONDecoder().decode(R.self, from: respData).id
    }

    /// Move a file to Drive trash (recoverable for ~30 days).
    func trash(fileID: String) async throws {
        var req = URLRequest(url: URL(string: "\(base)/files/\(fileID)?fields=id")!)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["trashed": true])
        let (respData, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw DriveError.httpBody(code, String(data: respData, encoding: .utf8) ?? "") }
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
        var out = [DriveFile]()
        var pageToken: String?
        repeat {
            var comps = URLComponents(string: "\(base)/files")!
            comps.queryItems = [
                .init(name: "q", value: query),
                .init(name: "fields", value: "nextPageToken,files(id,name,mimeType,size,modifiedTime)"),
                .init(name: "pageSize", value: "1000"),
                .init(name: "spaces", value: "drive"),
            ]
            if let pageToken { comps.queryItems?.append(.init(name: "pageToken", value: pageToken)) }
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw DriveError.http(code) }
            struct R: Codable {
                let nextPageToken: String?
                let files: [F]
                struct F: Codable { let id: String; let name: String; let mimeType: String; let size: String?; let modifiedTime: String? }
            }
            let r = try JSONDecoder().decode(R.self, from: data)
            out += r.files.map {
                DriveFile(id: $0.id, encryptedName: $0.name, encryptedPath: $0.name, decryptedPath: nil,
                          isFolder: $0.mimeType == "application/vnd.google-apps.folder",
                          size: $0.size.flatMap { Int64($0) },
                          modifiedTime: $0.modifiedTime.flatMap(Self.parseDate))
            }
            pageToken = r.nextPageToken
        } while pageToken != nil
        return out
    }

    /// RFC3339 (e.g. "2026-07-01T09:59:04.000Z") -> Date. Tolerates missing fractional seconds.
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    static func parseDate(_ s: String) -> Date? { isoFrac.date(from: s) ?? iso.date(from: s) }
}
