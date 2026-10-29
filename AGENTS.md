# Serafim Agent Guide

Read this before exploring or changing the app. It is a map and a set of verified conventions, not a replacement for checking the specific code and tests involved in a change. Keep it current when major architecture or commands change.

## Project At A Glance

Serafim is a Flutter client for chat and social features. The app uses Dart `^3.12.2`, Flutter, Riverpod 3, Dio, Isar Community, Supabase Auth/Storage, a FastAPI backend, and Firebase Cloud Messaging. Main app code is under `lib/src/`; focused Flutter tests are under `test/`.

## Start And Configuration

- `lib/main.dart` initializes Flutter, reads `SharedPreferences`, opens Isar before the first frame, applies the saved theme, then runs `SerafimApp` inside a Riverpod `ProviderScope`.
- The root app is a `MaterialApp`; mandatory update handling wraps `AuthGate`. `AuthGate` chooses landing/sign-in, onboarding, or `MainScreen` from auth/profile state.
- Runtime configuration is compile-time `--dart-define` data, not a bundled `.env` file. Copy `.env.example` to the gitignored `.env`, fill only client-safe values, and run with `--dart-define-from-file=.env`.
- Required config: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `API_BASE_URL`. Google sign-in also uses `GOOGLE_WEB_CLIENT_ID`; `GOOGLE_IOS_CLIENT_ID` is optional and platform-specific. See `lib/src/core/config/app_config.dart` and `docs/firebase-setup.md`.
- Never put Supabase `sb_secret_` / `service_role` keys, OAuth client secrets, or Firebase service-account private keys in the app, `.env.example`, logs, or commits. The publishable key is client-visible and constrained by database policies.
- Backend addresses depend on where the app runs: Android emulator cannot use host `localhost` (use `10.0.2.2`); physical devices need a reachable LAN or deployed address.

## Source Map

- `lib/src/core/`: configuration, platform behavior, networking primitives, errors, and feature flags.
- `lib/src/data/models/`: API and persisted value models.
- `lib/src/data/domain/`: Isar collections and local domain records, including chat messages and rooms.
- `lib/src/data/local/`: Isar access and local cache/persistence.
- `lib/src/data/services/`: API, auth, storage, media, backup, websocket, and feature service implementations.
- `lib/src/providers/`: Riverpod composition, service wiring, and feature state providers.
- `lib/src/presentation/view/`: pages/screens and UI composition.
- `lib/src/presentation/viewmodel/`: UI-facing state and behavior, notably auth, chat, and navigation.
- `lib/src/utils/`: shared UI components, chat widgets, themes, image/media helpers, and other presentation utilities.
- `test/support/`: reusable test fakes and support code. Tests are organized by behavior/feature, for example `test/auth_interceptor_test.dart`, `test/local_first_data_test.dart`, and `test/chat_room_id_test.dart`.
- `docs/`: setup and feature-specific implementation notes. `RELEASING.md` covers release steps; `docs/firebase-setup.md` covers Google sign-in and push setup.

## Architecture And Data Flow

- Riverpod is the dependency and state-management layer. Providers in `providers/` build services and expose feature state; view models/notifiers own UI-facing operations. Prefer the existing provider and service boundaries over networking directly from widgets.
- `network_providers.dart` deliberately separates clients: `supabaseDioProvider` calls GoTrue without the app auth interceptor; `apiDioProvider` is authenticated and uses `AuthInterceptor`; `storageDioProvider` is authenticated for Supabase Storage. Preserve this distinction to avoid refresh recursion or incorrect authorization.
- Supabase owns sign-in/session issuance. Google Sign-In obtains an identity token which is exchanged with Supabase; Firebase Auth is not the app's auth system. Firebase is initialized for messaging/push.
- Chat is local-first. Isar is opened before rendering; local message and room records support immediate chat-list/message reads, while services and websocket/provider flows synchronize remote activity. Avoid designs that require a successful network response before showing already-saved local data.
- `IsarService` owns local message/room persistence. If an Isar collection schema changes, regenerate generated code with `dart run build_runner build --delete-conflicting-outputs`, and add/update migration coverage where needed. Do not reorder persisted enum values without checking compatibility.
- Navigation uses Flutter `Navigator` / `MaterialPageRoute`; there is no app-wide declarative router to extend. Follow the local route/push-return-value patterns.

## UI And Behavior Conventions

- Use the existing theme system in `lib/src/utils/themes/` (`AppColors`, `AppTextStyles`) and shared components such as `AppTopBar`, `SerafimButton`, and existing chat widgets. Match nearby screens rather than introducing a second design system.
- Route user-facing failures through `humanError(error)` from `lib/src/core/errors/human_error.dart`; do not display raw exception strings.
- Check `lib/src/core/config/feature_flags.dart` before exposing or changing gated functionality. The flags have deployment and account-safety context; do not flip them casually.
- Keep changes localized to the owning feature and add/update tests beside its existing coverage. Preserve unrelated work already present in the working tree.

## Tests And Validation

Run commands from the repository root:

```sh
flutter pub get
flutter analyze
flutter test
```

Run a focused test while iterating:

```sh
flutter test test/<feature>_test.dart
```

If a test or app startup requires the compile-time configuration, pass `--dart-define-from-file=.env` to the relevant Flutter command. Never print `.env` contents. For Isar schema changes, run the generator command above, then analyze and run the focused tests plus the full suite when practical.

Test patterns in this repo include `ProviderContainer` overrides, fake services, mock `SharedPreferences`, Flutter widget tests, and fake network adapters. Reuse `test/support/` and neighboring tests instead of introducing live backend dependencies. The repository has no backend source; backend behavior should be treated as an API contract unless a separately available backend repo is explicitly in scope.

## Working Notes

- Check `git status --short` before editing. Existing local changes belong to the user; do not revert or overwrite them.
- Prefer targeted inspection of the owning provider/service/view-model and its tests. Avoid scanning generated `build/` output.
- Do not format the entire Dart tree. Format only files touched, using the project's Dart formatter.
- Update this guide only when the facts it records are verified to have changed.
