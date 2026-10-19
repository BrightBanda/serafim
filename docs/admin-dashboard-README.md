# Serafim Admin Dashboard — Build Brief

You are building the **Serafim admin dashboard**: a Flutter app for **web (desktop browsers) first**, and **Android** second. Serafim administrators use it to:

- see how the app is doing (users, sign-ups, messages, groups, push, app versions),
- **post announcements** to everyone through the official SERAFIM chat, including **app-update announcements**,
- **see users**, look at one user's account, and **suspend, unsuspend or delete** them,
- see **group chats** and remove a group,
- see **Circles** (communities). Circles are **not built yet**. You build only the navigation entry and a placeholder that a later feature slots into (§10.7),
- read an **audit log** of what admins did.

Unlike some earlier dashboards, **most of the admin API does not exist yet**. The backend has exactly one admin feature today: posting and deleting announcements. So the job has two parts:

- **Part A: backend.** Add an `/admin/*` router to the FastAPI backend, plus a migration and tests (§7).
- **Part B: dashboard.** Build the Flutter client on top of it (§8–§12).

Do Part A first, with tests passing, before you write dashboard screens that depend on it. Read this whole brief before writing code. Section 14 lists the acceptance criteria.

---

## 1. Context: what already exists

Serafim is a chat and social app: direct messages over a WebSocket, friends and follows, group chats, voice notes, stickers/GIFs, link previews, chat backgrounds, push notifications, and an official **SERAFIM** chat that every account sees. Android builds are sideloaded from GitHub releases and update themselves from inside the app.

| Piece | Where | Notes |
|---|---|---|
| Serafim app (Flutter) | `FlutterProjects/serafim/` (this repo) | **Do not modify** unless §7.7 lists the change. Read it for the design language (`lib/src/utils/themes/`, `lib/src/utils/serafim_*.dart`), the models (`lib/src/data/models/`) and how it talks to the backend (`lib/src/data/services/`, `lib/src/core/network/`). |
| Backend (FastAPI + async SQLAlchemy + Postgres) | `HINOKAMI/Backend/Serafim-Backend/` (its own git repo) | Routers in `app/api/`, models in `app/models/`, schemas in `app/schemas/`, hand-written SQL migrations in `sql/NNN_*.sql`, pytest suite in `tests/` (runs on SQLite, no Postgres needed). |
| Auth | Supabase (GoTrue) | Accounts live in Supabase `auth.users`. The backend's `users` table shares the same UUID and has a foreign key to `auth.users(id) ON DELETE CASCADE`. |
| Database | Supabase Postgres | Same project. Tables are created on startup (`app/main.py`), and column changes are applied by hand from `sql/`. |
| Profile pictures | Supabase Storage, public bucket `avatars`, path `<user id>/…` | See `supabase/storage_avatars.sql`. Chat images are never stored on the server. They stay on the phones. |
| Push | Firebase Cloud Messaging, project `serafim-chat-42421` | Server-side only. **The dashboard does not need Firebase at all.** |
| Deployed API | Render (`serafim-backend.onrender.com`), reached through the Cloudflare Worker **`https://serafim-api.binaryforge.workers.dev`** | Some Malawian networks block Render's addresses, so clients use the Worker (`Backend/Serafim-Backend/cloudflare/`). Use the Worker URL as the default. The first request after an idle period may take about 30 s while Render wakes up. |
| Releases | Public GitHub releases of `BrightBanda/serafim` | See `RELEASING.md`. Tag format `v<version>+<code>`, e.g. `v1.0.2+3`. |

### Who is an admin

An admin is a user whose UUID is in the backend env var **`ADMIN_USER_IDS`** (comma-separated). The UUID is the Supabase auth user id, which the app shows as "UID". The backend decides this on **every request** (`is_admin()` in `app/api/official.py`). The dashboard never decides it, never caches it as truth, and never hides a feature behind a client-side flag alone.

---

## 2. Scope

### Build

1. **Sign-in** with Google (and email/password for accounts that have one) through Supabase, plus the server-side admin check (§6).
2. **Overview**: headline numbers and a 30-day sign-up chart.
3. **Users**: a searchable, filterable, paginated list. A detail page. Suspend, unsuspend, delete.
4. **Announcements**: the official chat history; post a text announcement; post an **app-update** announcement; delete an announcement.
5. **Groups**: list and search; detail (members and roles, rules); delete.
6. **Circles**: nav entry and placeholder only (§10.7).
7. **Audit log**: what every admin did, newest first.
8. **Settings**: who is signed in, their UID (copyable), API target, server health, theme, sign out.

One codebase, with a responsive layout for desktop web, tablets and phones (§9).

### Do not

- **Do not read private messages.** No endpoint or screen shows the content of direct or group messages. Counts are fine; content is not. This is a hard rule.
- Do not change the Serafim app, except for anything §7.7 lists.
- Do not change existing backend wire contracts (`/official/*`, `/auth/*`, `/profile/*`, social, groups, WebSocket events). Add new routes under `/admin`. The only intentional change to an existing route is closing the `/auth/users` hole (§7.6).
- Do not put the Supabase **secret** key (`sb_secret_…`) or the legacy `service_role` key in the dashboard. It goes in the backend env only. The dashboard ships only the **publishable** key.
- Do not add features the API cannot back, such as editing someone's profile, reading reports, bulk actions, or emailing users. List them as follow-ups (§13).
- Do not use mock data in a production build. Mocks belong in tests only.

---

## 3. Project setup

Create a **new, separate Flutter project** next to the app, with its own git repo:

```
FlutterProjects/
├── serafim/                     ← the app (this repo)
└── serafim_admin_dashboard/     ← you create this
HINOKAMI/Backend/Serafim-Backend ← the API (Part A changes go here)
```

```bash
cd FlutterProjects
flutter create --org com.binaryforge --project-name serafim_admin \
  --platforms web,android serafim_admin_dashboard
```

- **Dart SDK**: use the same `environment.sdk` constraint as the app's `pubspec.yaml` (`^3.12.2`).
- **Config** is passed at build time with `--dart-define-from-file=.env`, the same way the app does it (`lib/src/core/config/app_config.dart`). Add `.env` to `.gitignore` and commit a `.env.example`:

