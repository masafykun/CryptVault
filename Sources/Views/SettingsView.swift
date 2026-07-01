import SwiftUI

/// Settings for one vault (profile): backend (Google Drive / WebDAV), folder, crypt keys,
/// plus the shared Google account, security, and vault management.
struct SettingsView: View {
    let profileID: String
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: BackendKind = .googleDrive
    @State private var folder = ""
    @State private var password = ""
    @State private var salt = ""
    @State private var webdavURL = ""
    @State private var webdavUser = ""
    @State private var webdavPass = ""
    @State private var authStatus = ""
    @AppStorage("googleClientID") private var googleClientID = ""
    @AppStorage("appLockEnabled") private var appLockEnabled = true

    private let secrets = SecretsStore()

    var body: some View {
        NavigationStack {
            Form {
                Section("このVault") {
                    TextField("名前（タブに表示）", text: $name)
                    Picker("保存先", selection: $kind) {
                        ForEach(BackendKind.allCases) { Text($0.label).tag($0) }
                    }
                    TextField(kind == .webdav ? "フォルダ（パス）例: secure-vault" : "Drive のフォルダ名", text: $folder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("CRYPT_PASSWORD", text: $password)
                    SecureField("CRYPT_SALT (password2)", text: $salt)
                    Text("別端末で同じファイルを読むには、各端末で同じ保存先・フォルダ・鍵にしてください。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if kind == .webdav {
                    Section("WebDAV 接続（Hetzner / NAS 等）") {
                        TextField("URL 例: https://u123.your-storagebox.de", text: $webdavURL)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                        TextField("ユーザー名", text: $webdavUser)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        SecureField("パスワード", text: $webdavPass)
                        Text("HetznerはStorage Boxで WebDAV と External Reachability を有効化してください。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if kind == .googleDrive {
                    Section("Google アカウント（全 Drive Vault 共通）") {
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
                    }
                }

                Section("セキュリティ") {
                    Toggle("起動時に認証（Face ID / パスコード）", isOn: $appLockEnabled)
                }

                Section("Vault 管理") {
                    ForEach(store.profiles) { p in
                        HStack(spacing: 10) {
                            Image(systemName: p.id == profileID ? "checkmark.circle.fill"
                                  : (p.kind == .webdav ? "externaldrive" : "lock.doc"))
                                .foregroundStyle(p.id == profileID ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name)
                                Text("\(p.kind.label) ・ \(p.folderName)")
                                    .font(.caption).foregroundStyle(.secondary)
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
            name = p.name; folder = p.folderName; kind = p.kind; webdavURL = p.webdavURL
        }
        password = secrets.cryptPassword(profile: profileID)
        salt = secrets.cryptSalt(profile: profileID)
        webdavUser = secrets.webdavUser(profile: profileID)
        webdavPass = secrets.webdavPass(profile: profileID)
    }

    private func save() {
        if var p = store.profiles.first(where: { $0.id == profileID }) {
            p.name = name.isEmpty ? p.name : name
            p.folderName = folder
            p.kind = kind
            p.webdavURL = webdavURL.trimmingCharacters(in: .whitespacesAndNewlines)
            store.update(p)
        }
        secrets.saveCryptKeys(profile: profileID, password: password, salt: salt)
        secrets.saveWebDAV(profile: profileID, user: webdavUser.trimmingCharacters(in: .whitespaces), pass: webdavPass)
    }

    private func connectGoogle() async {
        do {
            let t = try await DriveAuth().authorize()
            secrets.saveToken(t)
            authStatus = t.canWrite
                ? "✅ 接続OK（書き込み権限あり）"
                : "⚠️ 読み取りのみ。数分待って、Googleのアプリ連携を解除→再接続してください"
        } catch DriveAuthError.noClientID {
            authStatus = "クライアントID を入力してください"
        } catch {
            authStatus = "認証失敗: \(error.localizedDescription)"
        }
    }
}
