# Releasing Serafim (Android, sideloaded)

Updates are published as **public GitHub releases** of
`BrightBanda/serafim` and announced in the official SERAFIM chat. The app
downloads the APK from the release, checks its SHA-256, and opens Android's
installer. People confirm the install (Android always asks), and the first
time they allow "Install unknown apps" for Serafim.

## Rules that must never break

- **Same key.** Every release must be signed with the keystore in
  `android/key.properties`. An APK signed with any other key can't be
  installed over the existing app. Never commit the keystore or
  `key.properties`, and keep a backup of both somewhere safe: losing them
  means nobody can update without uninstalling.
- **Higher version code.** The number after `+` in `pubspec.yaml`
  (`version: 1.2.0+5`) must go up with every release.
- **Same application id.** `com.binaryforge.serafim`. Changing it makes a
  different app.
- **Tag format.** `v<version>+<code>`, e.g. `v1.2.0+5`. The in-app checker
  relies on it.
- **Keep the symbols.** Releases are obfuscated (smaller), so a stack trace
  from one is unreadable without `release-symbols/<version>/`, which
  `tool/release.sh` writes. It is not committed: back it up with the
  keystore. Read a trace with
  `flutter symbolize -i trace.txt -d release-symbols/<version>/app.android-arm64.symbols`.
- **One APK per release**, `serafim-<version>.apk`, for both 64-bit and
  32-bit ARM phones (32-bit covers many itel and Android Go models). Attach
  only that one `.apk`: app versions before 1.0.2 take the first `.apk` on
  the release. (The app can also handle one APK per CPU type, named
  `…-arm64-v8a.apk` / `…-armeabi-v7a.apk`, if downloads ever need to be
  smaller.)

## Publishing a release

1. Bump `version:` in `pubspec.yaml`, e.g. `1.1.0+2` → `1.2.0+3`.
2. Write the release notes (what's new) in `release-notes/<version>.md`,
   e.g. `release-notes/1.2.0.md`.
3. Run `tool/release.sh release-notes/1.2.0.md`. It:
   - builds the signed release APK for 64-bit and 32-bit ARM phones
     (`flutter build apk --release --target-platform android-arm,android-arm64`,
     using `.env` for the build settings),
   - refuses to go on if the APK is signed with the debug key,
   - prints the version, size, SHA-256 and download URL,
   - creates the GitHub release with the APK attached if the GitHub CLI
     (`gh`) is installed and logged in; otherwise it prints the steps to do it
     on github.com.
4. In the app, signed in as an admin, open the **SERAFIM** chat → **Announce
   an app update** → **Fill from the latest GitHub release**. Check the details (GitHub supplies the checksums; if one is
   missing, tap **Compute SHA-256**), write or adjust "What's new", decide whether it is **Required**,
   and **Post update**.

Everyone sees the update card in the official chat; phones with the app
closed get a push. Apps also notice a new GitHub release on their own (checked
at most every 6 hours), even before it is announced.

### Required updates

Turn on **Required update** only for breaking changes (for example an API
change older versions can't handle). Every version below a required release
is blocked at launch, even before sign-in, until it updates. The blocking
screen always offers *Try again* and a link to download from GitHub in the
browser, so a broken release can't lock anyone out completely. Fixing a bad
release means publishing a newer one.

## If the in-app update fails

- **"Signed with a different key"**: the release wasn't built with the usual
  keystore. Rebuild with the right key and publish again.
- **Checksum mismatch**: the announced SHA-256 doesn't match the file. Delete
  the announcement (long-press it in the official chat) and post it again.
- Anyone can always install by downloading the APK from the release page.

## The package rename (done)

The application id changed from `com.example.serafim` to
`com.binaryforge.serafim`. In Firebase (`serafim-chat-42421`) the new Android
app "Serafim (com.binaryforge)" is registered with the release key (SHA-1
`80:C7:C4:41:…:3A:08`, SHA-256 `C4:89:08:61:…:F8:09`) and the local debug key,
`android/app/google-services.json` is the new config and
`lib/firebase_options.dart` points at the new app. The old
`com.example.serafim` app is still registered so existing installs keep
working until people move over.

If you build on another computer, add that machine's debug SHA-1 in the
Firebase console for Google sign-in to work in its debug builds.

Everyone on the old package uninstalls it once and installs the new APK from
the release page; from then on, updates happen in the app.

## Google Play Protect warnings

Play Protect warns about apps it doesn't know, especially ones installed
outside the Play Store that can install other apps. What helps:

- A real application id (done: `com.binaryforge.serafim`; `com.example.*` is
  treated as a placeholder).
- Always the same release key, and only release builds handed out (never the
  debug build).
- Submitting the APK to Google for review via the Play Protect appeals form
  (search "Play Protect appeals"), and registering as a developer for Android
  developer verification when it applies to your region.

None of these remove Android's own install confirmation, which always
appears for sideloaded apps.