```
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
API_BASE_URL=https://serafim-api.binaryforge.workers.dev
GOOGLE_WEB_CLIENT_ID=<the web OAuth client id the app uses>
UPDATE_REPO=BrightBanda/serafim
```

  Copy `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` and `GOOGLE_WEB_CLIENT_ID` from the app's `.env`. Don't print them in logs or commit them.
- **CORS.** The backend allows browser origins listed in `CORS_ORIGINS`, plus any `http://localhost:<port>` / `http://127.0.0.1:<port>` (so `flutter run -d chrome` works locally). Allowed methods are **`GET POST PUT DELETE OPTIONS`**, and **not `PATCH`**, so design the admin API without PATCH. Allowed headers are `Authorization` and `Content-Type`. When the dashboard is deployed (e.g. Cloudflare Pages), add its origin to `CORS_ORIGINS` on Render.
- **Supabase redirect URLs.** For web Google sign-in, add the dashboard origins (local and deployed) under Supabase → Authentication → URL Configuration → Redirect URLs.

### Running the backend locally

```bash
cd HINOKAMI/Backend/Serafim-Backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# .env needs DATABASE_URL, SUPABASE_URL, ADMIN_USER_IDS=<your uid>,
# and (new, Part A) SUPABASE_SECRET_KEY for suspend/delete.
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
pytest            # must stay green
```

Live OpenAPI docs are at `<API_BASE_URL>/docs`. `GET /health` reports database and push status.

---

## 4. Dependencies (dashboard)

Prefer what the app already uses, so conventions match.

| Package | Purpose | Notes |
|---|---|---|
| `flutter_riverpod` (^3) | State | Same as the app. Hand-written `Notifier`/`AsyncNotifier` providers. **No codegen** (`riverpod_generator`, `freezed`, `json_serializable`). Models are hand-written like the app's. |
| `dio` | HTTP | One configured instance (§8.3). |
| `supabase_flutter` | Sign-in and session | See §6 for why the dashboard uses it when the app uses raw GoTrue calls. |
| `google_sign_in` | Google on Android | Same flow as the app (`GoogleAuthService`). On web, use Supabase OAuth redirect instead (§6). |
| `go_router` | Routing and URLs | URL-addressable screens and filters (§10). |
| `google_fonts` | Bangers, Inter, JetBrains Mono | Same as the app. |
| `fl_chart` | Sign-up chart | |
| `intl` | Number and date formatting | |
| `cached_network_image` | Avatars, group photos | Same as the app. |
| `url_launcher` | Open GitHub release pages | |
| `crypto` | SHA-256 of an APK (update form) | Same as the app. |
| `shared_preferences` | Theme, last-used filters | Conveniences only, never data. |
| dev: `flutter_lints`, `mocktail`, `http_mock_adapter` | Tests | |

Don't add other state, DI or model libraries (bloc, get_it, freezed).

---

## 5. Domain primer (what the screens must understand)

- **`users` row vs Supabase account.** Signing in creates a Supabase account. The app then calls `POST /auth/sync`, which upserts the app's `users` row (`id`, `email`, `is_active`, `created_at`). A user without a **profile** has signed in but not finished onboarding (no username yet). Show them as "No profile yet"; don't hide them.
- **Profile** (`app/schemas/profile.py`): `username` (3–20 chars, `^[a-z0-9_]+$`), `display_name` (≤ 30), `bio` (≤ 160), `profile_pic` (public avatar URL), `interests` (list of strings), plus privacy settings: `allow_friend_requests`, `lock_profile` (hides friends/followers/following from others), `group_add_privacy` (`everyone` | `friends` | `nobody`).
- **Relationships**: friendships (request → accepted) and follows (one-way, independent of friendship).
- **Groups**: `name` (≤ 50), optional `photo_url`, `rules` (≤ 2000). Members have roles `owner` | `admin` | `member`. Exactly one owner. Group **admins** are a group-level role and are unrelated to Serafim administrators. Use the words "group admin" and "Serafim admin" in the UI so nobody confuses them.
- **Official SERAFIM chat**: one shared timeline of announcements, stored once and read by everyone, including accounts created later. Posting broadcasts a WebSocket event (`announcement`) to everyone online and sends a push to everyone else. Deleting broadcasts `announcement_deleted`, and the message disappears from every app.
- **App-update announcements** (`kind: "app_update"`): carry version, changelog, APK URL(s), SHA-256 and size. The newest one drives the in-app update card. A **mandatory** one sets `min_version_code`, and every older app version is **blocked at launch until it updates**. That is the most dangerous button in the dashboard (§10.4).
- **Suspended** = `users.is_active = false`. The backend answers every authenticated REST request from that user with `403 "This account has been deactivated."`, and the app treats a 403 as a dead session and signs out (`auth_view_model.dart`, `_sessionIsDead`). Part A extends this to the WebSocket and push (§7.4).

---

## 6. Authentication and the admin gate

### Why `supabase_flutter` here

The app talks to GoTrue with raw Dio calls (`lib/src/data/services/auth_service.dart`) and gets Google ID tokens from `google_sign_in`. That works on phones. In a desktop browser, Google sign-in is far simpler and more reliable as a Supabase **OAuth redirect** (PKCE), and `supabase_flutter` also handles session persistence and token refresh. The tokens are the same Supabase access tokens, so the backend can't tell the difference.

### Flow

1. **Sign-in screen** (no Supabase session):
   - **Continue with Google**:
     - Web: `supabase.auth.signInWithOAuth(OAuthProvider.google, redirectTo: Uri.base.origin)`.
     - Android: `google_sign_in` with `serverClientId = GOOGLE_WEB_CLIENT_ID` → `supabase.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: …)`. This mirrors `GoogleAuthService` + `signInWithGoogleIdToken` in the app.
   - **Email and password** (collapsed under "Sign in with email"). **No sign-up and no password reset UI.** Admins are existing accounts.
2. **Sync, then admin check.** After sign-in, call `POST /auth/sync` (idempotent), then **`GET /admin/me`** (new, §7.3):
   - `200`: admin. Enter the app.
   - `403` with detail "deactivated": the admin's own account is suspended. Show that and sign out.
   - `403` otherwise: the **Not authorized** screen. Show the signed-in email and the **UID with a copy button**, and explain: "Ask the server operator to add this UID to `ADMIN_USER_IDS`." Offer sign-out.
   - `401`: refresh the session once and retry. If it still fails, sign out.
   - Network error or timeout: "Can't reach the server. It may be waking up; the first request can take about 30 seconds." Offer **Retry**.
