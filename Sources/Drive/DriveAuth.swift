import Foundation
import UIKit
import CryptoKit
import AuthenticationServices

struct OAuthToken: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiry: Date
    var isValid: Bool { Date() < expiry.addingTimeInterval(-60) }
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

    static let clientID = "YOUR_IOS_CLIENT_ID.apps.googleusercontent.com"
    static let redirectScheme = "com.masafy.cryptvault"
    static var redirectURI: String { "\(redirectScheme):/oauth2redirect" }
    static let scope = "https://www.googleapis.com/auth/drive.readonly"

    private var pkceVerifier = ""
    private var session: ASWebAuthenticationSession?   // retain during the flow

    func authorize() async throws -> OAuthToken {
        guard !DriveAuth.clientID.hasPrefix("YOUR_") else { throw DriveAuthError.noClientID }
        pkceVerifier = Self.randomURLSafe(64)
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: DriveAuth.clientID),
            .init(name: "redirect_uri", value: DriveAuth.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: DriveAuth.scope),
            .init(name: "code_challenge", value: Self.codeChallenge(pkceVerifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        let callback = try await present(authURL: comps.url!)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw DriveAuthError.badResponse }
        return try await exchange(code: code)
    }

    private func present(authURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: authURL,
                                               callbackURLScheme: DriveAuth.redirectScheme) { url, error in
                if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? DriveAuthError.cancelled) }
            }
            s.presentationContextProvider = self
            self.session = s
            if !s.start() { cont.resume(throwing: DriveAuthError.cancelled) }
        }
    }

    private func exchange(code: String) async throws -> OAuthToken {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formEncode([
            "client_id": DriveAuth.clientID,
            "code": code,
            "code_verifier": pkceVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": DriveAuth.redirectURI,
        ]).data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Resp: Codable { let access_token: String; let refresh_token: String?; let expires_in: Double? }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        return OAuthToken(accessToken: r.access_token, refreshToken: r.refresh_token,
                          expiry: Date().addingTimeInterval(r.expires_in ?? 3500))
    }

    // MARK: helpers
    static func formEncode(_ dict: [String: String]) -> String {
        dict.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
    }
    static func randomURLSafe(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
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
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
