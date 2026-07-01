#if DEBUG
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import RcloneCryptKit

/// DEBUG-only harness for capturing App Store screenshots without UI automation.
/// Driven entirely by launch environment variables (see `launch_app_sim env:`):
///   CV_SEED=1        fill the first (local) vault with demo images across a few folders
///   CV_SCREEN=grid   open straight into a folder's thumbnail grid
///   CV_SCREEN=settings  open the Settings tab
///   CV_SELECT=1      (with grid) open the first image full-screen
/// None of this is compiled into Release builds, so it can never run on the App Store.
enum Screenshot {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var isSeeding: Bool { env["CV_SEED"] == "1" }
    static var screen: String { env["CV_SCREEN"] ?? "" }
    static var selectFirst: Bool { env["CV_SELECT"] == "1" }
    static var disableLock: Bool { env["CV_NOLOCK"] == "1" }

    /// Populate the first local vault with encrypted demo images, using that vault's own crypt
    /// key (so the app decrypts them exactly as it would real content). No-op unless CV_SEED=1.
    @MainActor static func seedIfNeeded() {
        guard isSeeding else { return }
        guard let p = ProfileStore.loadProfiles().first, p.kind == .local else { return }
        let secrets = SecretsStore()
        var pw = secrets.cryptPassword(profile: p.id)
        var salt = secrets.cryptSalt(profile: p.id)
        if pw.isEmpty {
            pw = BackupViewModel.randomKey(); salt = BackupViewModel.randomKey()
            secrets.saveCryptKeys(profile: p.id, password: pw, salt: salt)
        }
        guard let crypt = try? RcloneCrypt(password: pw, salt: salt) else { return }
        let root = LocalStore.rootPath(forFolder: p.folderName)
        LocalStore.ensureRoot(root)
        if let existing = try? LocalStore.list(rootPath: root), !existing.isEmpty { return }  // already seeded

        let plan: [(String, [String])] = [
            ("旅行", ["kyoto", "seaside", "mountain", "old-town", "night", "harbor", "forest", "temple", "market"]),
            ("書類", ["passport", "invoice", "contract", "id-card", "receipt"]),
            ("スクリーンショット", ["home", "chart", "map", "profile", "wallet", "music", "notes"]),
        ]
        var n = 0
        for (folder, names) in plan {
            for name in names {
                guard let jpg = demoImage(index: n) else { n += 1; continue }
                let encRel = crypt.encryptName("\(folder)/\(name).jpg")
                let cipher = crypt.encryptContent([UInt8](jpg))
                try? LocalStore.write(rootPath: root, encPath: encRel, data: Data(cipher))
                n += 1
            }
        }
    }

    /// A colourful abstract portrait image so the demo vault looks like a real photo library.
    static func demoImage(index: Int) -> Data? {
        let w = 1000, h = 1400
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let h1 = Double((index * 47) % 360) / 360.0
        let h2 = Double((index * 47 + 60) % 360) / 360.0
        let grad = CGGradient(colorsSpace: cs,
                              colors: [hsb(h1, 0.65, 0.95), hsb(h2, 0.75, 0.55)] as CFArray,
                              locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: w, y: h), options: [])
        // A couple of translucent circles for depth.
        ctx.setFillColor(hsb(h2, 0.4, 1.0).copy(alpha: 0.20)!)
        ctx.fillEllipse(in: CGRect(x: 120, y: 900, width: 700, height: 700))
        ctx.setFillColor(hsb(h1, 0.3, 1.0).copy(alpha: 0.15)!)
        ctx.fillEllipse(in: CGRect(x: 520, y: 180, width: 520, height: 520))
        guard let img = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(dst)
        return out as Data
    }

    private static func hsb(_ h: Double, _ s: Double, _ v: Double) -> CGColor {
        let i = Int(h * 6), f = h * 6 - Double(i)
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let (r, g, b): (Double, Double, Double)
        switch i % 6 {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                       components: [CGFloat(r), CGFloat(g), CGFloat(b), 1])!
    }
}
#endif
