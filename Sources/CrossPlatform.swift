import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

// MARK: - Clipboard

enum Clipboard {
    /// Copy sensitive text (crypt keys). On iOS the pasteboard entry is local-only (no Handoff /
    /// universal clipboard) and expires after 60 seconds, so keys don't linger for other apps.
    static func copySensitive(_ s: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #else
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: s]],
            options: [.localOnly: true,
                      .expirationDate: Date().addingTimeInterval(60)])
        #endif
    }
}

// MARK: - Image bridging (UIImage / NSImage)

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

extension PlatformImage {
    /// Build a platform image from a decoded CGImage.
    static func fromCG(_ cg: CGImage) -> PlatformImage {
        #if os(macOS)
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #else
        return UIImage(cgImage: cg)
        #endif
    }
}

// MARK: - Colors

extension Color {
    /// Default window/screen background, per platform.
    static var appBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

// MARK: - Full-screen presentation

extension View {
    /// `fullScreenCover` on iOS; `sheet` on macOS (which has no full-screen cover).
    @ViewBuilder
    func fullCover<Item: Identifiable, C: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> C
    ) -> some View {
        #if os(macOS)
        self.sheet(item: item, content: content)
        #else
        self.fullScreenCover(item: item, content: content)
        #endif
    }
}
