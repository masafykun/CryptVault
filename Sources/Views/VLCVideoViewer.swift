import SwiftUI

/// Full-screen playback for formats AVFoundation can't decode (webm/mkv/avi/…), via VLC.
/// Decrypts to a temp file (through the view model), loops, tap to play/pause, ✕ to close.
struct VLCVideoViewer: View {
    let file: DriveFile
    let load: (DriveFile) async -> URL?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = VLCController()
    @State private var ready = false
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if ready {
                VLCPlayerView(controller: controller)
                    .ignoresSafeArea()
                    .onTapGesture { controller.togglePlayPause() }
                if !controller.isPlaying {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 6)
                        .onTapGesture { controller.togglePlayPause() }
                }
            } else if failed {
                VStack(spacing: 12) {
                    Image(systemName: "film.slash").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("この動画を復号できませんでした").foregroundStyle(.white)
                    Text(file.displayName)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).padding(.horizontal, 40)
                }
            } else {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("復号中…").font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .task {
            if let url = await load(file) {
                controller.start(url: url)
                ready = true
            } else {
                failed = true
            }
        }
        .onDisappear { controller.stop() }
    }
}
