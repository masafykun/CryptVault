import SwiftUI
import LocalAuthentication

/// Settings for one vault (profile): backend (local / WebDAV), folder, crypt keys,
/// plus security, key backup, and vault management.
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
    @State private var pendingDelete: Profile?      // vault awaiting delete confirmation
    @State private var showKeyReveal = false        // key backup sheet (after local auth)
    @State private var revealError = ""
    @State private var showSaveError = false
    @AppStorage("appLockEnabled") private var appLockEnabled = true

    private let secrets = SecretsStore()

    var body: some View {
        NavigationStack {
            Form {
                Section("このVault") {
                    TextField("名前（タブに表示）", text: $name)
                    Picker("保存先", selection: $kind) {
                        ForEach(BackendKind.selectable) { Text($0.label).tag($0) }
                    }
                    TextField(folderPlaceholder, text: $folder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("暗号キー（CRYPT_PASSWORD）", text: $password)
                    SecureField("暗号キー2（CRYPT_SALT）", text: $salt)
                    Text(kind == .local
                         ? "ローカルVaultは端末内に暗号化して保存します。鍵は自動生成されます。別端末やサーバで同じファイルを読むには「鍵を表示」で控えて、同じ値を入力してください。"
                         : "別端末で同じファイルを読むには、各端末で同じ保存先・フォルダ・鍵にしてください。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("鍵のバックアップ") {
                    Button {
                        revealKeys()
                    } label: {
                        Label("鍵を表示・コピー（要認証）", systemImage: "key.fill")
                    }
                    if !revealError.isEmpty {
                        Text(revealError).font(.caption).foregroundStyle(.red)
                    }
                    Text("鍵はこの端末のKeychainだけに保存され、機種変更やバックアップ復元では引き継がれません。紛失・故障に備えて、鍵を安全な場所（パスワードマネージャ等）に必ず控えてください。鍵を失うとファイルは誰にも復号できません。")
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
                        Text("HetznerはStorage Boxで WebDAV と External Reachability を有効化してください。接続は https のみ対応です。")
                            .font(.caption).foregroundStyle(.secondary)
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
                                Button(role: .destructive) { pendingDelete = p } label: {
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
                    Button("保存") {
                        if save() { dismiss() } else { showSaveError = true }
                    }
                }
            }
            .onAppear(perform: load)
            .onChange(of: profileID) { _ in load() }
            .confirmationDialog("このVaultを削除しますか？",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible,
                                presenting: pendingDelete) { p in
                Button("「\(p.name)」を鍵ごと削除", role: .destructive) { store.remove(p) }
                Button("キャンセル", role: .cancel) {}
            } message: { p in
                Text(p.kind == .local
                     ? "このVaultの暗号鍵が端末から削除されます。鍵を控えていない場合、中のファイルは二度と復号できません（暗号化ファイル本体は端末に残ります）。"
                     : "このVaultの暗号鍵と接続情報が端末から削除されます。鍵を控えていない場合、サーバ上の暗号化ファイルは二度と復号できません。")
            }
            .alert("保存に失敗しました", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Keychainへの書き込みに失敗しました。もう一度お試しください。")
            }
            .sheet(isPresented: $showKeyReveal) {
                KeyRevealView(password: secrets.cryptPassword(profile: profileID),
                              salt: secrets.cryptSalt(profile: profileID))
            }
        }
    }

    private var folderPlaceholder: String {
        switch kind {
        case .local:  return "フォルダ名（この端末内）例: vault"
        case .webdav: return "フォルダ（パス）例: secure-vault"
        case .googleDrive: return "Drive のフォルダ名"
        }
    }

    /// Gate the key-reveal sheet behind local authentication (Face ID / Touch ID / passcode).
    /// Devices with no passcode can't authenticate at all — same fail-open policy as the app lock.
    private func revealKeys() {
        revealError = ""
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "パスコードを入力"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            showKeyReveal = true
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "暗号キーを表示します") { ok, _ in
            Task { @MainActor in
                if ok { showKeyReveal = true } else { revealError = "認証できませんでした" }
            }
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

    /// Persist the form. Returns false if a Keychain write failed (the caller keeps the sheet
    /// open so the user's input isn't silently dropped).
    private func save() -> Bool {
        if var p = store.profiles.first(where: { $0.id == profileID }) {
            p.name = name.isEmpty ? p.name : name
            p.folderName = folder
            p.kind = kind
            p.webdavURL = Self.normalizeWebDAVURL(webdavURL)
            store.update(p)
        }
        let keysOK = secrets.saveCryptKeys(profile: profileID, password: password, salt: salt)
        let davOK = secrets.saveWebDAV(profile: profileID,
                                       user: webdavUser.trimmingCharacters(in: .whitespaces),
                                       pass: webdavPass)
        return keysOK && davOK
    }

    /// Normalize the WebDAV base URL: trim, add https:// when the scheme is missing, and upgrade
    /// http:// to https:// (ATS blocks cleartext anyway — Basic auth must never go out in plain).
    static func normalizeWebDAVURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }
        if s.lowercased().hasPrefix("http://") {
            s = "https://" + s.dropFirst("http://".count)
        } else if !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        return s
    }
}

/// Shows the vault's crypt keys for backup, after local authentication. Copy uses a local-only,
/// auto-expiring pasteboard entry on iOS.
struct KeyRevealView: View {
    let password: String
    let salt: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("暗号キー（CRYPT_PASSWORD）") {
                    keyRow(password, id: "password")
                }
                Section("暗号キー2（CRYPT_SALT）") {
                    keyRow(salt.isEmpty ? "（未設定 — rcloneのデフォルトソルト）" : salt,
                           id: "salt", copyValue: salt)
                }
                Section {
                    Text("この2つの値をパスワードマネージャ等の安全な場所に控えてください。同じ値を入力すれば、別の端末やrclone本体からも同じVaultを読めます。鍵を失うとファイルは誰にも復号できません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("鍵のバックアップ")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }

    @ViewBuilder
    private func keyRow(_ display: String, id: String, copyValue: String? = nil) -> some View {
        let value = copyValue ?? display
        HStack {
            Text(display)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            if !value.isEmpty {
                Button {
                    Clipboard.copySensitive(value)
                    copied = id
                } label: {
                    Image(systemName: copied == id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
