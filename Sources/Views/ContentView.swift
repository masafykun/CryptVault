import SwiftUI
import UIKit

struct ImageBox: Identifiable { let id = UUID(); let image: UIImage }

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
                .sheet(item: previewBinding) { box in ImageDetailView(image: box.image) }
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
            List(vm.files) { f in
                Button { Task { await vm.open(f) } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.displayName)
                        if !f.decryptedDir.isEmpty {
                            Text(f.decryptedDir).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
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

    private var previewBinding: Binding<ImageBox?> {
        Binding(get: { vm.previewImage.map { ImageBox(image: $0) } },
                set: { if $0 == nil { vm.previewImage = nil } })
    }
}
