# SERAFIM Circles — Implementation Plan

Status: **Phases 0, 1 and 2 are built.** Phases 3–5 are not.
Repos: app `HINOKAMI/FlutterProjects/serafim`, backend `HINOKAMI/Backend/Serafim-Backend`.

## Where the work is

| Phase | What | Where | State |
|---|---|---|---|
| 0 | Content layer: posts, comments, Sparks | backend | **done** |
| 1 | Circles core: membership, roles, visibility, requests | backend | **done** |
| 2 | Circles UI: the tab, a Circle, creating one, posting | app | **done** |
| 3 | The Feed | backend done, app not | **half** |
| 4 | Nav restructure (Feed / Whispers / Discover / Circles, profile in the app bar) | app | **not started** |
| 5 | Reports and moderation | both | **not started** |

The app's Circles tab is behind `FeatureFlags.circles`, which is `false`
until the backend is deployed. Flip it in
`lib/src/core/config/feature_flags.dart` when `/circles` answers.

### What was added

**Backend** — `app/models/circle.py`, `app/models/post.py`,
`app/core/circles.py` (the permission rules), `app/core/posts.py` (the
visibility rules and the feed query), `app/core/interests.py` (the catalog),
`app/api/circles.py`, `app/api/posts.py`, `app/api/feed.py`,
`app/schemas/circle.py`, `app/schemas/post.py`, `sql/012_circles.sql`,
`sql/013_posts.sql`, `tests/test_circles.py`, `tests/test_posts.py`.

**App** — `lib/src/data/models/circle.dart`, `lib/src/data/models/post.dart`,
`lib/src/data/services/circle_service.dart`,
`lib/src/data/services/post_service.dart`,
`lib/src/providers/circle_providers.dart`,
`lib/src/providers/post_providers.dart`,
`lib/src/presentation/view/circles_page.dart`,
`lib/src/presentation/view/circle_detail_page.dart`,
`lib/src/presentation/view/create_circle_page.dart`,
`lib/src/presentation/view/composer_page.dart`,
`lib/src/presentation/view/widgets/circle_card.dart`,
`lib/src/presentation/view/widgets/post_card.dart`,
`test/circles_test.dart`.

---

## 0. The finding that reshapes this plan

The Circles spec is written against an app that has posts, comments, Sparks,
Echoes and a Feed. **None of those exist.** Circles is not a feature you add
on top of a finished content system — it is the reason you have to build that
system.

Verified against the code, not inferred:

| The spec assumes | Reality |
|---|---|
| "Circle posts should use SERAFIM's existing post, comment, and Spark systems rather than implementing separate versions" | No `posts`, `comments` or `sparks` table exists. No post model, no post route, no post screen. |
| "Each post should support Sparks, comments, replies, and any other interactions already available in SERAFIM's existing post system" | The only "interactions" that exist are on *messages* (reactions to chat messages are not implemented either). |
| "Posts from joined Circles should be eligible to appear in the user's main Feed" | There is no Feed. `navigation_notifier.dart` still carries the comment `// Default starting tab index (0 = Home/Feed)` — a leftover from a planned home tab that was never built. |
| "Unlike Echoes, Circle posts should not automatically disappear after 24 hours" | There are no Echoes either. **Out of scope now** — see §0.1. |
| The new nav: Feed, Whispers, Discover, Circles | Today's nav is Chats / Discover / Profile, three tabs. |