3. **Router guard.** Auth unknown → splash. No session → `/sign-in`. Session but not admin → `/not-authorized`. Admin → requested route, or `/` by default. Use `refreshListenable` (or watch a small `(loading, status)` record) so the `GoRouter` instance is **not rebuilt** on every auth change.
4. **Any later `403`** from an `/admin/*` call means the person lost admin rights mid-session (their UID was removed from `ADMIN_USER_IDS`). Re-run the admin check and route to `/not-authorized`.
5. **Sign out** calls `supabase.auth.signOut()` and clears every provider.

---

## 7. Part A: backend work (`HINOKAMI/Backend/Serafim-Backend`)

Match the existing code style: one router module per area, Pydantic schemas in `app/schemas/`, small helpers in `app/core/`, docstrings that explain *why*, user-facing `detail` strings written as plain sentences ("Announcement not found."). Identity comes **only** from the verified token (`get_current_user`). Never take an acting user id from the path, query or body.

### 7.1 New settings (`app/core/config.py`)

```python
# Server-only Supabase key (sb_secret_... or the legacy service_role JWT).
# Needed to ban/unban and delete accounts through the GoTrue admin API and to
# remove avatar files. Never shipped to any client.
SUPABASE_SECRET_KEY: str | None = None
```

When it is unset, suspend still works on our side (`is_active`), but the response says the Supabase ban was skipped, and **delete answers `503`** with "Account deletion isn't configured on this server." Never half-delete.

### 7.2 Migration `sql/011_admin.sql` and models

```sql
-- Run once against the deployed database.
ALTER TABLE users ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS suspended_reason TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS suspended_by UUID;

CREATE TABLE IF NOT EXISTS admin_actions (
  id          UUID PRIMARY KEY,
  admin_id    UUID,              -- no FK: the log must outlive accounts
  action      VARCHAR(32) NOT NULL,
  target_type VARCHAR(16) NOT NULL, -- user | group | announcement
  target_id   UUID,
  summary     TEXT NOT NULL,     -- e.g. "Suspended @sam: spam"
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_admin_actions_created_at ON admin_actions (created_at DESC);
CREATE INDEX IF NOT EXISTS ix_admin_actions_target ON admin_actions (target_id);
```

Add the columns to `app/models/user.py`, add `app/models/admin_action.py`, register the new table in **both** `app/main.py` (startup `create_all` list) and `tests/conftest.py` (`TABLES`).

`action` values: `suspend_user`, `unsuspend_user`, `delete_user`, `delete_group`, `post_announcement`, `post_update`, `delete_announcement`. Also log the existing `/official` post and delete routes, so the audit log covers announcements made from the phone too.

### 7.3 The admin router: `app/api/admin.py`, prefix `/admin`

Add a dependency `require_admin` (in `app/api/deps.py` or the router module) that wraps `get_current_user` and reuses `is_admin()` from `app/api/official.py`. Move `is_admin` to `app/core/admin.py` and import it from both places. Otherwise it answers `403 "Only SERAFIM administrators can do that."`.

**Conventions**

- JSON is **snake_case**, like the rest of this API.
- Timestamps are ISO 8601 UTC (`to_iso_utc` in `app/api/ws.py`). Calendar days are `"YYYY-MM-DD"` in UTC.
- List endpoints take `limit` (1–100, default 25) and `offset` (≥ 0), and return `{ "items": [...], "total": int, "limit": int, "offset": int }`.
- Errors are FastAPI's `{"detail": "..."}`. Request validation errors are `{"detail": [{"loc": [...], "msg": "...", "type": "..."}]}`.

**Endpoints**

| Method & path | Purpose | Returns |
|---|---|---|
| `GET /admin/me` | Admin check for the gate | `{ "user_id", "email", "username" \| null, "push_enabled": bool, "push_detail": str, "account_deletion_enabled": bool, "update_repo": str }` |
| `GET /admin/stats` | Overview numbers | `AdminStats` (below) |
| `GET /admin/users` | List users. Query: `q` (matches username, display name or email, case-insensitive substring), `status` = `all`\|`active`\|`suspended` (default `all`), `profile` = `any`\|`yes`\|`no`, `sort` = `newest`\|`oldest`\|`username`, `limit`, `offset` | page of `AdminUserRow` |
| `GET /admin/users/{user_id}` | One user | `AdminUserDetail` |
| `POST /admin/users/{user_id}/suspend` | Body `{ "reason": str }` (1–500 chars, required) | `AdminUserDetail` |
| `POST /admin/users/{user_id}/unsuspend` | | `AdminUserDetail` |
| `DELETE /admin/users/{user_id}?confirm=<username or user id>` | Permanently delete. `confirm` must equal the username (or the id when there is no profile), or `422` | `204` |
| `GET /admin/groups` | Query: `q` (name), `sort` = `newest`\|`members`\|`active`, `limit`, `offset` | page of `AdminGroupRow` |
| `GET /admin/groups/{group_id}` | One group | `AdminGroupDetail` |
| `DELETE /admin/groups/{group_id}?confirm=<group name>` | Delete a group | `204` |
| `GET /admin/audit` | Query: `target_id` (optional), `limit`, `offset` | page of `AdminAction` |

Announcements need **no new routes**. The dashboard uses the existing `/official` routes (§7.5).

**Schemas** (`app/schemas/admin.py`)

```text
AdminStats {
  users: {
    total, active, suspended, with_profile,
    new_7d, new_30d,
    online_now                 // manager.is_user_online over connected sockets
  }
  signups: [{ date: "YYYY-MM-DD", count: int }]   // last 30 UTC days, oldest first, zero-filled
  messages: { last_24h, last_7d, total }           // counts only; direct + group
  groups: { total, created_7d }
  devices: { total, users_with_push }
  push: { enabled: bool, detail: str }             // push.describe_status()
  announcements: { total, last_at: datetime | null }
  app: {
    latest_version_name: str | null,
    latest_version_code: int | null,
    min_version_code: int                          // same logic as GET /app/latest-update
  }
}

AdminUserRow {
  id: uuid
  email: str | null
  username: str | null          // null = no profile yet
  display_name: str | null
  profile_pic: str | null
  is_active: bool
  is_admin: bool                // in ADMIN_USER_IDS
  online: bool
  created_at: datetime
  suspended_at: datetime | null
  suspended_reason: str | null
}

AdminUserDetail = AdminUserRow + {
  profile: ProfileResponse | null        // reuse the existing schema
  counts: { friends, followers, following, groups, messages_sent, devices, pending_friend_requests }
  groups: [{ id, name, role }]           // groups they're in
  suspended_by: { id, username } | null
  recent_actions: [AdminAction]          // last 10 admin actions targeting them
}

AdminGroupRow {
  id, name, photo_url, member_count,
  owner: { id, username, display_name } | null,
  created_at, last_message_at: datetime | null
}

AdminGroupDetail = AdminGroupRow + {
  rules: str | null, rules_updated_at: datetime | null,
  members: [{ user: { id, username, display_name, profile_pic, is_active }, role, joined_at }],
  message_count: int                    // count only — never content
}

AdminAction {
  id, action, target_type, target_id, summary, created_at,
  admin: { id, username } | null
}
```

