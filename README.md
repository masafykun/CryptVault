# 🔐 CryptVault (iOS / macOS)

> 写真・動画・書類を「あなたの鍵で」暗号化して守る、プライバシー第一のファイル金庫。

CryptVault はファイルを端末内で暗号化して保管する Vault アプリです。暗号方式は
[rclone](https://rclone.org) の `crypt` 互換（scrypt 鍵導出 ＋ XSalsa20‑Poly1305 ＋ AES‑256 EME）。
鍵は端末の Keychain にのみ保存され、外部に出ません。任意で WebDAV（Hetzner Storage Box・NAS・
Nextcloud など、**あなた自身のサーバー**）を設定すると、**暗号化したままの**ファイルだけを同期できます。
暗号エンジンは [RcloneCryptKit](https://github.com/masafykun/RcloneCryptKit) を利用しています。

![Platform](https://img.shields.io/badge/platform-iOS%2016%2B%20%7C%20macOS%2013%2B-blue?style=flat-square) ![Swift](https://img.shields.io/badge/Swift-5-orange?style=flat-square) ![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-green?style=flat-square) ![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)

🔗 **暗号エンジン: [RcloneCryptKit](https://github.com/masafykun/RcloneCryptKit)**

---

## ✨ 特徴

- **アカウント不要・即利用** — 起動するとローカルVaultが自動作成され、鍵も自動生成。設定ゼロで暗号化保管が始められる
- **端末内で完結する暗号化** — 鍵（パスワード / ソルト）は端末の Keychain のみに保存。平文も鍵も外に出さない
- **自分のサーバーに“暗号化したまま”同期（任意）** — WebDAV に対応。同じ鍵を使えば複数端末で同じVaultを読める
- **写真アプリライクな UI** — フォルダ一覧 → サムネイルグリッド → タップで全画面、ピンチ / ダブルタップでズーム
- **サムネイルサイズ変更** — 小 / 中 / 大 / 特大
- **動画再生** — mp4 / mov / m4v は AVKit（ハードウェアデコード）、webm / mkv / avi ほかは VLC（VLCKit）
- **写真ライブラリから追加** — 選択した写真・動画をその場で暗号化して取り込み
- **並び替え** — 更新日（新しい / 古い順）・名前順（端末に保存）
- **Face ID / Touch ID / パスコードロック** — 起動・復帰時に認証（設定でオフ可）
- **スムーズなスクロール** — 復号・入出力・サムネ生成はメインスレッド外、並列数制限＋キャッシュ

---

## 🛠️ 技術スタック

| カテゴリ | 技術 |
|---|---|
| 言語 / UI | Swift 5, SwiftUI（iOS / macOS でソース共有、`#if os(macOS)` で分岐） |
| 暗号 | [RcloneCryptKit](https://github.com/masafykun/RcloneCryptKit)（scrypt / XSalsa20-Poly1305 / AES-256 EME + base32-hex） |
| ストレージ | ローカル（Application Support、暗号化）／ WebDAV（PROPFIND/GET/PUT/MKCOL/DELETE, Basic 認証） |
| 動画 | AVKit, VLCKit（[vlckit-spm](https://github.com/tylerjonesio/vlckit-spm)） |
| セキュリティ | Keychain, LocalAuthentication |
| ビルド | XcodeGen, Swift Package Manager |

---

## 📁 ディレクトリ構成

```
project.yml                         # XcodeGen 設定（RcloneCryptKit / VLCKit を SPM で参照）
Sources/
  App/CryptVaultApp.swift           # エントリポイント・App Lock 制御
  Auth/AppLock.swift                # Face ID / Touch ID / パスコードロック
  Backend/
    Storage.swift                   # バックエンド抽象化（local / webdav）＋ LocalStore
    WebDAVClient.swift              # WebDAV クライアント（PROPFIND ほか）
  Profiles/Profile.swift            # Vault（プロファイル）＝ バックエンド＋フォルダ＋鍵
  Store/KeychainStore.swift         # 鍵・接続情報の Keychain 保管
  Video/…                           # VLCKit プレーヤー / サムネイル
  ViewModel/BackupViewModel.swift   # 一覧・名前/中身復号・サムネ・並び替え・暗号化アップロード
  Views/…                           # フォルダ一覧・グリッド・設定・ビューア
  Debug/Screenshots.swift           # DEBUG 専用のスクショ用シード（Release では除外）
```

---

## 🚀 ビルド

```bash
# 1. XcodeGen（初回のみ）
brew install xcodegen

# 2. SwiftPM が bare リポジトリを拒否する環境向けワークアラウンド
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

# 3. プロジェクト生成
cd CryptVault
xcodegen generate
open CryptVault.xcodeproj
```

- **iOS**：スキーム `CryptVault`
- **macOS**：スキーム `CryptVaultMac`（ネイティブ SwiftUI アプリ。Mac App Store 向けに App Sandbox 有効）

依存（RcloneCryptKit / VLCKit）は Swift Package Manager が自動解決します。

---

## 📱 使い方

1. 起動すると「マイVault」が自動作成されます（ローカル保存・鍵は自動生成）。
2. 右上の **＋** → 「写真から」/「ファイルから」で追加 → その場で暗号化して保存。
3. フォルダをタップ → サムネイルをタップで全画面表示。
4. **⚙️ 設定** で、保存先を「この端末（ローカル）」または「WebDAV」に切り替え。
   同じ鍵・同じフォルダにすれば、別端末やサーバーで同じVaultを読めます。

> 別端末やサーバーと共有したい場合は、⚙️設定 →「鍵を表示・コピー（要認証）」で暗号キーを控えて、各端末で同じ値を入力してください。

---

## 🔒 セキュリティ設計

- 暗号鍵（パスワード / ソルト）は端末の **Keychain** にのみ保存
  - `WhenUnlocked / ThisDeviceOnly`：端末ロック解除中のみ読出し可・**バックアップ経由でも端末外に出ない**
  - macOS は**データ保護Keychain**（ログインキーチェーンではなくアプリ専用領域）
  - 書き込みは update-in-place ＋ 結果検証（失敗しても既存の鍵は消えない）
  - ⚠️ 機種変更・復元では鍵は引き継がれません。**⚙️設定の「鍵を表示」で必ず控えてください**（鍵を失うと誰にも復号できません）
- 暗号化・復号は端末内で実行。WebDAV には**暗号文しか**渡さない
  - 接続は https のみ・Basic認証は**同一オリジンのリダイレクトにしか**追従しない
- 復号した動画の一時ファイルは最強のファイル保護クラスで書き出し、**バックグラウンド移行・ロック・起動・更新時に破棄**
- 起動・復帰時に **Face ID / Touch ID / パスコード** でロック（設定でオフ可）
  - ロック時は導出済み鍵・サムネイルキャッシュ・復号済み一時ファイルを**メモリ/ディスクから破棄**
  - アプリスイッチャーのスナップショットにも中身が写らないよう、非アクティブ時はカバー表示
  - パスコード未設定の端末ではロックを掛けられないため、認証なしで開きます

### 既知の制約（rclone crypt フォーマット互換に由来）

rclone 本体と同じ暗号フォーマットを使うため、フォーマット固有の性質もそのまま引き継ぎます：

- **ブロック境界での切り詰めは検出不能** — 各64KiBブロックは個別に認証されますが、ファイル全体の長さは認証されないため、ちょうどブロック境界で切り詰められた暗号文は「短いファイル」として正常に復号されます
- **ファイル名の暗号化は決定的** — 同じ鍵・同じ名前は常に同じ暗号名になるため、重複ファイル名やフォルダ構造の形はサーバー管理者に漏れます
- **ファイルサイズはほぼそのまま漏れます**（パディングなし）

これらが脅威になる運用（ホスティング先を信頼できない等）では、コンテナ形式の暗号化（Cryptomator等）も検討してください。

---

## ライセンス

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

**MIT ライセンス**で公開しています。詳細は [LICENSE](LICENSE) を参照してください。
rclone および各ストレージ事業者とは無関係の非公式プロジェクトです。

© 2026 Masato Suzuki ([masafykun](https://github.com/masafykun))
