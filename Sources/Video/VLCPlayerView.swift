import SwiftUI
import VLCKitSPM
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Drives a VLCKit player. VLC decodes formats AVFoundation can't (webm/mkv/avi/…),
/// rendering into a plain platform view. Kept as an ObservableObject so the SwiftUI viewer
/// can show play/pause state and toggle it.
@MainActor
final class VLCController: ObservableObject {
    #if os(macOS)
    let videoView = NSView()
    #else
    let videoView = UIView()
    #endif
    private let player = VLCMediaPlayer()
    @Published var isPlaying = false

    init() {
        #if os(macOS)
        videoView.wantsLayer = true
        videoView.layer?.backgroundColor = NSColor.black.cgColor
        #else
        videoView.backgroundColor = .black
        #endif
        player.drawable = videoView
    }

    func start(url: URL) {
        let media = VLCMedia(url: url)
        media.addOption(":input-repeat=65535")   // loop indefinitely (clips are short)
        player.media = media
        player.play()
        isPlaying = true
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause(); isPlaying = false
        } else {
            player.play(); isPlaying = true
        }
    }

    func stop() { player.stop() }
}

/// Hosts the VLC drawable view inside SwiftUI.
#if os(macOS)
struct VLCPlayerView: NSViewRepresentable {
    @ObservedObject var controller: VLCController
    func makeNSView(context: Context) -> NSView { controller.videoView }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#else
struct VLCPlayerView: UIViewRepresentable {
    @ObservedObject var controller: VLCController
    func makeUIView(context: Context) -> UIView { controller.videoView }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
