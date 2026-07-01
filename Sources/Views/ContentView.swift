import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

/// App shell: one tab per profile (vault). Switching tabs flips between vaults; each keeps its
/// own loaded state. A trailing "設定" tab manages profiles and global settings.
struct ContentView: View {
    @StateObject private var store = ProfileStore()
    @State private var selection = ""

    var body: some View {
        TabView(selection: $selection) {
            ForEach(store.profiles) { profile in
                VaultView(profile: profile)
                    .tabItem { Label(profile.name, systemImage: "lock.doc.fill") }
                    .tag(profile.id)
            }
            SettingsView(profileID: store.activeID)
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag("__settings__")
        }
        .environmentObject(store)
        .onAppear {
            if selection != "__settings__" && !store.profiles.contains(where: { $0.id == selection }) {
                selection = store.activeID
            }
        }
        .onChange(of: selection) { new in
            if new != "__settings__" { store.setActive(new) }
        }
    }
}

/// One vault tab: the folder browser for a single profile. Owns its own view model so switching
/// tabs preserves each vault's loaded list/scroll state.
struct VaultView: View {
    let profile: Profile
    @StateObject private var vm: BackupViewModel
    @EnvironmentObject private var store: ProfileStore
    @State private var showSettings = false

    init(profile: Profile) {
        self.profile = profile
        _vm = StateObject(wrappedValue: BackupViewModel(profileID: profile.id))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.sections.isEmpty {
                    emptyState
                } else {
                    FolderListView(vm: vm)
                }
            }
            .navigationTitle(profile.name)
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
            .sheet(isPresented: $showSettings, onDismiss: { vm.reloadConnection() }) {
                SettingsView(profileID: profile.id)
            }
            .navigationDestination(for: FolderRoute.self) { route in
                FolderGridView(dir: route.dir, vm: vm)
            }
        }
        .onAppear { vm.reloadConnection() }
    }

    private var gearButton: some View {
        Button { showSettings = true } label: { Image(systemName: "gearshape") }
    }

    @ViewBuilder private var trailingActions: some View {
        if vm.isConnected { AddButton(vm: vm, dir: "") }      // add to vault root
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
            Text(vm.isConnected ? "「更新」でこのVaultの一覧を取得" : "「接続」でGoogle Driveに接続")
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

/// Thumbnail tile size (grid density), persisted in UserDefaults.
enum ThumbSize: String, CaseIterable, Identifiable {
    case small, medium, large, xlarge
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        case .xlarge: return "特大"
        }
    }
    /// Minimum tile width fed to the adaptive grid.
    var minWidth: CGFloat {
        switch self {
        case .small: return 80
        case .medium: return 120
        case .large: return 170
        case .xlarge: return 240
        }
    }
}

/// View-options menu (sort order + thumbnail size), used in the folder list and grid toolbars.
struct SortMenu: View {
    @ObservedObject var vm: BackupViewModel
    @AppStorage("thumbSize") private var thumbSizeRaw = ThumbSize.medium.rawValue
    var body: some View {
        Menu {
            Picker("並び順", selection: $vm.sortOrder) {
                ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
            }
            Picker("サムネの大きさ", selection: $thumbSizeRaw) {
                ForEach(ThumbSize.allCases) { Text($0.label).tag($0.rawValue) }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
    }
}

/// Toolbar "+" menu: add from the photo library or from Files, encrypt, and upload into `dir`.
struct AddButton: View {
    @ObservedObject var vm: BackupViewModel
    let dir: String
    @State private var importing = false
    @State private var showPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        Menu {
            Button { showPhotos = true } label: { Label("写真から", systemImage: "photo") }
            Button { importing = true } label: { Label("ファイルから", systemImage: "folder") }
        } label: {
            Image(systemName: "plus")
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result, !urls.isEmpty {
                Task { await vm.addFiles(urls, toDir: dir) }
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems,
                      maxSelectionCount: 30, matching: .any(of: [.images, .videos]))
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            let picked = items
            photoItems = []
            Task { await vm.addPhotos(picked, toDir: dir) }
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
    @State private var pendingDelete: DriveFile?
    @AppStorage("thumbSize") private var thumbSizeRaw = ThumbSize.medium.rawValue

    private var files: [DriveFile] { vm.sections.first { $0.dir == dir }?.files ?? [] }
    private var title: String { vm.sections.first { $0.dir == dir }?.displayName ?? dir }
    private var thumbMin: CGFloat { (ThumbSize(rawValue: thumbSizeRaw) ?? .medium).minWidth }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbMin), spacing: 2)], spacing: 2) {
                ForEach(files, id: \.id) { f in
                    ThumbCell(file: f, load: { await vm.thumbnail(for: $0) },
                              onTap: { vm.selected = f },
                              onDelete: { pendingDelete = f })
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem { AddButton(vm: vm, dir: dir) }
            ToolbarItem { SortMenu(vm: vm) }
        }
        .confirmationDialog("このファイルを削除しますか？",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { file in
            Button("削除（ゴミ箱へ）", role: .destructive) {
                Task { await vm.deleteFile(file) }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { file in
            Text(file.displayName)
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
    var onDelete: (() -> Void)? = nil
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
        .contextMenu {
            if let onDelete {
                Button(role: .destructive) { onDelete() } label: { Label("削除", systemImage: "trash") }
            }
        }
    }
}
