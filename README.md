# 🔐 CryptVault (iOS / macOS)

> rclone `crypt` で暗号化した Google Drive バックアップを、iPhone / Mac 上でそのまま閲覧・復号する。

[rclone](https://rclone.org) の `crypt` はクライアントサイド暗号なので、Google Drive 側には
中身もファイル名もスクランブルされた暗号文しか置かれません。CryptVault は Drive に接続し、
**ファイル名を復号して本物のフォルダツリーを表示**し、**タップで中身を復号**します。すべて端末内で
完結し、鍵は一切外に出ません。Google が持つのは暗号文だけです。復号エンジンは
[RcloneCryptKit](https://github.com/masafykun/RcloneCryptKit) を利用しています。

![Platform](https://img.shields.io/badge/platform-iOS%2016%2B%20%7C%20macOS%2013%2B-blue?style=flat-square) ![Swift](https://img.shields.io/badge/Swift-5-orange?style=flat-square) ![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-green?style=flat-square) ![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)

🔗 **復号エンジン: [RcloneCryptKit](https://github.com/masafykun/RcloneCryptKit)**

> **使い方は「自分でビルド（Xcode サイドロード）」です。** App Store には出していません。
> ユーザーの Drive 全体を読む処理は Google の *制限付きスコープ* 審査＋有償の年次 CASA 監査が必要で、
> 個人ツールには見合いません。OSS として各自が自分の OAuth クライアント（testing モード・自分専用）で
> ビルドすれば、これらは一切不要になります。

---

## ✨ 特徴

- **完全クライアントサイド復号** — 鍵（パスワード / ソルト）は端末の Keychain のみに保存。Google には暗号文しか渡さない
- **ファイル名も復号** — 暗号化された名前を復号し、本物のフォルダ構成のまま閲覧できる
- **フォルダ選択ホーム** — 起動時にフォルダ一覧を表示 → タップでそのフォルダだけのグリッドへ。ファイルの多いフォルダに埋もれない
- **写真アプリライクな UI** — サムネイルグリッド → タップで全画面、ピンチ / ダブルタップでズーム・パン
- **動画再生** — mp4 / mov / m4v は AVKit（ハードウェアデコード）、webm / mkv / avi ほかは VLC（MobileVLCKit）
- **並び替え** — 更新日（新しい / 古い順）・名前順。選択は端末に保存（既定：更新日の新しい順）
- **Face ID / パスコードロック** — 起動・復帰時に認証（設定でオフ可）
- **トークン自動更新** — OAuth アクセストークンの期限切れを自動でリフレッシュ
- **スムーズなスクロール** — 復号・ダウンロード・サムネ生成はすべてメインスレッド外、並列数を制限してキャッシュ

---

## 🛠️ 技術スタック

| カテゴリ | 技術 |
|---|---|
| 言語 / UI | Swift 5, SwiftUI |
| 復号 | [RcloneCryptKit](https://github.com/masafykun/RcloneCryptKit)（scrypt / XSalsa20-Poly1305 / AES-256 EME + base32-hex） |
| 動画 | AVKit, MobileVLCKit（[vlckit-spm](https://github.com/tylerjonesio/vlckit-spm)） |
| 認証 | Google OAuth（Authorization Code + PKCE）, ASWebAuthenticationSession |
| ストレージ / API | Google Drive v3 REST, Keychain, LocalAuthentication |
| ビルド | XcodeGen, Swift Package Manager |

---

## 📁 ディレクトリ構成

```
project.yml                         # XcodeGen 設定（RcloneCryptKit / VLCKit を SPM で参照）
Sources/
  App/CryptVaultApp.swift           # エントリポイント・App Lock 制御
  Auth/AppLock.swift                # Face ID / パスコードロック
  Concurrency/AsyncSemaphore.swift  # サムネ生成の並列数制限
  Drive/
    DriveAuth.swift                 # Google OAuth（PKCE）＋トークンリフレッシュ
    DriveClient.swift               # Drive v3 REST（一覧・walk・ダウンロード・ページネーション）
    DriveModels.swift               # DriveFile / フォルダ / 並び順の定義
  Store/KeychainStore.swift         # 鍵・トークンの Keychain 保管
  Video/VLCPlayerView.swift         # MobileVLCKit プレーヤー（SwiftUI ホスト）
  ViewModel/BackupViewModel.swift   # 一覧取得・名前/中身復号・サムネ・並び替え
  Views/
    ContentView.swift               # フォルダ一覧 → グリッドのナビゲーション
    SettingsView.swift              # ⚙️ 設定（鍵・クライアントID・フォルダ名・ロック）
    ImageDetailView.swift           # 画像の全画面ビューア（ズーム・パン）
    VideoViewer.swift               # AVKit 動画ビューア
    VLCVideoViewer.swift            # VLC 動画ビューア
```

---

## 🚀 セットアップ

```bash
# 1. XcodeGen を用意（初回のみ）
brew install xcodegen

# 2. SwiftPM が bare リポジトリを拒否する場合のワークアラウンド
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

# 3. Xcode プロジェクトを生成して開く
cd CryptVault
xcodegen generate
open CryptVault.xcodeproj   # スキームを選んでビルド＆実行
```

- **iOS**：スキーム `CryptVault`（シミュレータ or 実機）
- **macOS**：スキーム `CryptVaultMac`（ネイティブ SwiftUI アプリ。Catalyst ではなく macOS
  ターゲット。VLCKit の macOS スライスで webm/mkv/avi 再生・サムネも動作）

依存（RcloneCryptKit / VLCKit）は Swift Package Manager が GitHub から自動解決します。
iOS と macOS でソース（`Sources/`）を共有し、差分は `#if os(macOS)` で分岐しています。

---

## 🔑 初回設定（アプリ内 ⚙️）

コード編集は不要。すべてアプリの **⚙️ 設定** で完結します。

1. **自分の Google OAuth クライアントを作る**（初回のみ・約10分）。Google Cloud Console で
   プロジェクトを用意 → **Drive API** を有効化 → **Google Auth Platform** の **Clients** で
   **OAuth クライアント ID → iOS** を作成（bundle id は `com.masafy.cryptvault` に合わせる）。
   **Audience** はアプリを *Testing* のままにして自分の Google アカウントを **テストユーザー** に追加、
   **Data access** で `drive.readonly` スコープを追加。
2. **アプリを設定** — 起動 → ⚙️ で以下を入力：
   - **OAuth クライアント ID**（`…apps.googleusercontent.com`）— iOS のリダイレクトスキーム
     （逆順クライアント ID）はアプリが自動生成するので Info.plist の編集は不要
   - rclone crypt の **パスワード / ソルト**（`password` / `password2`）
   - crypt リモートを含む **Drive フォルダ名**（既定：`comfyui-backup`）
3. **接続** → Google 同意 → **更新** → ファイルをタップして復号・表示。

> 各ユーザーが「自分の OAuth クライアント（Testing モード・自分専用）」と「自分の crypt 鍵」を
> 使う設計です。だから Google の制限付きスコープ審査なしに OSS として成立します。
> このリポジトリに共有の / 埋め込みのクライアント ID や鍵は含まれていません。

---

## 🔒 セキュリティ設計

- crypt のパスワード / ソルト、OAuth トークンは端末の **Keychain** にのみ保存
- 復号は端末内で実行。Google には**暗号文しか**渡らない
- 復号した動画は一時ファイルに書き出して再生し、起動・更新時に破棄
- 起動・復帰時に **Face ID / パスコード** でロック（設定でオフ可）

---

## ライセンス

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

このプロジェクトは **MIT ライセンス** のもとで公開しています。詳細は [LICENSE](LICENSE) を参照してください。
rclone および Google とは無関係の非公式プロジェクトです。

© 2026 Masato Suzuki ([masafykun](https://github.com/masafykun))
