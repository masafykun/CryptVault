import SwiftUI
import VLCKitSPM

/// Drives an MobileVLCKit player. VLC decodes formats AVFoundation can't (webm/mkv/avi/…),
/// rendering into a plain UIView. Kept as an ObservableObject so the SwiftUI viewer can
/// show play/pause state and toggle it.
@MainActor
final class VLCController: ObservableObject {
    let videoView = UIView()
    private let player = VLCMediaPlayer()
    @Published var isPlaying = false

    init() {
        videoView.backgroundColor = .black
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

/// Hosts the VLC drawable UIView inside SwiftUI.
struct VLCPlayerView: UIViewRepresentable {
    @ObservedObject var controller: VLCController
    func makeUIView(context: Context) -> UIView { controller.videoView }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
