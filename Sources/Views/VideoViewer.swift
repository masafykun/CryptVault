import SwiftUI
import AVKit

/// Full-screen playback for a decrypted video. Asks the view model to decrypt the file to a
/// temp URL, then plays it with AVPlayer. Only AVFoundation-decodable formats (mp4/mov/m4v)
/// play; anything else shows a graceful "can't play" message instead of a black screen.
struct VideoViewer: View {
    let file: DriveFile
    let load: (DriveFile) async -> URL?

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else if failed {
                VStack(spacing: 12) {
                    Image(systemName: "film.slash").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("この形式は再生できません").foregroundStyle(.white)
                    Text(file.displayName)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).padding(.horizontal, 40)
                }
            } else {
                ProgressView().tint(.white)
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
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
        .task {
            if let url = await load(file) {
                let p = AVPlayer(url: url)
                player = p
                p.play()
            } else {
                failed = true
            }
        }
        .onDisappear { player?.pause() }
    }
}
