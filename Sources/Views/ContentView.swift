import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var vm = BackupViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("CryptVault")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if vm.isConnected {
                            Button("更新") { Task { await vm.loadList() } }
                        } else {
                            Button("接続") { Task { await vm.connect() } }
                        }
                    }
                }
                .overlay(alignment: .bottom) { statusBar }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .fullScreenCover(item: $vm.selected) { f in
                    if f.isVideo {
                        VideoViewer(file: f) { await vm.videoURL(for: $0) }
                    } else {
                        PhotoViewer(file: f, placeholder: vm.cachedThumbnail(f.id)) { await vm.fullImage(for: $0) }
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        if vm.files.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "lock.doc").font(.system(size: 48)).foregroundStyle(.secondary)
                Text(vm.isConnected ? "「更新」でバックアップ一覧を取得" : "「接続」でGoogle Driveに接続")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                if vm.isBusy { ProgressView() }
            }.padding()
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 2)], spacing: 2,
                          pinnedViews: [.sectionHeaders]) {
                    ForEach(vm.sections) { section in
                        Section {
                            ForEach(section.files, id: \.id) { f in
                                ThumbCell(file: f, load: { await vm.thumbnail(for: $0) }, onTap: { vm.selected = f })
                            }
                        } header: {
                            sectionHeader(section.dir, count: section.files.count)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func sectionHeader(_ dir: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text("📁 " + (dir.isEmpty ? "(ルート)" : dir))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1).truncationMode(.head)
            Spacer()
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    /// One grid tile. Holds its own decrypted thumbnail in @State, so loading it only
    /// re-renders this cell — not the whole grid (this is what keeps scrolling smooth).
    private struct ThumbCell: View {
        let file: DriveFile
        let load: (DriveFile) async -> UIImage?
        let onTap: () -> Void
        @State private var image: UIImage?
        @State private var loaded = false      // distinguishes "still loading" from "no thumbnail"

        var body: some View {
            Button(action: onTap) {
                Color.gray.opacity(0.12)
                    .aspectRatio(1, contentMode: .fit)      // square tile (no overlap)
                    .overlay {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else if loaded {
                            Image(systemName: file.isVideo ? "film" : "photo")
                                .font(.title2).foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if file.isVideo {
                            Image(systemName: "play.circle.fill")
                                .font(.callout)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 2)
                                .padding(4)
                        }
                    }
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .task(id: file.id) { if image == nil { image = await load(file); loaded = true } }
        }
    }

    @ViewBuilder private var statusBar: some View {
        if !vm.status.isEmpty {
            Text(vm.status)
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 10)
        }
    }

}
