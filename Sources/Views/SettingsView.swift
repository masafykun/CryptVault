import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var salt = ""
    @AppStorage("rootFolderName") private var rootFolderName = "comfyui-backup"
    private let secrets = SecretsStore()

    var body: some View {
        NavigationStack {
            Form {
                Section("復号キー（rclone crypt）") {
                    SecureField("CRYPT_PASSWORD", text: $password)
                    SecureField("CRYPT_SALT (password2)", text: $salt)
                }
                Section("Driveのバックアップフォルダ") {
                    TextField("フォルダ名", text: $rootFolderName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
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
