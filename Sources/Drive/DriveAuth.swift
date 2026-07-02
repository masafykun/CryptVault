import Foundation
import CryptoKit
import AuthenticationServices
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct OAuthToken: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiry: Date
    var grantedScope: String? = nil          // space-separated scopes Google actually granted
    var isValid: Bool { Date() < expiry.addingTimeInterval(-60) }

    /// True when Google granted full read/write drive access (needed for upload/delete).
    var canWrite: Bool {
        (grantedScope ?? "").split(separator: " ").map(String.init)
            .contains("https://www.googleapis.com/auth/drive")
    }
}

enum DriveAuthError: Error, LocalizedError {
    case noClientID, cancelled, badResponse
    var errorDescription: String? {
        switch self {
        case .noClientID:  return "OAuth client id is not set"
        case .cancelled:   return "認証がキャンセルされました"
        case .badResponse: return "認証レスポンスが不正です"
        }
    }
}

/// Google OAuth (Authorization Code + PKCE) via ASWebAuthenticationSession.
/// TODO(setup): create an *iOS* OAuth client in Google Cloud Console and paste its id
/// below. The bundle's URL scheme (com.masafy.cryptvault) is already wired in project.yml.
final class DriveAuth: NSObject {

    // Full drive scope: needed to upload/create/delete (readonly can't write, and drive.file
    // can't touch files rclone created). Restricted scope, but fine for a personal client in
    // Testing mode with yourself as the test user.
    static let scope = "https://www.googleapis.com/auth/drive"

    /// Your Google OAuth **iOS** client id, set in the app's Settings (not hard-coded), e.g.
    /// "1234567890-abcdef.apps.googleusercontent.com". Stored in UserDefaults; it is not a secret.
    private var clientID: String {
        (UserDefaults.standard.string(forKey: "googleClientID") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// iOS OAuth uses the *reversed* client id as the redirect URL scheme — derived at runtime.
    private var redirectScheme: String {
        guard let r = clientID.range(of: ".apps.googleusercontent.com") else { return "" }
        return "com.googleusercontent.apps.\(clientID[..<r.lowerBound])"
    }
    private var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    private var pkceVerifier = ""
    private var stateToken = ""
    private var session: ASWebAuthenticationSession?   // retain during the flow

    func authorize() async throws -> OAuthToken {
        guard clientID.hasSuffix(".apps.googleusercontent.com") else { throw DriveAuthError.noClientID }
        pkceVerifier = Self.randomURLSafe(64)
        stateToken = Self.randomURLSafe(16)
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: DriveAuth.scope),
            .init(name: "code_challenge", value: Self.codeChallenge(pkceVerifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "state", value: stateToken),
        ]
        let callback = try await present(authURL: comps.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        // The callback must carry back our `state` (CSRF/defense-in-depth on top of PKCE).
        guard let code = items?.first(where: { $0.name == "code" })?.value,
              items?.first(where: { $0.name == "state" })?.value == stateToken
        else { throw DriveAuthError.badResponse }
        return try await exchange(code: code)
    }

    private func present(authURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: authURL,
                                               callbackURLScheme: redirectScheme) { url, error in
                if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? DriveAuthError.cancelled) }
            }
            s.presentationContextProvider = self
            // Fresh session each time: avoids silently reusing an older (readonly) grant via SSO,
            // so newly-added scopes are actually presented and granted.
            s.prefersEphemeralWebBrowserSession = true
            self.session = s
            if !s.start() { cont.resume(throwing: DriveAuthError.cancelled) }
        }
    }

    /// Exchange the stored refresh token for a fresh access token (no user interaction).
    /// Google usually omits a new refresh_token on refresh, so we keep the existing one.
    func refresh(_ token: OAuthToken) async throws -> OAuthToken {
        guard clientID.hasSuffix(".apps.googleusercontent.com") else { throw DriveAuthError.noClientID }
        guard let rt = token.refreshToken else { throw DriveAuthError.badResponse }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formEncode([
            "client_id": clientID,
            "refresh_token": rt,
            "grant_type": "refresh_token",
        ]).data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw DriveAuthError.badResponse }
        struct Resp: Codable { let access_token: String; let refresh_token: String?; let expires_in: Double?; let scope: String? }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        return OAuthToken(accessToken: r.access_token,
                          refreshToken: r.refresh_token ?? token.refreshToken,
                          expiry: Date().addingTimeInterval(r.expires_in ?? 3500),
                          grantedScope: r.scope ?? token.grantedScope)
    }

    private func exchange(code: String) async throws -> OAuthToken {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formEncode([
            "client_id": clientID,
            "code": code,
            "code_verifier": pkceVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]).data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw DriveAuthError.badResponse }
        struct Resp: Codable { let access_token: String; let refresh_token: String?; let expires_in: Double?; let scope: String? }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        return OAuthToken(accessToken: r.access_token, refreshToken: r.refresh_token,
                          expiry: Date().addingTimeInterval(r.expires_in ?? 3500),
                          grantedScope: r.scope)
    }

    // MARK: helpers
    static func formEncode(_ dict: [String: String]) -> String {
        dict.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
    }
    static func randomURLSafe(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        let status = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        // A failed CSPRNG must never silently yield an all-zero "random" value.
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return base64url(Data(bytes))
    }
    static func codeChallenge(_ verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
    static func base64url(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension DriveAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
        #else
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #endif
    }
}
