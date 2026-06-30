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
                    PhotoViewer(file: f, placeholder: vm.thumbnails[f.id]) { await vm.fullImage(for: $0) }
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
                    ForEach(Array(vm.files.prefix(vm.visibleCount))) { f in
                        cell(f).onAppear {
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

    private func cell(_ f: DriveFile) -> some View {
        Button { vm.selected = f } label: {
            Color.gray.opacity(0.12)
                .aspectRatio(1, contentMode: .fit)          // square tile (no overlap)
                .overlay {
                    if let img = vm.thumbnails[f.id] {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        ProgressView()
                    }
                }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task { await vm.loadThumbnail(for: f) }
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