Keep queries efficient: aggregate counts with `GROUP BY` / subqueries, not one query per row. Avoid N+1 queries in the list endpoints.

### 7.4 Suspend, unsuspend and delete semantics

Put the logic in `app/core/moderation.py` so routes stay thin and tests can call it directly. Talk to Supabase through a small `app/core/supabase_admin.py` (httpx, `apikey: <SUPABASE_SECRET_KEY>`, and `Authorization: Bearer <key>` when it is the legacy JWT). Tests replace it with a fake, the same way they fake FCM. **Check the current Supabase docs** for the exact header rules of `sb_secret_` keys before relying on them.

**Guards (all actions)**

- An admin cannot suspend or delete **themselves** (`409 "You can't do that to your own account."`).
- Nobody can suspend or delete **another Serafim admin** (`409 "Remove them from ADMIN_USER_IDS first."`).
- Unknown id → `404 "User not found."`.

**Suspend**: `POST /admin/users/{id}/suspend`

1. Set `is_active = false`, `suspended_at = now`, `suspended_reason`, `suspended_by = admin`.
2. Ban in Supabase so they can't sign in again or refresh: `PUT {SUPABASE_URL}/auth/v1/admin/users/{id}` with `{"ban_duration": "876000h"}`. If the key is missing or the call fails, still suspend locally and record "Supabase ban skipped: …" in the audit summary. Local suspension is what enforces it.
3. **Close their live WebSocket connections.** Add `ConnectionManager.disconnect_user(user_id, code=4403)` to `app/core/websocket_manager.py`. It closes every socket for that user and drops them.
4. **Fix the WebSocket gap**: `authenticate()` in `app/api/ws.py` only checks the token. It must also load the user and **reject inactive users** (close `4403`). Otherwise a suspended user can reconnect and keep chatting with an unexpired token.
5. **No pushes** to inactive users: filter `User.is_active` in the push fan-out (`app/core/push.py`: messages, group messages, announcements, `notify_user`). Keep their device rows so unsuspending restores push.
6. **Hide them** from `GET /discover` and `GET /users/search`. Leave existing friendships and history alone.
7. **Block direct messages to them.** In `handle_message` (`app/api/ws.py`), once the recipient is resolved and before anything is stored, check `recipient.is_active`. If it is false, send `{"type": "message_rejected", "temp_id": …, "reason": "user_unavailable", "message": "User not available"}` and return. Nothing is stored and no push is sent. Extend `_reject()` with an optional `message` argument; leave the existing reasons unchanged. This check applies only while the suspension lasts, so unsuspending makes messaging work again with nothing else to undo. Group messages are unaffected: they still reach the group, and the suspended member simply doesn't receive them (no socket, no push).
8. Audit: `suspend_user`, summary `Suspended @<username>: <reason>`.

For the suspended person, the app needs no change: its next REST call gets `403`, and it signs out with "Your session has ended." For people messaging them, see §7.7.

**Unsuspend**: clear the four fields, set `is_active = true`, set `ban_duration: "none"` in Supabase, and write an audit row. Idempotent: unsuspending an active user is a `200` no-op with no audit row.

**Delete**: `DELETE /admin/users/{id}?confirm=…`

`503` if `SUPABASE_SECRET_KEY` is missing. Otherwise, in this order:

1. Validate `confirm`.
2. **Write the audit row first** (`delete_user`, summary `Deleted @<username> (<email>)`). The log has no FK, so it survives.
3. **Hand over owned groups.** `groups.owner_id` is `ON DELETE SET NULL` and the owner's `group_members` row cascades away, so a group would be left with no owner. For each group they own, promote the longest-standing group admin, otherwise the longest-standing member, to `owner`. Reuse the transfer logic in `app/api/groups.py`/`app/core/groups.py`. If they were the only member, delete the group.
4. Close their sockets (`disconnect_user`).
5. Delete their avatar files: Storage API `DELETE {SUPABASE_URL}/storage/v1/object/avatars` with `{"prefixes": [...]}` after listing `avatars/<id>/`. Best-effort; log failures.
6. Delete the Supabase account: `DELETE {SUPABASE_URL}/auth/v1/admin/users/{id}`. The FK cascade removes the `users` row and everything hanging off it: profile, messages they sent **and received**, friendships, follows, devices, notifications, media (voice notes), group memberships. `announcements.author_id` becomes `NULL`.
7. Tell affected group members with the existing `group_update` WebSocket event (`_notify` in `app/api/groups.py`) so member lists refresh.

If step 6 fails, answer `502 "Supabase didn't delete the account. Nothing else was removed."`. That is only true if steps 3–5 are safe to have run. Group handover and avatar deletion are acceptable to keep. Make sure **nothing user-visible besides those** happened before step 6.

What deletion **cannot** do: copies of messages already stored on other people's phones (Isar local cache) stay on those phones. The dashboard's confirm dialog says so.

**Delete group**: `DELETE /admin/groups/{id}?confirm=<name>`. Collect member ids, delete the group (messages and memberships cascade), send each member `group_removed` (the app already handles it and removes the chat), and write an audit row.

### 7.5 Announcements: reuse `/official`

| Method & path | Notes |
|---|---|
| `GET /official` | `{ name, username, can_post, latest }`. `can_post` mirrors admin status. |
| `GET /official/announcements?limit=50&before=<iso>` | Newest first. Page back with the oldest `created_at` you have as `before`. `limit` ≤ 200. |
| `POST /official/announcements` | Admin only. Body `{ "content": str, "update"?: AppUpdateIn }`. Returns `201 AnnouncementResponse`. |
| `DELETE /official/announcements/{id}` | Admin only. `204`. |
| `GET /app/latest-update` | Public. `{ latest: AppUpdateOut \| null, min_version_code: int }`. |

