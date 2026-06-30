# CryptVault (iOS)

A small SwiftUI app that browses and decrypts an **[rclone](https://rclone.org) `crypt`
Google Drive backup** directly on iPhone — a reference app for
[RcloneCryptKit](https://github.com/masafykun/RcloneCryptKit).

Because rclone `crypt` encrypts client-side, the Google Drive app itself only ever shows
encrypted blobs with scrambled names. CryptVault talks to Drive, decrypts filenames so you can
browse the real tree, and decrypts file contents on tap — all on-device. The keys never leave
the phone and Google only ever holds ciphertext.

> **Use it by building it yourself (Xcode sideload) with your own Google OAuth client.**
> It is not on the App Store: reading a user's whole Drive needs Google's *restricted-scope*
> verification + an annual paid CASA audit, which is not worthwhile for a personal tool. As an
> open-source app each person uses their own OAuth client (in "testing" mode, just for
> themselves), which avoids all of that.

## How it works
1. **RcloneCryptKit** derives keys with scrypt and decrypts content (XSalsa20-Poly1305) and
   filenames (AES-256 EME + base32-hex). See that repo for the format details and verification.
2. **DriveClient** lists/downloads files via the Drive v3 REST API.
3. **DriveAuth** does Google OAuth (Authorization Code + PKCE) with `ASWebAuthenticationSession`.
4. Crypt password/salt and the OAuth token live only in the device **Keychain**.

## Build
```bash
brew install xcodegen          # once
cd CryptVault
# SwiftPM may need this if git refuses bare repos:
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all
xcodegen generate
open CryptVault.xcodeproj       # build & run on a simulator or your device
```
The `RcloneCryptKit` dependency is resolved from GitHub by Swift Package Manager.

## Setup before live use
1. **Google OAuth client** — in Google Cloud Console: create a project, enable the **Drive API**,
   then create an **OAuth client ID (iOS)** with bundle id `com.masafy.cryptvault`. Paste the
   client id into `DriveAuth.clientID`. (Add yourself as a test user; the app requests the
   read-only Drive scope.)
2. **Crypt keys** — run the app → ⚙️ → enter your rclone crypt `password` / `password2` and the
   name of the Drive folder that holds the crypt remote (default `comfyui-backup`).
3. Tap **接続 (Connect)** → Google consent → **更新 (Refresh)**, then tap a file to decrypt + view.

## Layout
```
project.yml                    # XcodeGen project (depends on RcloneCryptKit via SPM URL)
Sources/
  App/CryptVaultApp.swift
  Drive/{DriveAuth,DriveClient,DriveModels}.swift
  Store/KeychainStore.swift
  ViewModel/BackupViewModel.swift
  Views/{ContentView,SettingsView,ImageDetailView}.swift
```

## Status / roadmap
Skeleton: builds and runs; decrypt core verified against a real backup. Next:
Drive `files.list` pagination, a thumbnail grid with lazy decrypt + cache, access-token refresh,
and richer error handling.

## License
MIT © Masato Suzuki. See [LICENSE](LICENSE). Not affiliated with rclone or Google.