Searches for `circle`, `spark`, `feed`, `echo` in the app all return false
positives: `BoxShape.circle` and `drawCircle` in the doodle sticker kit,
`sparkleAt`, and marketing copy in the landing, login and signup pages. In the
backend, every hit was inside `.venv` (pip's vendored `rich` and `pygments`).

The backend's real table list is: `users`, `profiles`, `friendships`,
`follows`, `groups`, `group_members`, `messages`, `media`, `devices`,
`notifications`, `announcements`, `admin_actions`.

The admin dashboard brief already knows this — §10.7 reserves a Circles
placeholder behind `FeatureFlags.circles = false` and says in as many words:
**"No backend or app support exists."**

**Consequence for the plan:** the Circles spec's own §11 phase list is
reasonable in spirit but under-counts, because it treats the content layer as
already built. The phases below are re-cut around the real dependency order.

### 0.1 Decisions taken (2026-10-19)

| Question | Decision |
|---|---|
| Circle role names | **Owner / Overseer / Member.** Not "admin" — the admin dashboard brief warns that "group admin" versus "Serafim admin" confuses people, and a Circle's Overseer is neither. A distinct word keeps three vocabularies apart: *Serafim admin* (backend), *group admin* (chat groups), *Circle Overseer*. |
| Echoes | **Not built.** Echoes are a story format: ≤ 30 s, visible for 24 hours. Deferred, and no part of the model anticipates them beyond §6.4. |
| Sparks | **Sparks are likes.** One per person per target, a toggle, a count. No kinds, no reactions palette. "Spark" stays the product word; the mechanic is exactly a like. |
| Post sorting | **Newest first only.** No "Popular" toggle, and no popularity formula. The Circle's post list is one list, newest at the top. |
| Scope | **Circles first.** The Feed, the nav restructure and the rest follow the Circles work; Echoes, trending, recommendations, pins-to-announcements, member search and invitations are all deferred. |

Two of these simplify the build a lot: dropping Echoes removes the expiry
filter from every read path, and dropping popular sorting removes the
denormalised counters that existed only to feed it.

---

## 1. What already exists and gets reused

Circles are a near-clone of Groups with three additions: **visibility**,
**membership requests**, and **content**. Groups already solve ownership,
roles, transfer-on-leave, moderation and cascade deletion.

| Circle needs | Reuse | File |
|---|---|---|
| Circle roles owner/overseer/member | `OWNER/ADMIN/MEMBER`, `MANAGERS`, `can_manage`, `can_remove` — the shape transfers, the names do not | `app/core/groups.py` |
| "can this role edit / remove" | `can_manage()`, `can_remove()` | `app/core/groups.py` |
| Membership lookup | `membership()`, `is_member()`, `member_ids()` | `app/core/groups.py` |
| Who inherits a circle when the owner leaves | `successor()` (longest-standing admin, else member) | `app/core/groups.py` |
| Explicit cascade delete (not relying on DB cascades) | `delete_everything()` | `app/core/groups.py` |
| Notify + push + socket, and retract on undo | `notify()`, `retract()` | `app/core/notifications.py` |
| Audit rows for every moderation action | `record()` | `app/core/moderation.py` |
| Summary/detail schema split, literal roles, plain-English validators | `GroupSummary` / `GroupDetail` | `app/schemas/group.py` |
| Route + response conventions | `/groups` router | `app/api/groups.py` |
| Hand-written migrations run once | `sql/NNN_*.sql` | `sql/` |
| Tests on SQLite, table list in one place | `TABLES` list | `tests/conftest.py` |
| Interest categories for a circle's category | 9 categories, 89 interests | `lib/src/data/interest_catalog.dart` |
| Design system: colours, type, shape, logo | — | `app_colors.dart`, `app_text_styles.dart`, `serafim_mark.dart` |
| Bottom nav / top bar shells | — | `app_bottom_nav.dart`, `app_top_bar.dart` |

---

## 2. Data model

### 2.1 Circles

**`circles`**
| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `name` | VARCHAR(50) | not unique; collisions allowed, disambiguated by owner |
| `description` | TEXT | ≤ 1000 |
| `category` | VARCHAR(32) | one of the 9 interest categories (see §8 Q5) |
| `icon_url` | VARCHAR(500) | nullable |
| `banner_url` | VARCHAR(500) | nullable |
| `visibility` | VARCHAR(16) | `public` \| `private` \| `invite_only`, default `public` |
| `owner_id` | UUID FK → users.id | exactly one owner, mirrored from the owner's membership row |
| `rules` | TEXT | ≤ 2000, nullable |
| `rules_updated_at` | TIMESTAMPTZ | |
| `posting_enabled` | BOOLEAN | default true; false = read-only circle |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

**`circle_members`**
| Column | Type | Notes |
|---|---|---|
| `circle_id` + `user_id` | composite PK | |
| `role` | VARCHAR(16) | `owner` \| `overseer` \| `member` |
| `joined_at` | TIMESTAMPTZ | drives seniority for ownership transfer |
| `added_by` | UUID | nullable |
| `muted` | BOOLEAN | default false — spec §8 "mute individual Circles" |
| `notify_posts` / `notify_replies` / `notify_mentions` | BOOLEAN | spec §8 "control which types of notifications they receive" |

**`circle_join_requests`** — `id` PK, `circle_id`, `user_id`, `message` (nullable),
`status` (`pending`/`approved`/`rejected`), `created_at`, `decided_at`, `decided_by`.
Unique on `(circle_id, user_id)` where pending.

**`circle_bans`** — `circle_id`, `user_id`, `banned_by`, `reason`, `created_at`.

### 2.2 The content layer (new — Circles needs it, and the Feed needs it)

**`posts`**
| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `author_id` | UUID FK → users.id | |
| `circle_id` | UUID FK → circles.id, **nullable** | **null = profile post, set = Circle post** (spec §10, exactly) |
| `content` | TEXT | ≤ 2000 |
| `kind` | VARCHAR(16) | `text` now; `image` later |
| `media_ids` | ARRAY(UUID) | see §8 Q3 |
| `spark_count` | INT | denormalised, maintained in code — shown on the post card |
| `comment_count` | INT | denormalised, shown on the post card |
| `pinned_at` | TIMESTAMPTZ, nullable | pinned posts sort above everything else |
| `created_at` / `edited_at` / `deleted_at` | TIMESTAMPTZ | soft delete on `deleted_at` |

No `expires_at` column: every post is permanent. Echoes are deferred, and
when they arrive this is one nullable column and one filter — see §6.4.

**`comments`** — `id` PK, `post_id` FK, `author_id` FK, `parent_id` FK → comments.id
(nullable = a reply), `content` (≤ 1000), `spark_count`, `created_at`, `edited_at`,
`deleted_at`.

**`sparks`** — `id` PK, `user_id` FK, `post_id` FK nullable, `comment_id` FK nullable,
`created_at`, with `CHECK ((post_id IS NOT NULL) <> (comment_id IS NOT NULL))` and
unique partial indexes on `(user_id, post_id)` and `(user_id, comment_id)`.
One table rather than two, because a Spark is one concept applied to two targets.

A Spark is a like: one per person per target, created and deleted to toggle,
counted in `spark_count`. There is no Spark type, no reaction palette, and no
Spark editing.

### 2.3 The Feed is a query, not a table

`GET /feed` returns posts where **either** the author is someone you follow
**or** the circle is one you have joined, newest first, cursor-paginated on
`(created_at, id)`.

The query **must** join `circle_members` to enforce private-circle visibility
before the rows are selected — not fetch-then-filter. This is the single
highest-risk query in the feature; see §7.

---

## 3. Backend

### 3.1 New files

```
app/models/circle.py      Circle, CircleMember, CircleJoinRequest, CircleBan
app/models/post.py        Post, Comment, Spark
app/core/circles.py       permission rules (the heart — see below)
app/core/posts.py         post visibility + the feed query
app/api/circles.py        /circles
app/api/posts.py          /posts, /comments, /sparks
app/api/feed.py           /feed
app/schemas/circle.py     CircleSummary, CircleDetail, CircleMemberOut, ...
app/schemas/post.py       PostOut, CommentOut, FeedPage
sql/012_circles.sql
sql/013_posts.sql
tests/test_circles.py
tests/test_posts.py
tests/test_feed.py
```

The migration numbers continue from the eleven that exist
(`001_message_attachments` … `011_admin`); `008_groups.sql` is the template to
copy — `CREATE TABLE IF NOT EXISTS`, explicit `ON DELETE` behaviour, and an
index on the reverse foreign key (`ix_group_members_user`) so the
"my circles" query does not scan.

### 3.2 Modified files

- `app/main.py` — register the three routers; add the new tables to the
  explicit `create_all(tables=[...])` list (it is explicit on purpose: the
  metadata also holds a stub for Supabase's `auth.users`).
- `tests/conftest.py` — add the new tables to `TABLES`.
- `app/core/notifications.py` — new notification types.
- `app/core/moderation.py` — circle admin actions (suspend/delete circle,
  remove member) reusing `record()`.

### 3.3 `app/core/circles.py` — permission rules

Mirrors `app/core/groups.py` closely, so the two files read alike:

```python
PUBLIC, PRIVATE, INVITE_ONLY = "public", "private", "invite_only"
OWNER, OVERSEER, MEMBER = "owner", "overseer", "member"
MANAGERS = {OWNER, OVERSEER}

async def membership(db, circle_id, user_id) -> CircleMember | None
async def is_member(db, circle_id, user_id) -> bool
async def member_ids(db, circle_id) -> list[UUID]
async def can_see_circle(db, circle, user_id) -> bool   # public => True
async def can_read_post(db, post, user_id) -> bool        # joins membership
async def can_post(db, circle, user_id) -> bool           # member && posting_enabled
def can_manage(role) -> bool
def can_remove(actor_role, target_role) -> bool
async def successor(others) -> CircleMember
async def delete_everything(db, circle) -> None
```

`OWNER` and `OVERSEER` both count as managers, but they are not
interchangeable: only the Owner may appoint or remove Overseers, delete the
Circle, change its visibility, or transfer ownership. An Overseer may approve
membership requests, remove posts and comments, pin posts, and manage plain
members. `can_manage()` and `can_remove()` are split accordingly, so the
distinction lives in one place instead of being re-derived per route.

Two of these are the load-bearing ones:

- **`can_see_circle`** — a public circle is visible to everyone; `private` and
  `invite_only` are visible (discoverable) but their *content* is not.
- **`can_read_post`** — the single gate every read path goes through. A post
  in a private circle is readable only by that circle's members. Nothing else
  in the codebase may read a post row without it.

### 3.4 API surface

**`/circles`**
```
POST   /circles                              create
GET    /circles                              my joined circles
GET    /circles/discover?section=&category=&q=  for_you | popular
GET    /circles/{id}                         detail
PUT    /circles/{id}                         owner only
DELETE /circles/{id}                         owner only, typed confirmation
POST   /circles/{id}/join                    public => join; private => request
POST   /circles/{id}/leave
GET    /circles/{id}/requests                owner/overseer
POST   /circles/{id}/requests/{uid}/approve
POST   /circles/{id}/requests/{uid}/reject
GET    /circles/{id}/members
PUT    /circles/{id}/members/{uid}/role      owner sets overseer/member
DELETE /circles/{id}/members/{uid}
POST   /circles/{id}/ban/{uid}
POST   /circles/{id}/transfer
POST   /circles/{id}/mute  ·  /unmute
PUT    /circles/{id}/settings/notifications
```

`discover`'s `popular` section is public circles ordered by member count. That
is a plain count, not a ranking formula — there is no trending model, and the
spec's "attracting members or generating discussions" stays a member count
until there is a reason to do better.

**`/posts`**
```
GET    /posts?author_id=|circle_id=           list, visibility-filtered, newest first
POST   /posts                                 {content, circle_id?, media_ids?}
GET    /posts/{id}
DELETE /posts/{id}                            author, or a Circle Overseer
PUT    /posts/{id}/pin  ·  /unpin             Overseer
POST   /posts/{id}/spark  ·  DELETE /posts/{id}/spark
GET    /posts/{id}/comments
POST   /posts/{id}/comments
DELETE /comments/{id}
POST   /comments/{id}/spark
```

There is no `sort` parameter. A Circle's Posts tab is one list, newest at the
top, with pinned posts above it. The spec asked for "at least two sorting
options: Latest and Popular"; Popular is deferred with the rest (§6.4).

**`/feed`**
```
GET    /feed?cursor=                           mixed: followed people + joined circles
```

### 3.5 Notification types

Added to `app/core/notifications.py`, each with its own push copy and socket
payload, and each respecting the member's per-circle preferences:

`circle_join_request`, `circle_request_approved`, `circle_request_rejected`,
`circle_post_commented`, `circle_comment_replied`, `circle_mention`,
`circle_post_pinned`, `circle_role_changed`, `circle_banned`, `report_filed`.

---

## 4. Flutter app

### 4.1 New files

```
lib/src/data/models/circle.dart          circle, member, request, summary/detail
lib/src/data/models/post.dart            post, comment, spark
lib/src/data/services/circle_service.dart
lib/src/data/services/post_service.dart
lib/src/data/services/feed_service.dart
lib/src/providers/circle_providers.dart
lib/src/providers/post_providers.dart
lib/src/providers/feed_providers.dart
lib/src/presentation/view/circles_page.dart        the Circles tab
lib/src/presentation/view/circle_detail_page.dart   Posts | About | Members
lib/src/presentation/view/create_circle_page.dart
lib/src/presentation/view/circle_requests_page.dart
lib/src/presentation/view/feed_page.dart
lib/src/presentation/view/composer_page.dart        post composer + target picker
lib/src/presentation/view/post_detail_page.dart
lib/src/presentation/view/widgets/post_card.dart
lib/src/presentation/view/widgets/comment_tile.dart
lib/src/presentation/view/widgets/circle_card.dart
lib/src/presentation/view/widgets/circle_badge.dart   "in Flutter Developers"
```

### 4.2 Modified files

| File | Change |
|---|---|
| `lib/src/presentation/view/main_screen.dart` | 4 tabs in the `IndexedStack`; profile removed from the tab list |
| `lib/src/utils/app_bottom_nav.dart` | already takes a list of items — no change needed, just a new item list |
| `lib/src/presentation/viewmodel/navigation_notifier.dart` | default index; fix the stale `0 = Home/Feed` comment |
| `lib/src/utils/app_top_bar.dart` | already supports `titleWidget` and `trailing` — add the profile menu as `trailing` |
| `lib/src/presentation/view/profile_page.dart` | becomes a pushed route instead of a tab |
| `lib/src/core/config/feature_flags.dart` | add `circles`, `posts`, `feed`. The class exists today with one flag (`emailSignIn`); the admin dashboard brief already reserves a `FeatureFlags.circles` switch on the *dashboard* side, so the app should match that name. |

**Feature flags are not optional here.** The nav must never ship a dead tab,
so `circles` and `feed` gate their own tab's presence until the backend is
live behind the Cloudflare Worker.

### 4.3 Words the UI must use

| Thing | Label | Never |
|---|---|---|
| The person who owns a Circle | **Owner** | "Admin", "Creator" |
| The person who helps run a Circle | **Overseer** | "Moderator", "Admin" |
| A Circle member | **Member** | "Follower", "Subscriber" |
| A group-chat admin (`groups` table) | **Group admin** | "Overseer" |
| A Serafim administrator (`ADMIN_USER_IDS`) | **Serafim admin** | "Overseer" |

The app's own UI already has to keep "group admin" and "Serafim admin" apart
(the admin dashboard brief makes a point of it). Adding "Overseer" is a
third word in the same family, and it must not leak into the other two. The
app never shows the word "admin" for anything to do with Circles.

A post inside a Circle is labelled with both, as the spec's example shows:
**"Alex Banda · Flutter Developers"**.

---

## 5. The new navigation

### 5.1 Bottom bar

```
Feed  |  Whispers  |  Discover  |  Circles
```

Currently `AppBottomNav` renders a list of `AppBottomNavItem` and is already
generic — no new component needed, just a new list. The selected tab keeps
the primary-blue pressed block and the mono label, per the app's design rules.

### 5.2 Profile moves to the app bar

`AppTopBar` already takes a `trailing` widget. The plan:

- A shared `SerafimAppBar` widget used by every tab, so the profile menu is
  in the same place on all of them.
- `trailing` = a `ProfileMenuButton`: the user's avatar, opening a
  `PopupMenuButton` with:
  - **Profile** → pushes `ProfilePage` as a route
  - **Settings** → pushes the settings screen
  - **About Serafim** → pushes a small about screen
  - **Log out** → the existing sign-out path, with confirmation

`ProfilePage` currently owns its own app bar and hosts the settings entries
and the log-out button. Splitting it means moving those entries into the
dropdown and/or a settings route. The dropdown should not be a dumping
ground — the spec's list is short, and that is deliberate.

### 5.3 "Whispers" rename

The spec's final concept calls private conversations **Whispers**; the app
calls them **Chats** everywhere — the tab label, `ChatListPage`, the
notification copy, the settings.

Recommendation: **rename the tab label now, defer the full copy rename.** The
label is a one-line change; the full rename touches dozens of strings and
screens and should ride along with a broader copy pass. The `messages` table
and the WebSocket protocol keep their names either way.

---

## 6. Sequencing — re-cut phases

The spec's §11 phases are re-cut below. The order is driven by what each phase
actually depends on.

### Phase 0 — Content foundation (backend only, no UI)
`posts`, `comments`, `sparks` tables and models; `core/posts.py` visibility
rules; post, comment and spark routes; tests.

Build `circle_id` in from the start, even though Circles do not exist yet —
the spec is explicit that a post is a profile post when `circle_id` is null
and a Circle post when it is set, and retrofitting that later means rewriting
every query and every permission check. The column stays null until Phase 1
gives it something to point at.

### Phase 1 — Circles core (backend)
`circles`, `circle_members`, `circle_join_requests`, `circle_bans`;
`core/circles.py`; create/edit/delete; join/leave/approve/reject; roles;
transfer; ban; discovery; notifications; audit entries; tests.

### Phase 2 — Circles UI (app)
Circles tab (For You / Popular / Joined + search + create); circle detail
(Posts / About / Members); join, leave, request, approve; role management;
moderation actions; pinning.

### Phase 3 — Feed (backend + app)
`GET /feed`; Feed tab; composer with the profile-or-Circle target picker
(spec §5: "Alex Banda · Flutter Developers"); post detail; comments;
replies; Sparks.

### Phase 4 — Navigation restructure (app)
Four tabs; profile out of the bottom bar into the app-bar dropdown;
Whispers label. Gated so the nav never shows an empty tab.

### Phase 5 — Reports and moderation
`reports` table; report posts, comments, members and circles; a moderation
queue in the app; circle admin actions in the admin dashboard (the brief
already lists exactly what those are, in §10.7 — "don't build or mock any of
it now" applies to the *dashboard*).

### 6.4 Deferred — explicitly out of scope for now

Everything the spec's own §11 calls "later releases", plus two decisions
taken on 2026-10-19:

| Deferred | Note for when it comes back |
|---|---|
| **Echoes** | A story format: ≤ 30 s, visible for 24 hours. Not built. Nothing in the current model anticipates it. When it does: add `posts.expires_at TIMESTAMPTZ NULL`, filter `expires_at IS NULL OR expires_at > now()` on every read path, and add a `kind` of `echo` with a media reference and a duration. The `media` table already carries `duration_ms` and `waveform` for voice notes, so an Echo is close to a voice note with a 24-hour life. |
| **Popular sorting** | Circle posts are newest-first only. When a formula is agreed, it needs the popularity signals the deferred `spark_count`/`comment_count` columns were there to carry. |
| Recommendations, trending discussions, pinned announcements, member search, invitations | Per the spec's §11. |
| Real-time Circle chat, voice rooms, events, polls | Per the spec's §11. The spec is explicit that posts and comments should remain the main discussion format, because they stay readable for people who join later. |

---

## 7. The requirements most likely to go wrong, and how each is enforced

| Spec requirement | How it is actually enforced |
|---|---|
| **"Private Circle content must never appear in public feeds, recommendations, search previews, or notifications sent to non-members."** | Every read path selects through `core/circles.py:can_read_post`, and the feed query joins `circle_members` **before** selecting rows. The post row is never fetched for a non-member and then filtered. Search and recommendations filter on the same predicate. |
| **"The backend must enforce membership, visibility, and role permissions. Hiding buttons in the Flutter interface is not sufficient."** | All checks live in `core/circles.py` and are called from the routes. The app hides buttons for UX only; the server is the boundary. Every mutating route re-checks the caller's role at call time. |
| **"Leaving removes their membership and access to member-only content, but their existing posts should generally remain."** | Posts survive the leaving. The author keeps ownership of their own posts, so they can still delete them, but lose read access to the circle's other content. Post ownership is independent of membership. |
| **"Roles apply separately to each Circle."** | `role` lives on `circle_members`, not on the user. One row per (circle, user). |
| **"Pinned posts should appear at the top."** | `posts.pinned_at`; the ordering is `pinned_at DESC NULLS LAST, created_at DESC`. |
| **"Private Circles: anyone may discover the Circle"** | The circle *record* (name, description, category, member count) is discoverable. The circle's *posts and comments* are not. Discovery and content visibility are separate checks — `can_see_circle` and `can_read_post`. |
| **"Echoes are a story format, 30 s, gone after 24 hours"** | **Not built.** No `expires_at` column, no expiry filter, no story UI. Every post is permanent. §6.4 records exactly what to add when Echoes are picked up. |
| **"Owner, Moderator and Member"** | Owner / **Overseer** / Member. The distinction between Owner and Overseer lives in `core/circles.py`, not in the routes: only an Owner may appoint or remove Overseers, change visibility, delete the Circle or transfer ownership; an Overseer may approve requests, remove content, pin posts and manage plain members. |
| **"Latest and Popular" sorting** | **Newest first only.** One list, no `sort` parameter, no popularity formula. |
| **"Important moderation actions should be recorded in an audit log."** | `core/moderation.py:record()` is called with the same transaction as the change, and `admin_actions.target_type` gains a `circle` value. |
| **"An owner who leaves"** | `successor()` — the longest-standing Overseer, else the longest-standing member — inherits ownership, exactly as groups do. |

---

## 8. Open questions

Six questions remain, renumbered after the 2026-10-19 decisions closed four of
them (§0.1). These still need an answer before Phase 1 starts.

1. **Circle category.** Reuse the 9 interest categories as a fixed enum
   (`Sports`, `Hobbies`, …) or free text? Reusing them makes "For You"
   recommendation trivial and keeps the vocabulary consistent with profiles,
   which already carry interests from the same catalog.
2. **Icon and banner storage.** The spec gives a Circle both an icon and a
   banner. There is already a convention: the `avatars` bucket is public, and
   each user writes only to their own folder. Group photos already live there
   as `<user id>/group_<group id>.jpg`, uploaded by whoever created the group.
   Should a Circle's icon follow that same rule (`<owner id>/circle_<id>.jpg`)
   in the existing bucket, and where does the banner go — same bucket, or a
   new one with its own policies? A banner is wide and shared, so "the
   uploader's own folder" gets awkward once Overseers change it.
3. **Post media.** The `media` table is currently chat-scoped (`recipient_id`,
   `group_id`). Posts need their own attachment model, or `media` grows a
   `post_id` column. The spec's §5 says posts "share images", so this cannot
   be deferred indefinitely — but it can be deferred past Phase 1, since
   text-only Circle posts are a coherent first release.
4. **Feed ordering.** Pure reverse-chronological, or ranked? Pure is simpler
   and ships faster, and is defensible for v1.
5. **"For You" Circles.** Recommended from the user's 89 interests mapped to
   circle categories, then ranked by activity and member count? The spec says
   "shared interests, followed accounts, and community activity" — followed
   accounts implies people you follow have joined circles, which is a
   different signal from interests. Until this is settled, "For You" can ship
   as plain member-count ordering, same as "Popular", and be worth less.
6. **Posting restrictions.** "Posting restrictions when necessary" — is that
   a per-circle `posting_enabled` toggle (a read-only Circle), or an Overseer
   action against one member, or both?

---

## 9. Size

Order-of-magnitude estimate, excluding review and iteration:

| Area | Backend | App | Tests |
|---|---|---|---|
| Content layer (Phase 0) | ~1100 lines | — | ~500 |
| Circles core (Phase 1) | ~1000 lines | — | ~700 |
| Circles UI (Phase 2) | — | ~2200 | ~700 |
| Feed (Phase 3) | ~400 | ~1300 | ~500 |
| Nav (Phase 4) | — | ~300 | ~150 |
| Moderation (Phase 5) | ~500 | ~500 | ~300 |

Dropping Echoes took roughly 100 lines off the content layer and removed an
expiry filter from every read path — a query that would have had to be
remembered in eight places, and the kind of thing that is forgotten in one
of them.

This is a multi-week feature, not a multi-day one. The spec's phase list is
close to right in spirit, but under-counts because it treats the content layer
as already built — and the content layer is roughly half the work.

The honest first milestone is **Phase 0 + Phase 1 + Phase 2**: circles you can
create, join, and post in, with a Circles tab and no Feed yet. The nav
restructure then lands in Phase 4 with all four tabs real.
