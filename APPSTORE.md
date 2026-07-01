# CryptVault — App Store 申請メモ / Submission Kit

このファイルは App Store Connect に貼り付ける文言と、審査で詰まらないための設定メモです。
（機密値は一切含めません。クライアントID・鍵・サーバ情報はここに書かない）

---

## 1. 基本情報

| 項目 | 値 |
|---|---|
| App 名 (Name, ≤30) | **CryptVault** |
| Bundle ID (iOS) | `com.masafy.cryptvault` |
| Bundle ID (Mac) | `com.masafy.cryptvault.mac` |
| Team ID | （自分の Developer Team ID。公開リポジトリには書かない） |
| SKU | `cryptvault-ios-001` / `cryptvault-mac-001` |
| プライマリカテゴリ | ユーティリティ / Utilities |
| セカンダリカテゴリ | 仕事効率化 / Productivity |
| 年齢制限 | 4+ |
| 価格 | 無料（Free）※将来 In‑App/有料化は別途 |
| 対応 | iPhone / iPad / Mac（Designed for Mac、ネイティブ AppKit ビルド） |
| バージョン | 1.0 (build 1) |
| 著作権 | © 2026 Masato Suzuki |

### URL（要ホスティング）
- Privacy Policy URL: `https://cryptvault.1qaz.jp/privacy`（`PRIVACY.md` を配置。GitHub Pages でも可）
- Support URL: `https://cryptvault.1qaz.jp/`（または GitHub リポジトリ）
- Marketing URL（任意）: 同上

---

## 2. サブタイトル / Subtitle（≤30 chars）
- JA: `端末内で完結する暗号化ファイル金庫`
- EN: `Your private encrypted vault`

## 3. プロモーションテキスト / Promotional Text（≤170 chars）
- JA: `写真・動画・書類を端末内で暗号化して保管。アカウント不要、クラウドにもあなたのWebDAVサーバーにも“暗号化したまま”。鍵はあなたの端末だけ。`
- EN: `Encrypt photos, videos and documents on‑device. No account needed. Sync to your own WebDAV server — always encrypted. Your keys never leave your device.`

## 4. キーワード / Keywords（≤100 chars, カンマ区切り）
- JA: `暗号化,金庫,ファイル,写真,動画,プライバシー,セキュリティ,バックアップ,WebDAV,rclone,ロック,秘密,保管,クラウド`
- EN: `encrypt,vault,secure,files,photos,video,privacy,security,backup,webdav,rclone,lock,secret,cloud`

## 5. 説明 / Description

### JA
CryptVault は、写真・動画・書類を「あなたの鍵で」暗号化して守る、プライバシー第一のファイル金庫です。

■ アカウント不要ですぐ使える
インストールしてすぐ、端末内に暗号化Vaultを作成。写真アプリやファイルから追加すると、その場で暗号化して保存します。クラウドも登録も不要です。

■ 端末内で完結する暗号化
ファイルは rclone crypt 互換の強力な暗号（scrypt 鍵導出 ＋ XSalsa20‑Poly1305）で暗号化されます。暗号鍵は端末の Keychain に保存され、外部に送信されません。

■ 自分のサーバーにも“暗号化したまま”
必要なら WebDAV（Hetzner Storage Box、NAS、Nextcloud など）を設定して、暗号化済みファイルだけをアップロード。平文や鍵がサーバーに渡ることはありません。同じ鍵を使えば、複数の端末で同じVaultを読めます。

■ 写真も動画もそのまま再生
サムネイル一覧、フルスクリーン表示、動画再生（mp4/mov に加え、webm/mkv/avi なども）に対応。

■ 起動時ロック
Face ID / Touch ID / パスコードで、アプリ全体をロックできます。

あなたのデータは、あなたのものだけ。CryptVault は、それを技術で保証します。

### EN
CryptVault is a privacy‑first file vault that encrypts your photos, videos and documents with keys only you hold.

■ No account, ready in seconds
Create an on‑device encrypted vault the moment you launch. Add from Photos or Files and it's encrypted on the spot. No cloud, no sign‑up.

■ Encryption that stays on your device
Files are protected with strong, rclone‑crypt‑compatible encryption (scrypt key derivation + XSalsa20‑Poly1305). Keys live in your device Keychain and never leave it.

■ Sync to your own server — still encrypted
Optionally point CryptVault at a WebDAV server (Hetzner Storage Box, a NAS, Nextcloud, …). Only already‑encrypted files are uploaded; plaintext and keys never reach the server. Use the same key to read one vault across devices.

