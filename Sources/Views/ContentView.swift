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
                    PhotoViewer(file: f, placeholder: vm.cachedThumbnail(f.id)) { await vm.fullImage(for: $0) }
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 2)], spacing: 2) {
                    ForEach(vm.files.prefix(vm.visibleCount), id: \.id) { f in
                        ThumbCell(file: f, load: { await vm.thumbnail(for: $0) }, onTap: { vm.selected = f })
                            .onAppear {
                                if f.id == vm.files.prefix(vm.visibleCount).last?.id { vm.loadMore() }
                            }
                    }
                }
                .padding(.horizontal, 2)
                if vm.visibleCount < vm.files.count {
                    ProgressView().padding(.bottom, 24)
                }
            }
        }
    }

    /// One grid tile. Holds its own decrypted thumbnail in @State, so loading it only
    /// re-renders this cell — not the whole grid (this is what keeps scrolling smooth).
    private struct ThumbCell: View {
        let file: DriveFile
        let load: (DriveFile) async -> UIImage?
        let onTap: () -> Void
        @State private var image: UIImage?

        var body: some View {
            Button(action: onTap) {
                Color.gray.opacity(0.12)
                    .aspectRatio(1, contentMode: .fit)      // square tile (no overlap)
                    .overlay {
                        if let image { Image(uiImage: image).resizable().scaledToFill() }
                        else { ProgressView() }
                    }
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .task(id: file.id) { if image == nil { image = await load(file) } }
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
