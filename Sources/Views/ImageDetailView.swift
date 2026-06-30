import SwiftUI
import UIKit

/// Full-screen, Photos-like viewer. Shows the thumbnail instantly, then swaps in the
/// full-resolution decrypted image. Pinch to zoom, swipe down (or ✕) to dismiss.
struct PhotoViewer: View {
    let file: DriveFile
    let placeholder: UIImage?
    let loadFull: (DriveFile) async -> UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var full: UIImage?
    @State private var scale: CGFloat = 1
    @State private var drag: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let img = full ?? placeholder {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(y: drag.height)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale = max(1, $0) }
                            .onEnded { _ in withAnimation { scale = max(1, scale) } }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { if scale == 1 { drag = $0.translation } }
                            .onEnded { v in
                                if scale == 1, abs(v.translation.height) > 120 { dismiss() }
                                else { withAnimation { drag = .zero } }
                            }
                    )
            }

            if full == nil { ProgressView().tint(.white) }   // loading full-res over the thumbnail

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
        .task { full = await loadFull(file) }
    }
}