■ View photos and play videos
Thumbnail grid, full‑screen viewer, and video playback (mp4/mov plus webm/mkv/avi and more).

■ Launch lock
Lock the whole app behind Face ID / Touch ID / passcode.

Your data is yours alone — and CryptVault enforces it with cryptography.

---

## 6. 審査メモ / App Review Notes（App Store Connect の "Notes" に貼る）

```
No account or server is required to fully test this app.

1. Launch the app. A ready-to-use on-device vault ("マイVault") is created automatically.
2. Tap the + button (top right) → "写真から" (From Photos) → pick a few photos.
   The app encrypts them on-device and shows them in the vault.
3. Tap a folder → tap a thumbnail to view full screen.
4. Settings tab: the storage backend can be "この端末（ローカル / Local)" or "WebDAV".
   WebDAV is optional and only for users who own a WebDAV server; it is NOT required
   to review the app — Local mode exercises all functionality (encrypt, store, list,
   view, delete) with zero setup.

Encryption: files are encrypted with standard published algorithms (scrypt + XSalsa20-
Poly1305), rclone-crypt compatible. Keys are generated on-device and stored in Keychain.
No user data is transmitted to the developer.
```

---

## 7. 輸出コンプライアンス / Export Compliance（重要）

本アプリは標準的な暗号（scrypt / XSalsa20‑Poly1305 / AES）でユーザーのファイルを暗号化します。
Info.plist に `ITSAppUsesNonExemptEncryption` は**あえて記載していません**。提出時に App Store Connect が質問するので、以下の方針で回答してください（独自暗号ではなく公開標準アルゴリズムのマスマーケット製品なので、通常 CCATS 不要の免除に該当）:

1. 「暗号を使用していますか？」→ **はい / Yes**
2. 「エクスポート規制の免除に該当しますか？」→ **はい / Yes**
   （理由: 一般公開向けマスマーケット製品で、標準の公開暗号アルゴリズムを使用。専用/独自の暗号ではない）
3. 年次の自己分類レポート（BIS/ENC 宛メール）が必要になる場合があります。詳細は
   https://help.apple.com/app-store-connect/#/dev88f5c7bf9 を確認。

※ もし毎回聞かれるのが煩わしければ、確定後に Info.plist へ
`ITSAppUsesNonExemptEncryption` を追加（上記回答に一致する値）して固定できます。

---

## 8. スクリーンショット / Screenshots

`screenshots/` に格納済み（シミュレータ実機キャプチャ、実際のアプリUI）:

| ファイル | デバイス | サイズ | 用途 |
|---|---|---|---|
| ios_01_folders.png | iPhone 17 Pro Max (6.9") | 1320×2868 | フォルダ一覧 |
| ios_02_grid.png | 〃 | 1320×2868 | サムネイルグリッド |
| ios_03_viewer.png | 〃 | 1320×2868 | フルスクリーン表示 |
| ios_04_settings.png | 〃 | 1320×2868 | 設定（ローカル/WebDAV） |
| ipad_01_folders.png | iPad Pro 13" (M5) | 2064×2752 | フォルダ一覧 |
| ipad_02_grid.png | 〃 | 2064×2752 | グリッド |
| ipad_03_viewer.png | 〃 | 2064×2752 | フルスクリーン |

- **iPhone 6.9"** と **iPad 13"** は App Store の必須サイズを満たします。
- **Mac 版のスクショは未取得**（このMacBookでのGUI自動撮影は許可ダイアログが多発するため中断）。
  Mac mini 等で `CryptVaultMac` を起動し、ウインドウを 1280×800pt にして
  `screencapture -R<x>,<y>,1280,800` で撮ると 2560×1600（App Store 許容サイズ）になります。

---

## 9. 提出前チェックリスト

- [ ] Apple Developer 有料メンバーシップ（自分の Team ID で署名）
- [ ] App Store Connect で App レコード作成（iOS / Mac）
- [ ] Bundle ID 登録・署名（Automatic 署名）
- [ ] アプリアイコン（`Sources/Assets.xcassets/AppIcon` に同梱済み）
- [ ] プライバシーポリシーURLを公開（`PRIVACY.md`）
- [ ] App Privacy「データを収集しない / Data Not Collected」を選択
- [ ] 輸出コンプライアンス（§7 の回答）
- [ ] スクショ（iPhone 6.9" / iPad 13"）アップロード、Mac 版は Mac mini で撮って追加
- [ ] Archive → Distribute（Xcode）で iOS / Mac をそれぞれアップロード
