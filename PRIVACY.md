# CryptVault — Privacy Policy / プライバシーポリシー

_Last updated: 2026-07-01_

## 日本語

CryptVault（以下「本アプリ」）は、あなたのプライバシーを最優先に設計されています。

### 収集する情報
本アプリは、**個人情報を一切収集・送信・追跡しません**。開発者や第三者にデータが送られることはありません。アナリティクス、広告SDK、トラッキングは組み込まれていません。

### データの保存場所
- **ローカルVault**: ファイルは端末内にのみ、暗号化された状態で保存されます（rclone crypt 互換：scrypt 鍵導出 ＋ XSalsa20‑Poly1305）。
- **WebDAV Vault（任意）**: あなたが自分で設定したサーバー（例：Hetzner Storage Box、NAS、Nextcloud 等）にのみ、**暗号化済みのファイル**がアップロードされます。平文のファイルや暗号鍵がサーバーに送られることはありません。
- **暗号鍵・接続情報**: 端末の Keychain に保存され、端末外へ送信されません。

### 生体認証（Face ID / Touch ID）
起動時ロックのためだけに使用します。認証は OS 内で完結し、生体データがアプリや開発者に渡ることはありません。

### 写真ライブラリ
「写真から追加」を選んだときのみ、あなたが選択した写真・動画を読み取り、暗号化して保存します。ライブラリ全体へのアクセスや送信は行いません。

### 第三者サーバーについて
WebDAV 接続先はあなたが選んだサーバーです。そのサーバー事業者のプライバシー慣行は各社のポリシーに従います。本アプリはファイルを常に**暗号化してから**送信します。

### お問い合わせ
masafy.masato@gmail.com

---

## English

CryptVault ("the app") is designed with your privacy first.

### Information we collect
The app **does not collect, transmit, or track any personal information**. No data is ever sent to the developer or any third party. There are no analytics, advertising SDKs, or trackers.

### Where your data lives
- **Local vault**: Files are stored only on your device, encrypted at rest (rclone‑crypt compatible: scrypt key derivation + XSalsa20‑Poly1305).
- **WebDAV vault (optional)**: Only **already‑encrypted** files are uploaded to a server that you configure yourself (e.g. Hetzner Storage Box, a NAS, Nextcloud). Plaintext files and your encryption keys never leave the device.
- **Encryption keys & credentials**: Stored in the device Keychain and never transmitted off‑device.

### Biometrics (Face ID / Touch ID)
Used solely to unlock the app at launch. Authentication happens entirely within the OS; biometric data is never exposed to the app or the developer.

### Photo library
Only the photos/videos you explicitly pick via "Add from Photos" are read, encrypted, and stored. The app does not access or transmit your whole library.

### Third‑party servers
Any WebDAV destination is a server you choose; that provider's privacy practices are governed by their own policy. The app always encrypts files **before** sending them.

### Contact
masafy.masato@gmail.com
