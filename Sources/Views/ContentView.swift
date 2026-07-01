import SwiftUI

struct ContentView: View {
    @StateObject private var vm = BackupViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.sections.isEmpty {
                    emptyState
                } else {
                    FolderListView(vm: vm)
                }
            }
            .navigationTitle("CryptVault")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { gearButton }
                ToolbarItemGroup(placement: .topBarTrailing) { trailingActions }
                #else
                ToolbarItemGroup {
                    gearButton
                    trailingActions
                }
                #endif
            }
            .overlay(alignment: .bottom) { statusBar }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .navigationDestination(for: FolderRoute.self) { route in
                FolderGridView(dir: route.dir, vm: vm)
            }
        }
    }

    private var gearButton: some View {
        Button { showSettings = true } label: { Image(systemName: "gearshape") }
    }

    @ViewBuilder private var trailingActions: some View {
        if !vm.sections.isEmpty { SortMenu(vm: vm) }
        if vm.isConnected {
            Button("更新") { Task { await vm.loadList() } }
        } else {
            Button("接続") { Task { await vm.connect() } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.doc").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(vm.isConnected ? "「更新」でバックアップ一覧を取得" : "「接続」でGoogle Driveに接続")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            if vm.isBusy { ProgressView() }
        }.padding()
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

/// Sort-order picker used in both the folder list and the grid toolbars.
struct SortMenu: View {
    @ObservedObject var vm: BackupViewModel
    var body: some View {
        Menu {
            Picker("並び順", selection: $vm.sortOrder) {
                ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }
}

/// First screen: pick a folder. Solves "output has too many files to reach other folders".
struct FolderListView: View {
    @ObservedObject var vm: BackupViewModel

    var body: some View {
        List(vm.sections) { section in
            NavigationLink(value: FolderRoute(dir: section.dir)) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill").font(.title3).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.displayName)
                            .font(.body).lineLimit(1).truncationMode(.middle)
                        Text(subtitle(section)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(section.count)").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
    }

    private func subtitle(_ s: FolderSection) -> String {
        var parts = ["\(s.count) 件"]
        if let d = s.latestModified { parts.append(Self.fmt.string(from: d)) }
        return parts.joined(separator: "  ・  ")
    }
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd HH:mm"; return f
    }()
}

/// Second screen: the thumbnail grid for a single folder.
struct FolderGridView: View {
    let dir: String
    @ObservedObject var vm: BackupViewModel

    private var files: [DriveFile] { vm.sections.first { $0.dir == dir }?.files ?? [] }
    private var title: String { vm.sections.first { $0.dir == dir }?.displayName ?? dir }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 2)], spacing: 2) {
                ForEach(files, id: \.id) { f in
                    ThumbCell(file: f, load: { await vm.thumbnail(for: $0) }, onTap: { vm.selected = f })
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem { SortMenu(vm: vm) }
        }
        .fullCover(item: $vm.selected) { f in
            if f.usesVLC {
                VLCVideoViewer(file: f) { await vm.videoURL(for: $0) }
            } else if f.usesAVFoundation {
                VideoViewer(file: f) { await vm.videoURL(for: $0) }
            } else {
                PhotoViewer(file: f, placeholder: vm.cachedThumbnail(f.id)) { await vm.fullImage(for: $0) }
            }
        }
    }
}

/// One grid tile. Holds its own decrypted thumbnail in @State, so loading it only
/// re-renders this cell — not the whole grid (this is what keeps scrolling smooth).
struct ThumbCell: View {
    let file: DriveFile
    let load: (DriveFile) async -> PlatformImage?
    let onTap: () -> Void
    @State private var image: PlatformImage?
    @State private var loaded = false      // distinguishes "still loading" from "no thumbnail"

    var body: some View {
        Button(action: onTap) {
            Color.gray.opacity(0.12)
                .aspectRatio(1, contentMode: .fit)      // square tile (no overlap)
                .overlay {
                    if let image {
                        Image(platformImage: image).resizable().scaledToFill()
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
