import Foundation
import CoreGraphics
import VLCKitSPM

/// Generates a still-frame thumbnail for a video only VLC can decode (webm/mkv/avi/…),
/// wrapping VLCMediaThumbnailer's delegate callbacks in a single async call.
///
/// The thumbnailer's `delegate` is unretained, so the helper keeps a strong reference to
/// itself (`selfRef`) until a callback fires. VLCMediaThumbnailer has its own timeout, so
/// the continuation is always resumed (image or nil) — no hangs.
final class VLCThumbnailer: NSObject, VLCMediaThumbnailerDelegate {
    private var continuation: CheckedContinuation<PlatformImage?, Never>?
    private var thumbnailer: VLCMediaThumbnailer?
    private var media: VLCMedia?
    private var selfRef: VLCThumbnailer?

    static func thumbnail(url: URL, maxPixel: CGFloat) async -> PlatformImage? {
        await VLCThumbnailer().fetch(url: url, maxPixel: maxPixel)
    }

    private func fetch(url: URL, maxPixel: CGFloat) async -> PlatformImage? {
        await withCheckedContinuation { cont in
            self.continuation = cont
            self.selfRef = self
            // Drive it on the main thread; VLCMediaThumbnailer delivers its callbacks there.
            DispatchQueue.main.async {
                let m = VLCMedia(url: url)
                self.media = m
                let t = VLCMediaThumbnailer(media: m, andDelegate: self)
                t.thumbnailWidth = maxPixel
                t.thumbnailHeight = 0          // 0 => keep the source aspect ratio
                t.snapshotPosition = 0.1       // 10% in (avoids black first frames)
                self.thumbnailer = t
                t.fetchThumbnail()
            }
        }
    }

    func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        finish(PlatformImage.fromCG(thumbnail))
    }

    func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        finish(nil)
    }

    private func finish(_ image: PlatformImage?) {
        continuation?.resume(returning: image)
        continuation = nil
        thumbnailer = nil
        media = nil
        selfRef = nil
    }
}
