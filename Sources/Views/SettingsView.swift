import SwiftUI

/// Settings for one vault (profile) plus the shared Google account and vault management.
struct SettingsView: View {
    let profileID: String
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var folder = ""
    @State private var password = ""
    @State private var salt = ""
    @State private var authStatus = ""
    @AppStorage("googleClientID") private var googleClientID = ""
    @AppStorage("appLockEnabled") private var appLockEnabled = true

    private let secrets = SecretsStore()

    var body: some View {
        NavigationStack {
            Form {
                Section("このVault") {
                    TextField("名前（タブに表示）", text: $name)
                    TextField("Drive のフォルダ名", text: $folder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("CRYPT_PASSWORD", text: $password)
                    SecureField("CRYPT_SALT (password2)", text: $salt)
                    Text("同じファイルを別端末で読むには、各端末で同じフォルダ名・同じ鍵にしてください。ComfyUI バックアップとは別のフォルダを使ってください（同期で上書きされます）。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Google アカウント（全 Vault 共通）") {
                    TextField("OAuth クライアントID", text: $googleClientID)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                    Button {
                        Task { await connectGoogle() }
                    } label: {
                        Label("Google に接続 / 再接続（読み書き権限）",
                              systemImage: "person.crop.circle.badge.checkmark")
                    }
                    if !authStatus.isEmpty {
                        Text(authStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("アップロード・削除には書き込み権限が必要です。読み取り専用で接続済みなら一度再接続してください。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("セキュリティ") {
                    Toggle("起動時に認証（Face ID / パスコード）", isOn: $appLockEnabled)
                }

                Section("Vault 管理") {
                    ForEach(store.profiles) { p in
                        HStack(spacing: 10) {
                            Image(systemName: p.id == profileID ? "checkmark.circle.fill" : "lock.doc")
                                .foregroundStyle(p.id == profileID ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name)
                                Text(p.folderName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.profiles.count > 1 {
                                Button(role: .destructive) { store.remove(p) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    Button {
                        store.add(name: "新しい Vault", folderName: "")
                    } label: {
                        Label("新しい Vault を追加（タブが増えます）", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(); dismiss() }
                }
            }
            .onAppear(perform: load)
            .onChange(of: profileID) { _ in load() }
        }
    }

    private func load() {
        if let p = store.profiles.first(where: { $0.id == profileID }) {
            name = p.name; folder = p.folderName
        }
        password = secrets.cryptPassword(profile: profileID)
        salt = secrets.cryptSalt(profile: profileID)
    }

    private func save() {
        if var p = store.profiles.first(where: { $0.id == profileID }) {
            p.name = name.isEmpty ? p.name : name
            p.folderName = folder
            store.update(p)
        }
        secrets.saveCryptKeys(profile: profileID, password: password, salt: salt)
    }

    private func connectGoogle() async {
        do {
            let t = try await DriveAuth().authorize()
            secrets.saveToken(t)
            authStatus = "接続しました。各 Vault で「更新」してください"
        } catch DriveAuthError.noClientID {
            authStatus = "クライアントID を入力してください"
        } catch {
            authStatus = "認証失敗: \(error.localizedDescription)"
        }
    }
}
