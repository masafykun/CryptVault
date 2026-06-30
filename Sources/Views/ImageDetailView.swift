import SwiftUI
import UIKit

/// Full-screen, Photos-like viewer. Shows the thumbnail instantly, then swaps in the
/// full-resolution decrypted image. Pinch / double-tap to zoom, drag to pan when zoomed,
/// swipe down (or ✕) to dismiss.
struct PhotoViewer: View {
    let file: DriveFile
    let placeholder: UIImage?
    let loadFull: (DriveFile) async -> UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var full: UIImage?

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero        // pan when zoomed
    @State private var lastOffset: CGSize = .zero
    @State private var dismissDrag: CGFloat = 0       // swipe-down-to-dismiss when not zoomed

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let img = full ?? placeholder {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(x: offset.width, y: offset.height + dismissDrag)
                    .gesture(dragGesture)
                    .simultaneousGesture(zoomGesture)
                    .onTapGesture(count: 2) { toggleZoom() }
            }

            if full == nil { ProgressView().tint(.white) }

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

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in scale = max(1, lastScale * value) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { withAnimation { resetZoom() } }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                if scale > 1 {
                    offset = CGSize(width: lastOffset.width + v.translation.width,
                                    height: lastOffset.height + v.translation.height)
                } else {
                    dismissDrag = v.translation.height
                }
            }
            .onEnded { v in
                if scale > 1 {
                    lastOffset = offset
                } else if abs(v.translation.height) > 120 {
                    dismiss()
                } else {
                    withAnimation { dismissDrag = 0 }
                }
            }
    }

    private func toggleZoom() {
        withAnimation {
            if scale > 1 { resetZoom() }
            else { scale = 2.5; lastScale = 2.5 }
        }
    }

    private func resetZoom() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}
