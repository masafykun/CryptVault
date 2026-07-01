import Foundation

struct WebDAVItem {
    let path: String        // decoded absolute path on the server, e.g. "/secure-vault/enc/enc"
    let isCollection: Bool
    let size: Int64?
    let modified: Date?
}

/// Minimal WebDAV client (PROPFIND / GET / PUT / MKCOL / DELETE) over HTTP Basic auth.
/// Works with Hetzner Storage Box, Nextcloud, Nutstore, etc.
struct WebDAVClient {
    let baseURL: String     // e.g. "https://u123456.your-storagebox.de"
    let user: String
    let pass: String

    private func makeRequest(_ method: String, path: String) -> URLRequest {
        var comps = baseURL
        if comps.hasSuffix("/") { comps.removeLast() }
        let p = path.hasPrefix("/") ? path : "/" + path
        // base32hex path segments are URL-safe (0-9a-v), but encode defensively.
        let encoded = p.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        var req = URLRequest(url: URL(string: comps + encoded)!)
        req.httpMethod = method
        let cred = Data("\(user):\(pass)".utf8).base64EncodedString()
        req.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        return req
    }

    // MARK: - Operations

    /// PROPFIND one directory level (Depth: 1). Returns the directory's children (excludes itself).
    func propfind(path: String) async throws -> [WebDAVItem] {
        var req = makeRequest("PROPFIND", path: path.hasSuffix("/") ? path : path + "/")
        req.setValue("1", forHTTPHeaderField: "Depth")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("""
        <?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop>\
        <d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>
        """.utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 207 || code == 200 else { throw DriveError.httpBody(code, String(data: data, encoding: .utf8) ?? "") }
        let self_ = Self.normalize(path)
        return WebDAVParser.parse(data).filter { Self.normalize($0.path) != self_ }
    }

    /// Recursively collect every leaf file under `root`.
    func walk(root: String) async throws -> [WebDAVItem] {
        var out = [WebDAVItem]()
        var stack = [root]
        while let dir = stack.popLast() {
            let children: [WebDAVItem]
            do { children = try await propfind(path: dir) }
            catch { continue }   // missing/inaccessible dir -> skip
            for c in children {
                if c.isCollection { stack.append(c.path) } else { out.append(c) }
            }
        }
        return out
    }

    func get(path: String) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: makeRequest("GET", path: path))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw DriveError.httpBody(code, "") }
        return data
    }

    func put(path: String, data: Data) async throws {
        var req = makeRequest("PUT", path: path)
        req.httpBody = data
        let (respData, resp) = try await URLSession.shared.upload(for: req, from: data)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...204).contains(code) else { throw DriveError.httpBody(code, String(data: respData, encoding: .utf8) ?? "") }
    }

    /// Create a collection (folder). Treats "already exists" (405/301) as success.
    func mkcol(path: String) async throws {
        let (_, resp) = try await URLSession.shared.data(for: makeRequest("MKCOL", path: path))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...204).contains(code) || code == 405 || code == 301 else { throw DriveError.httpBody(code, "") }
    }

    func delete(path: String) async throws {
        let (_, resp) = try await URLSession.shared.data(for: makeRequest("DELETE", path: path))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...204).contains(code) || code == 404 else { throw DriveError.httpBody(code, "") }
    }

    /// Ensure every parent collection of `filePath` exists (creates them top-down).
    func ensureParents(of filePath: String) async throws {
        let segs = filePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard segs.count > 1 else { return }
        var acc = ""
        for seg in segs.dropLast() {
            acc += "/" + seg
            try await mkcol(path: acc)
        }
    }

    static func normalize(_ path: String) -> String {
        var p = path
        if let decoded = p.removingPercentEncoding { p = decoded }
        while p.hasSuffix("/") { p.removeLast() }
        return p.hasPrefix("/") ? p : "/" + p
    }
}

/// Pulls <response> entries out of a PROPFIND multistatus body (namespace-agnostic).
final class WebDAVParser: NSObject, XMLParserDelegate {
    private var items = [WebDAVItem]()
    private var curHref = ""
    private var curLen: String?
    private var curMod: String?
    private var curIsCollection = false
    private var text = ""
    private var inResponse = false

    static func parse(_ data: Data) -> [WebDAVItem] {
        let p = WebDAVParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = p
        parser.parse()
        return p.items
    }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch el.lowercased() {
        case "response": inResponse = true; curHref = ""; curLen = nil; curMod = nil; curIsCollection = false
        case "collection": if inResponse { curIsCollection = true }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch el.lowercased() {
        case "href": curHref = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "getcontentlength": curLen = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "getlastmodified": curMod = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "response":
            inResponse = false
            let path = WebDAVClient.normalize(curHref)
            items.append(WebDAVItem(path: path, isCollection: curIsCollection,
                                    size: curLen.flatMap { Int64($0) },
                                    modified: curMod.flatMap { WebDAVParser.httpDate.date(from: $0) }))
        default: break
        }
    }

    static let httpDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
}
