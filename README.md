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

> 別端末やサーバーと共有したい場合は、⚙️設定に表示される暗号キーを控えて、各端末で同じ値を入力してください。

---

## 🔒 セキュリティ設計

- 暗号鍵（パスワード / ソルト）は端末の **Keychain** にのみ保存
- 暗号化・復号は端末内で実行。WebDAV には**暗号文しか**渡さない
- 復号した動画は一時ファイルに書き出して再生し、起動・更新時に破棄
- 起動・復帰時に **Face ID / Touch ID / パスコード** でロック（設定でオフ可）

---

## ライセンス

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

**MIT ライセンス**で公開しています。詳細は [LICENSE](LICENSE) を参照してください。
rclone および各ストレージ事業者とは無関係の非公式プロジェクトです。

© 2026 Masato Suzuki ([masafykun](https://github.com/masafykun))