```text
AnnouncementResponse { id: uuid, content: str, created_at, kind: "text" | "app_update", update: AppUpdateOut | null }

AppUpdateIn {
  version_name: "1.2.3"                 // ^\d+\.\d+\.\d+$
  version_code: int                     // 1 .. 2_099_999_999; must go up every release
  changelog: str                        // ≤ 4000
  apk_url: str                          // must start https://github.com/<UPDATE_REPO>/releases/download/ and end .apk
  sha256: str                           // 64 hex chars (a "sha256:" prefix is stripped)
  size_bytes: int                       // 1 .. 500 MiB
  mandatory: bool                       // default false
  variants: [{ abi: "arm64-v8a" | "armeabi-v7a" | "x86_64", apk_url, sha256, size_bytes }]  // ≤ 4, unique abi
}
AppUpdateOut = AppUpdateIn + { created_at }
```

Rules: text content is trimmed, ≤ 4000 chars, and may not be empty for a plain announcement. For an update, `content` may be empty; the server writes a fallback sentence for old app versions.

### 7.6 Close the open user list

`GET /auth/users` (`app/api/auth.py`) currently returns **every user with their email to any signed-in account**. The app never calls it (`UserService.getUsers` is unused) and no test covers it. Remove the route, or make it `require_admin`. Removing it is preferred, since `/admin/users` replaces it. Add a test that a normal user can't list users.

### 7.7 App changes

These are the only changes allowed in the Serafim app (`FlutterProjects/serafim`).

**Required: show "User not available".** The app currently handles `message_rejected` in `lib/src/presentation/viewmodel/chat_viewmodel.dart` by marking the message `failed` and only *logging* the reason. Change it so that when `reason == "user_unavailable"`:

- the message is still marked `failed` (as now), and
- the sender sees **"User not available"**. Use the server's `message` field when present, otherwise that text. Show it the way the app shows other transient chat errors (the in-app banner / snackbar pattern in `lib/src/utils/in_app_banner.dart`), only while that chat is open.

Keep it small: no Isar schema change and no new per-message stored field. Other reasons keep today's behaviour. Older app versions without this change just show the message as failed, which is acceptable. Add a test for the new branch.

Optional, and only if asked: delete the unused `UserService.getUsers` from the app.

### 7.8 Backend tests: `tests/test_admin.py`

Use the existing fixtures (`env`, `as_user`, `env.add_user`). Make an admin with `monkeypatch.setattr(settings, "ADMIN_USER_IDS", str(uid))` as `tests/test_app_updates.py` does. Fake `supabase_admin` so no network is touched. Cover at least:

- Every `/admin/*` route answers `403` for a non-admin and `401` without a token.
- User list: search by username, display name and email; status and profile filters; pagination `total`; users without a profile appear.
- Stats: zero-filled 30-day sign-up series; counts are right.
- Suspend: sets the fields; the user then gets `403` on `/auth/me`; their WebSocket auth is rejected; they're absent from discover and search; no push goes to them; audit row written; Supabase ban called. Without a secret key the local suspend still works.
- A direct message to a suspended user gets `message_rejected` with `reason: "user_unavailable"` and `message: "User not available"`; no message row is stored and no push is sent. After unsuspend, the same message goes through. A group message in a group with a suspended member is still stored and delivered to everyone else.
- Can't suspend or delete yourself or another admin; `404` for unknown ids.
- Unsuspend restores everything and is idempotent.
- Delete: wrong `confirm` → `422`; no key → `503`; owned group passes to the right member; sole-member group is deleted; Supabase delete called; audit row survives.
- Group delete: members get `group_removed`; group and messages gone.
- No admin response contains message content (assert on the JSON).
- `/auth/users` is closed.

`pytest` must be fully green, existing tests included.

---

## 8. Part B: dashboard architecture

Feature-first folders, each with `domain` / `data` / `presentation`. Business logic never lives in widgets.

### 8.1 Layers

