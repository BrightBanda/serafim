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
- **Tag format.** `v<version>+<code>`, e.g. `v1.2.0+5`, with exactly one
  `.apk` attached. The in-app checker relies on it.

## Publishing a release

1. Bump `version:` in `pubspec.yaml`, e.g. `1.1.0+2` → `1.2.0+3`.
2. Write the release notes (what's new) in a file, e.g. `notes.md`.
3. Run `tool/release.sh notes.md`. It:
   - builds the signed release APK (`flutter build apk --release`, using
     `.env` for the build settings),
   - refuses to go on if the APK is signed with the debug key,
   - prints the version, size, SHA-256 and the download URL,
   - creates the GitHub release with the APK attached if the GitHub CLI
     (`gh`) is installed and logged in; otherwise it prints the steps to do it
     on github.com.
4. In the app, signed in as an admin, open the **SERAFIM** chat → **Announce
   an app update** → **Fill from the latest GitHub release**. Check the
   details (GitHub supplies the SHA-256; if it's missing, tap **Compute
   SHA-256**), write or adjust "What's new", decide whether it is **Required**,
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

## One-time setup after the package rename

The application id changed from `com.example.serafim` to
`com.binaryforge.serafim`. Until this is done, **Android builds fail**
(google-services can't find the package):

1. Firebase console → Project settings → **Add app** → Android, package
   `com.binaryforge.serafim`.
2. Add the release certificate fingerprints:
   - SHA-1 `80:C7:C4:41:22:74:76:8D:4C:8B:B7:C4:17:4C:22:A8:DD:D3:3A:08`
   - SHA-256 `C4:89:08:61:84:83:73:66:55:04:90:91:95:12:A7:83:D6:DF:90:2C:EE:C2:8A:9E:D2:E1:14:8A:8A:84:F8:09`
   - plus your debug key's (`keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`)
     if you want Google sign-in in debug builds.
3. Download the new `google-services.json` into `android/app/` (replacing
   the old one).
4. Run `flutterfire configure` (or re-download the Android options) so
   `lib/firebase_options.dart` has the new Android app id.
5. Google sign-in: the new Android OAuth client is created when you add the
   SHA-1. The Web client id (`GOOGLE_WEB_CLIENT_ID`) stays the same.

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
