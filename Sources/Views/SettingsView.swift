import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: BackupViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var salt = ""
    @AppStorage("googleClientID") private var googleClientID = ""
    @AppStorage("rootFolderName") private var rootFolderName = "comfyui-backup"
    @AppStorage("appLockEnabled") private var appLockEnabled = true
    private let secrets = SecretsStore()

    var body: some View {
        NavigationStack {
            Form {
                Section("セキュリティ") {
                    Toggle("起動時に認証（Face ID / パスコード）", isOn: $appLockEnabled)
                }
                Section("Google アカウント") {
                    Button {
                        Task { await vm.connect() }
                        dismiss()
                    } label: {
                        Label(vm.isConnected ? "Google に再接続（読み書き権限を許可）" : "Google に接続",
                              systemImage: "person.crop.circle.badge.checkmark")
                    }
                    Text("アップロード・削除には書き込み権限が必要です。読み取り専用で接続済みの場合は、一度再接続してください。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Google OAuth クライアントID") {
                    TextField("xxxx.apps.googleusercontent.com", text: $googleClientID)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                }
                Section("復号キー（rclone crypt）") {
                    SecureField("CRYPT_PASSWORD", text: $password)
                    SecureField("CRYPT_SALT (password2)", text: $salt)
                }
                Section("Driveのバックアップフォルダ") {
                    TextField("フォルダ名", text: $rootFolderName)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                Section {
                    Text("入力した鍵はこの端末のKeychainにのみ保存され、画像の復号にだけ使われます。Googleには暗号文しか渡りません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { secrets.saveCryptKeys(password: password, salt: salt); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear { password = secrets.cryptPassword; salt = secrets.cryptSalt }
        }
    }
}