- **domain/**: plain Dart models and enums, and repository *interfaces*. No Flutter, Dio or JSON.
- **data/**: hand-written DTOs (`fromJson`/`toJson`, the same style as `lib/src/data/models/` in the app) and repository implementations over the shared API client.
- **presentation/**: Riverpod providers and view-models, and widgets. Widgets read state and call view-model methods. Nothing else.

### 8.2 State conventions

- Each list screen has a view-model holding `(filters, page, AsyncValue<Page<T>>)`. Changing a filter resets to page 0 and refetches. Debounce search by 300 ms.
- **No optimistic updates for admin writes.** Wait for the server, then show a toast and invalidate the affected providers (list, detail, stats, audit).
- Disable Riverpod's automatic retry on API providers (`retry: (_, _) => null`) and offer a **Retry** button instead.
- Override every repository in tests. No test touches the network.

### 8.3 Networking (Dio)

`core/network/api_client.dart` owns one `Dio`:

- `baseUrl` = `API_BASE_URL`, `connectTimeout` 15 s, `receiveTimeout` 40 s (covers Render waking up).
- **Auth interceptor**: attaches `Authorization: Bearer <supabase access token>` from `supabase.auth.currentSession`. On `401`, refresh once (`supabase.auth.refreshSession()`, single-flighted) and replay. Never loop. The app's `AuthInterceptor` is the model.
- **Error mapping**: every `DioException` becomes an `ApiException { type, message, statusCode, fieldErrors }`. Port the friendly-message approach from the app's `lib/src/core/network/api_exception.dart` and `lib/src/core/errors/human_error.dart`.

| Status | Type | Message shown |
|---|---|---|
| no response / timeout | `network` | "Can't reach the server. It may be waking up — try again." |
| 401 | `auth` | "Your session expired. Sign in again." |
| 403 | `permission` | the server's `detail`, then re-run the admin check (§6.4) |
| 404 | `notFound` | "Not found — it may have been deleted." |
| 409 | `conflict` | the server's `detail` |
| 422 | `validation` | string `detail`, or the list form mapped to field errors by the last `loc` element (`["body","update","sha256"]` → `sha256`) |
| 502 / 503 | `server` | the server's `detail` (these carry specific explanations, §7.4) |
| other 5xx | `server` | "The server had a problem. Try again." |

### 8.4 Shared core

- `core/config/app_config.dart`: the dart-defines, with a `configurationError` getter like the app's.
- `core/format/`: compact numbers (`1.2k`), relative times ("3 h ago"), dates (`Mon 19 Oct 2026`), byte sizes (`24.1 MB`).
- `core/time/utc.dart`: build and parse `YYYY-MM-DD` UTC days. Show times in the viewer's local zone, with UTC on hover.
- `core/theme/`: the copied palette and text styles (§11).

---

## 9. Responsive layout

| Width | Navigation | Content |
|---|---|---|
| ≥ 1200 | Expanded left sidebar (logo, labels, signed-in admin at the bottom) | Tables; detail pages in two columns |
| 800–1199 | Collapsed navigation rail (icons with tooltips) | Tables with fewer columns |
| < 800 | Bottom nav bar (Overview, Users, Announcements, Groups, More) with Circles, Audit and Settings under **More** | Cards instead of tables; full-screen dialogs; sticky action bar on detail pages |

Every screen must work at 360 px wide with no horizontal page scroll. Destructive buttons are never the default focus.

---

## 10. Routes and screens

| Route | Screen |
|---|---|
| `/sign-in` | Sign in |
| `/not-authorized` | Not an admin |
| `/` | Overview |
| `/users?q=&status=&profile=&sort=&page=` | Users list (filters live in the URL) |
| `/users/:id` | User detail |
| `/announcements` | Official chat history and composer |
| `/announcements/update` | Announce an app update |
| `/groups?q=&sort=&page=` | Groups list |
| `/groups/:id` | Group detail |
| `/circles` | Circles placeholder |
| `/audit?target=&page=` | Audit log |
| `/settings` | Settings |

### 10.1 Sign in / Not authorized

Centered card on `paper`, with the Serafim mark and the **SERAFIM** wordmark in Bangers. The eyebrow above the title, in JetBrains Mono, reads `ADMIN DASHBOARD`. Not authorized shows email and UID (monospace, copy button), the `ADMIN_USER_IDS` explanation, and Sign out.

### 10.2 Overview (`/`)

- Stat tiles: **Users** (total, with "+N this week"), **Active** / **Suspended**, **Online now**, **Messages (24 h)**, **Groups**, **Push devices**.
- Line chart: sign-ups per day for the last 30 days, with a hover tooltip showing the date and count.
- **App version** card: latest announced version and code, `min_version_code`, and whether the newest update is mandatory. Links to the GitHub release.
- **Push** card: enabled or disabled with the server's detail. A rust warning when disabled ("Phones that are closed won't be notified of announcements").
- **Latest announcement** preview with a link to `/announcements`.
- Every tile links to its screen. Each block loads, fails and retries independently.

### 10.3 Users (`/users`, `/users/:id`)

**List**: a search box (username, display name or email), a status segmented control (All / Active / Suspended), a profile filter (Any / Has profile / No profile yet), and a sort menu. Desktop columns: avatar and display name with `@username` under it, email, status badge, joined (relative), and an online dot. A **Serafim admin** badge (the app's `official_badge.dart` look) marks admins. Pagination reads "26–50 of 213". The row's overflow menu holds View, Suspend/Unsuspend and Delete. Delete is disabled with a tooltip for admins and yourself.

**Detail**:
- Header: large avatar (tap to open full size, like `profile_photo_viewer.dart`), display name, `@username`, email, UID (copy), joined date, status badge. When suspended, a rust banner reads "Suspended <when> by @<admin>: <reason>".
- Profile card: bio, interests as chips (the `SerafimChip` look), and privacy settings in plain words ("Friend requests: off", "Profile locked: yes", "Who can add to groups: friends only").
- Counts: friends, followers, following, groups, messages sent, devices, pending requests.
- Groups they're in, with their role. Each links to the group.
- Recent admin actions about them.
- Actions:
  - **Suspend**: a dialog with a required reason (1–500 chars) and a summary of what happens: "They'll be signed out on every device, can't sign back in, won't receive notifications, and won't appear in Discover or search. Anyone who messages them will see 'User not available'. Their messages and friends stay."
  - **Unsuspend**: a simple confirm.
  - **Delete permanently**: a dialog that lists exactly what is removed (§7.4), notes that copies on other people's phones can't be removed, says which groups get a new owner, and asks the admin to **type the username** to enable the rust **Delete** button. When `account_deletion_enabled` is false, the button is disabled with "Account deletion isn't configured on this server."

### 10.4 Announcements (`/announcements`, `/announcements/update`)

**History**: renders the official chat the way the app does (`official_chat_page.dart`): the SERAFIM header with the official badge, then messages newest-at-bottom, with infinite scroll back through `before`. Update announcements render as an **update card** (version, size, changelog, "Required" tag) like `lib/src/utils/update/update_card.dart`. Each message has a **Delete** action with a confirm: "This removes it from everyone's app right away."

**Text composer** (bottom on desktop, a FAB → sheet on mobile):
- Multiline, a counter at **4000**, trimmed, and Post disabled while empty.
- A **preview** pane showing it as a phone would see it. Links become tappable in the app.
- The confirm says "This goes to every Serafim user now, as a push notification to phones that are closed." This can't be scheduled or edited later; delete and repost instead.

**Announce an app update** (`/announcements/update`). This mirrors the app's admin flow (`lib/src/utils/update/update_flow_panel.dart`, `post_update_page.dart`) and `RELEASING.md`:
1. **Fill from the latest GitHub release**: `GET https://api.github.com/repos/<UPDATE_REPO>/releases/latest` with **no credentials**. Parse the tag `v<name>+<code>` (reuse the app's `parseReleaseTag`), and collect `.apk` assets: `browser_download_url`, `size`, and `digest` (`sha256:…`). Assets named `…-<abi>.apk` become variants; the arm64 build (or the only APK) is the top-level `apk_url`. Pre-fill "What's new" from the release body. Ignore drafts and prereleases.
2. Editable fields with the server's validation shown inline: version name, version code, changelog (≤ 4000), APK URL, SHA-256, size, variants.
3. **SHA-256 missing?** Offer **Compute SHA-256**, which downloads the APK and hashes it with `crypto`. In a browser, GitHub download URLs may be blocked by CORS. If the download fails, say so and ask the admin to paste the SHA-256 printed by `tool/release.sh`. Never post without one.
4. **Version code check**: warn, and block posting, if the code is not higher than `GET /app/latest-update` → `latest.version_code`.
5. **Required update** toggle, off by default. When it is turned on, show a rust panel: "Every app below version code N will be **blocked at launch, even before sign-in,** until it updates. Use this only for breaking changes. A broken required release can only be fixed by publishing a newer one." Posting a required update needs a second confirm where the admin types the version name.
6. Optional custom text. If it is empty, the server writes the fallback.
7. Post → `POST /official/announcements` with `update`. Show success with a link back to history.

### 10.5 Groups (`/groups`, `/groups/:id`)

**List**: search by name, sort (Newest / Most members / Recently active), with columns photo and name, owner, members, created, last activity. **Detail**: photo, name, rules (with updated date), message **count**, and the member table (avatar, name, role badge Owner/Group admin/Member, joined, suspended marker), linking to users. **Delete group** confirm: type the group name; "Removes the group and all its messages for every member."

No message content anywhere, not even "last message" previews.

### 10.6 Audit log (`/audit`)

A reverse-chronological list: an icon per action type, the summary, the admin, and a relative time with the exact time on hover. Filtering by target comes from links on user and group pages (`/audit?target=<id>`). Read-only.

### 10.7 Circles (`/circles`): placeholder for a future feature

Circles are communities that will be added to Serafim later. **No backend or app support exists.** Build:

- The nav entry, with a small `SOON` eyebrow tag.
- A screen that explains what Circles will be, in the empty-state style (the illustration and type treatment of `friendly_error_box.dart` / the app's empty states).
- An empty `features/circles/` module (`domain/`, `data/`, `presentation/`) with a `CirclesRepository` interface and a `FeatureFlags.circles = false` switch. When it is off, the screen is the placeholder and nothing calls the API.

When Circles ship, the admin side will likely need: list and search circles (name, owner, member count, created, activity), circle detail (description, rules, moderators, members), suspend and delete a circle, remove a member, and an audit entry for each, following the same patterns as Groups. **Don't build or mock any of it now.** Put this list in the module's README as the starting point.

### 10.8 Settings (`/settings`)

Signed-in admin (avatar, name, email, UID with copy), the API base URL in use, server health (`GET /health`: database, push), theme (System / Dark / Light, remembered in `shared_preferences`), the app version of the dashboard, and **Sign out**.

---

## 11. Visual design system: match the Serafim app

The dashboard should look like Serafim, not like stock Material. **Copy** (don't import across repos) these files from the app and keep them in sync by hand:

- `lib/src/utils/themes/app_colors.dart`: `AppPalette.dark` / `.light` and the `AppColors` getters
- `lib/src/utils/themes/app_text_styles.dart`
- `lib/src/utils/serafim_mark.dart` and `assets/icon/app_icon_full.png` (logo)
- Use `serafim_button.dart`, `serafim_chip.dart`, `official_badge.dart`, `setting_tile.dart` and `friendly_error_box.dart` as references for the shared widgets.

### 11.1 Colour tokens

The look is a **"sticker" / comic** style: dark paper surfaces, **navy ink borders**, flat corners, hard offset shadows.

| Token | Dark (default) | Light | Use |
|---|---|---|---|
| `ink` | `#0C0D11` | `#FFFFFF` | Deepest background (sidebar) |
| `paper` | `#15161C` | `#F1F2F7` | Page background (`scaffoldBackgroundColor`) |
| `paperAlt` | `#1A1B22` | `#FFFFFF` | Cards, dialogs, inputs |
| `paperRaised` | `#20222A` | `#E6E9F3` | Hovered rows, snackbars, table headers |
| `line` | `#1C2440` | `#1C2440` | Borders and hard shadows (navy, never black) |
| `lineSoft` | `#33395C` | `#B9BFD6` | Dividers, unselected chip borders |
| `primary` | `#5B7FD6` | `#4A6FC8` | Brand blue: primary buttons, selection, links |
| `primaryDeep` | `#3D5AAD` | `#2F4A9A` | Gradient end, pressed state |
| `primaryPale` | `#A9C0F0` | `#30479A` | Logo, eyebrows, link text |
| `rust` | `#B3562F` | `#B3562F` | **Danger**: suspend, delete, required updates, suspended badge |
| `rustPale` | `#D98A63` | `#A1431F` | Danger text on surfaces |
| `teal` | `#3F7D78` | `#3F7D78` | **Healthy**: active badge, push enabled, online |
| `tealPale` | `#7FB8B0` | `#2B6762` | Success text |
| `text` | `#D7D9E2` | `#1B1E2B` | Primary text |
| `textDim` | `#8A8D9C` | `#5B6075` | Secondary text, body copy |

Theme switching works like the app: `AppColors.apply(brightness)` plus a rebuild. Dark is the default, and "System" follows the browser or OS.

### 11.2 Shape, type and spacing

- **Corners: square** (`BorderRadius.zero`) on buttons, cards, inputs, chips and dialogs. Avatars are the only round things.
- **Borders**: 2 px `line` on buttons and cards; 1.5 px on chips (`lineSoft` when unselected).
- **Shadows**: hard, unblurred, `Offset(3, 3)`, colour `line`. No Material elevation blur.
- **Primary button**: `primary → primaryDeep` diagonal gradient, white Inter 13/700 label, 14×20 padding. **Danger button**: the same shape with a `rust` fill. **Secondary**: `paperAlt` fill, `text` label.
- **Type** (Google Fonts):
  - **Bangers**: the logo (20, `primaryPale`, letter-spacing 0.5) and page titles (26, `text`). Display only, never body text.
  - **Inter**: body and UI. Body 12/1.5 `textDim`, inputs 13 `text`, small 11. Tables and dense desktop text may go up to 13–14 for legibility.
  - **JetBrains Mono**: UPPERCASE eyebrow labels (10, w600, letter-spacing 1, `primaryPale`), field labels (9.5, w600), and UIDs, version codes and SHA-256 values.
- **Spacing**: a 4-pt grid. Cards use 16 px padding on mobile and 20–24 px on desktop.
- **Status badges**: square, bordered, mono uppercase text. `ACTIVE` teal, `SUSPENDED` rust, `NO PROFILE` lineSoft, `SERAFIM ADMIN` primary.

### 11.3 Accessibility

- Text contrast of at least 4.5:1 in both themes (the palette's pale/deep split exists for this).
- Every icon-only button has a tooltip and a semantic label. Every focusable element shows a visible focus ring (2 px `primary`).
- Status is never shown by colour alone: badges carry words.
- Keyboard: `/` focuses search, `Esc` closes dialogs, `Enter` submits forms. Destructive confirms require typing, so a single stray `Enter` can't trigger one.

---

## 12. Suggested file structure

```
serafim_admin_dashboard/
├── lib/
│   ├── main.dart
│   ├── app.dart                         # MaterialApp.router, theme
│   ├── core/
│   │   ├── config/app_config.dart       # dart-defines
│   │   ├── config/feature_flags.dart    # circles = false
│   │   ├── network/api_client.dart
│   │   ├── network/auth_interceptor.dart
│   │   ├── network/api_exception.dart
│   │   ├── format/                      # numbers, dates, bytes
│   │   ├── time/utc.dart
│   │   ├── theme/app_colors.dart        # copied from the app
│   │   ├── theme/app_text_styles.dart   # copied from the app
│   │   ├── router/app_router.dart
│   │   └── widgets/                     # SerafimButton, DangerButton, StatusBadge,
│   │                                    # StatTile, DataTableCard, ConfirmTypeDialog,
│   │                                    # EmptyState, ErrorBox, Pager, AppShell
│   └── features/
│       ├── auth/        {domain,data,presentation}
│       ├── overview/
│       ├── users/
│       ├── announcements/
│       ├── groups/
│       ├── circles/     # placeholder + README of the future admin needs
│       ├── audit/
│       └── settings/
├── test/                                # mirrors lib/features
├── .env.example
└── README.md                            # how to run, configure, deploy
```

Backend additions:

```
Serafim-Backend/
├── app/api/admin.py
├── app/core/admin.py          # is_admin (moved), require_admin
├── app/core/moderation.py     # suspend / unsuspend / delete / delete_group
├── app/core/supabase_admin.py # GoTrue admin + Storage calls (fakeable)
├── app/models/admin_action.py
├── app/schemas/admin.py
├── sql/011_admin.sql
└── tests/test_admin.py
```

---

## 13. Known gaps: don't work around them, propose them

Put these in the dashboard README under "Follow-ups". Don't build them:

- **User reports / moderation queue.** The app has no "report" action yet.
- **Editing a user's profile** (e.g. clearing an offensive username or avatar). Suggest `PUT /admin/users/{id}/profile` with the same validation as `PUT /profile/me`.
- **Targeted announcements** (by version or interest), **scheduled** announcements, editing an announcement.
- **Last seen / activity history.** No such field is stored. Only "online now" exists.
- **Bulk actions.**
- **Admin roles.** Today every admin can do everything, and admins are managed only through `ADMIN_USER_IDS`.
- **Circles** (§10.7).
- Whether friend requests and follows to a suspended user should also be refused. Today only direct messages are (§7.4). Ask the owner before changing it.

If you hit a real gap that blocks a required screen, document it, propose the endpoint shape, and stop on that part. Don't invent a different contract in the client.

---

## 14. Definition of done

### Backend
- [ ] `/admin/*` implemented as in §7.3–7.4, with `require_admin` on every route.
- [ ] WebSocket rejects inactive users; suspend closes their sockets; push skips inactive users; discover and search hide them.
- [ ] Direct messages to a suspended user are rejected with `user_unavailable` / "User not available", and the app shows that text (§7.7).
- [ ] `/auth/users` closed.
- [ ] Audit rows for every admin action, including `/official` posts and deletes.
- [ ] `sql/011_admin.sql` written; new table registered in `main.py` and `conftest.py`.
- [ ] `tests/test_admin.py` covers §7.8; **all** tests pass (`pytest`).
- [ ] No response from any admin route contains message content.

### Dashboard
- [ ] Sign-in on web (Google OAuth redirect, email) and Android (Google ID token); admin gate with all the outcomes in §6.
- [ ] Every screen in §10 works against a local backend, in both themes, at 360 px, 1024 px and 1440 px wide.
- [ ] Destructive actions use typed confirmation and explain their consequences.
- [ ] App-update form validates exactly like the server, blocks a non-increasing version code, and double-confirms required updates.
- [ ] Circles is a placeholder behind `FeatureFlags.circles` with no API calls.
- [ ] `flutter analyze` clean; `dart format` applied.
- [ ] Tests: view-models (filters, pagination, error states), the API error mapping (including 422 list → field errors), the auth interceptor (401 → refresh once → replay), the router guard, the update-form validation and tag parsing, and widget tests for the users list, user detail actions, and the announcement composer. Repositories mocked; no network.
- [ ] `flutter build web --release` and `flutter build apk --release` succeed.
- [ ] README: setup, `.env`, running against local and deployed API, CORS and Supabase redirect steps, follow-ups list.

### Manual check against a local backend
1. Sign in as a non-admin → Not authorized with copyable UID. Add the UID to `ADMIN_USER_IDS`, restart, and Retry → enter.
2. Post a text announcement → it appears in the app's SERAFIM chat live. Delete it → it disappears from the app.
3. Suspend a test user who is signed in on a phone → the app signs them out; they can't sign back in; they're gone from Discover. From a second account, message them → the message fails and the app shows "User not available". Unsuspend → they can sign in again and messages go through.
4. Delete a test user who owns a group → the group gets a new owner in the app; the user is gone from lists; the audit log shows it.
5. Fill an app update from the latest GitHub release → values match `tool/release.sh` output. Don't post it as required against production.

---

## 15. Suggested order of work

1. Backend: move `is_admin`, add `require_admin`, `GET /admin/me`, and close `/auth/users`. Tests.
2. Backend: migration, `admin_actions`, audit on `/official` routes. Tests.
3. Backend: `GET /admin/stats`, `/admin/users` list and detail. Tests.
4. Backend: suspend and unsuspend, including the WebSocket, push and discover changes. Tests.
5. Backend: delete user (with the fake Supabase client), groups list, detail and delete, audit list. Tests. Full suite green.
6. Dashboard: project setup, theme copy, shell and responsive nav, router guard, sign-in and admin gate.
7. Dashboard: API client and error mapping, Overview.
8. Dashboard: Users list and detail with actions.
9. Dashboard: Announcements history and composer, then the app-update form.
10. Dashboard: Groups, Audit, Settings, Circles placeholder.
11. Tests, analysis, builds, README, then the manual check in §14.
