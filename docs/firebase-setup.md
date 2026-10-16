# Firebase, Google sign-in and push notifications

Firebase project: **Serafim** — id `serafim-chat-42421`
Console: https://console.firebase.google.com/project/serafim-chat-42421

Sign-in itself stays with **Supabase**. Google is only an identity provider:
the app gets a Google ID token and trades it to Supabase for a session
(`POST /auth/v1/token?grant_type=id_token`). Firebase Auth is not used.
Firebase is used for **FCM** (push) and as the home of the Google OAuth clients.

## Already done

- Firebase project created; Android and iOS apps (`com.example.serafim`)
  registered; debug SHA-1 and SHA-256 added.
- `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`,
  `lib/firebase_options.dart` generated.
- App: Google button on landing/login/sign-up; FCM token registration; banner
  for pushes while the app is open; tap a notification to open the chat;
  Settings → Notifications switches.
- Backend: `POST/DELETE /devices`, FCM v1 sender, push on new messages when the
  recipient is offline (or online but never acknowledges delivery).

## You need to do these (console steps)

### 1. Enable Google as a sign-in provider (creates the OAuth clients)
Firebase console → **Authentication** → *Get started* → **Sign-in method** →
**Google** → Enable → pick a support email → Save.

This auto-creates a **Web client** and an **Android client** (for the SHA-1
already registered).

### 2. Get the Web client id and secret
Open the Web SDK configuration on the Google provider card (or Google Cloud
console → *APIs & Services* → *Credentials* → "Web client (auto created by
Google Service)"). Copy the **Web client ID** and **Client secret**.

### 3. Put the id in the app
In `.env` (gitignored):

    GOOGLE_WEB_CLIENT_ID=<the web client id>

Then fully restart the app (`flutter run --dart-define-from-file=.env`).
Refresh the config files so they include the new OAuth clients:

    firebase apps:sdkconfig ANDROID 1:38214413467:android:51bb077add2a1e9fddaa3e \
        --project serafim-chat-42421 --out android/app/google-services.json
    firebase apps:sdkconfig IOS 1:38214413467:ios:afb14ebd15f39b8cddaa3e \
        --project serafim-chat-42421 --out ios/Runner/GoogleService-Info.plist

### 4. Turn on Google in Supabase
Supabase dashboard → **Authentication** → **Providers** → **Google** → Enable.
- **Client IDs**: the Web client id (add the Android/iOS client ids too,
  comma-separated, if you like).
- **Client secret**: the secret from step 2 (this is the only place it goes).
- iOS only: tick **Skip nonce checks**.

### 5. Backend: run the SQL, add the service-account key
1. Run `sql/003_follows_replies_privacy.sql` and `sql/004_push_devices.sql`
   (skip any you already ran).
2. Firebase console → **Project settings** → **Service accounts** →
   **Generate new private key**. On your host (Render) set:
   - `FIREBASE_CREDENTIALS_JSON` = the whole JSON file contents
   - `FIREBASE_PROJECT_ID` = `serafim-chat-42421`
   Never commit this file. Without it, push is simply off and chat works as before.
3. Redeploy.

### 6. Before release
- Add your **release** keystore SHA-1/SHA-256 to the Android app (Project
  settings → Your apps), or Google sign-in fails in release builds:
  `firebase apps:android:sha:create <appId> <sha> --project serafim-chat-42421`
- The package name is still `com.example.serafim`; change it before publishing
  (then re-register the app and re-download the config files).
- Add the `INTERNET` permission to `android/app/src/main/AndroidManifest.xml`
  (only debug/profile builds have it today).

### iOS (needs a Mac)
- Xcode → Runner target → add the **Push Notifications** capability and
  **Background Modes → Remote notifications**.
- Add `GoogleService-Info.plist` to the Runner target in Xcode.
- Firebase console → Project settings → **Cloud Messaging** → upload an
  **APNs authentication key** (Apple Developer account).
- For Google sign-in add the reversed client id (`REVERSED_CLIENT_ID` from the
  plist) as a URL scheme in `Info.plist`, and set `GOOGLE_IOS_CLIENT_ID`.

## Testing it
- Google: tap *Continue with Google* on a device/emulator with a Google account.
- Push: sign in on phone A, **close the app**, send a message from phone B —
  a notification should arrive. Check backend logs for `serafim.push` on errors.
