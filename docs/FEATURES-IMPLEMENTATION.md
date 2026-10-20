# Serafim — feature implementation spec (batch 2)

For the engineer/agent implementing these. Read the whole file first. Work in the order
of the "Suggested order" at the bottom. Run `flutter analyze` and `flutter test` after
each feature; backend: `cd /run/media/brightbanda/HINOKAMI/Backend/Serafim-Backend &&
.venv/bin/python -m pytest tests -q` (237 tests pass today; keep them passing).

Repos
- App: `/run/media/brightbanda/HINOKAMI/FlutterProjects/serafim` (Flutter, Riverpod 3,
  Isar local DB). Paths below are relative to `lib/src/` unless stated.
- Backend: `/run/media/brightbanda/HINOKAMI/Backend/Serafim-Backend` (FastAPI, SQLAlchemy;
  tests run on SQLite via `tests/conftest.py`; helpers `env.add_user`, `as_user`).

House rules (match the surrounding code)
- UI uses `AppColors`, `AppTextStyles`, `AppTopBar`, `SerafimButton`; square corners, 1.5px
  borders. Do not introduce Material rounded styles.
- Never run `dart format` on the whole tree: format only files you touched.
- No new Isar field without regenerating: `dart run build_runner build --delete-conflicting-outputs`.
- Feature flags stay as they are (`core/config/feature_flags.dart`, circles/posts on).
- Errors shown to people go through `core/errors/human_error.dart` `humanError(e)`.

---

## 1. Image editor before sending (crop + draw)

Goal: after the user picks a chat image, open an editor with **Crop** and **Draw** tools;
Send/Done returns the edited JPEG bytes; Cancel aborts the send.

Where it hooks in
- `presentation/view/chat_thread_page.dart` `_handleAttach()` (~167-210). Today:
  `pickShrunkImage(...)` (`utils/image_picking.dart`) → `chatViewModelProvider.notifier
  .sendMessage(imageBytes: bytes, ...)`. Insert the editor between those two calls:
  `final edited = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(builder:
  (_) => ImageEditorPage(bytes: bytes)));` — `null` means cancel: do nothing, clear `_attaching`.
- `_attaching = true` is set in the `onPicked` callback, i.e. before the editor opens. Set it
  back to false while the editor is open (or move the flag to after the editor) so no
  spinner shows behind the editor.
- Do NOT route `_handleInserted` (keyboard GIF/sticker insert, ~line 640) through the
  editor, and never edit GIFs.
- Reuse the same editor for post pictures in `presentation/view/composer_page.dart`
  `_addImages` (optional; chat is the requirement).

New files
- `presentation/view/image_editor_page.dart` — `ImageEditorPage({required Uint8List bytes})`
  returns `Uint8List?` via `Navigator.pop`.
- `utils/image_editor/draw_canvas.dart` — a `CustomPainter` + gesture layer.
- `utils/image_editor/stroke.dart` — `class Stroke { Color color; double width; List<Offset> points; }`.

Dependencies
- Add `crop_your_image` (pure Dart, works on bytes) to `pubspec.yaml` for the crop step.
  The `image` package (already present) is used for final encoding; no other new package.
- Drawing is custom: no painter package.

Behaviour (be exact)
- Two tabs/modes at the bottom: **Crop**, **Draw**. Top bar: back (cancel, confirm
  discard if edits exist), and a **Done** button.
- Pipeline: Crop produces new bytes → Draw operates on those bytes. If the user switches
  Draw → Crop after drawing, first flatten strokes into the bytes (apply, then crop) and
  clear the stroke list, so crop never misaligns strokes. Show a one-line note
  "Drawing is applied before cropping".
- Crop: free aspect by default plus preset chips Free / 1:1 / 4:3 / 16:9. Rotate 90° button.
- Draw:
  - Exactly **7 colors**: white `#FFFFFF`, black `#000000`, red `#E53935`, orange `#FB8C00`,
    yellow `#FDD835`, green `#43A047`, blue `#1E88E5`. Selected color shows a ring.
  - Exactly **3 stroke sizes**: thin 3, medium 8, thick 16 (logical px at the on-screen
    image width; scale to image pixels when flattening: `strokePx = width * imagePx / displayedPx`).
  - Round caps/joins, `Paint.style = stroke`, no fill. Smooth by drawing quadratic
    midpoints between points.
  - Buttons: **Undo** (pop last stroke), **Clear all**. Default color red, size medium.
  - Single-finger draw only; if the image is shown in an `InteractiveViewer`, disable pan
    while drawing.
- Export: render the base image + strokes with `ui.PictureRecorder` at the image's pixel
  size, `toImage`, `toByteData(format: png)`, then run through `shrinkImage(...)`
  (`utils/image_shrink.dart`) using the user's chat quality setting
  (`settingsProvider.imageQuality.maxSide/jpegQuality`) so the size stays the same as
  today's pipeline. Run heavy work off the UI isolate where possible (`compute`).
- Large images: the editor displays a downscaled copy (max side ~1600) but must map
  strokes to the exported size.

Tests (`test/image_editor_test.dart`)
- Stroke scaling math (display → image px) as a pure function.
- Widget test: the 7 color swatches and 3 size buttons exist; Undo removes the last stroke.

---

## 2. Chat background: preview + opacity slider

Goal: when choosing a chat background, show a live preview of the chat with the chosen
background, and a slider that controls how strongly the background shows (opacity/dim).

Facts
- `presentation/view/chat_background_page.dart` already has `_Preview(wallpaper: _selected)`
  at the top; state: `_selected`, `_applyToAll`, `_picking`, `_saving`; `_save()` calls
  `wallpaperProvider.notifier.choose(roomId, wallpaper, applyToAll:)`.
- `data/models/chat_wallpaper.dart`: `ChatWallpaper` has `kind`, `value`; stored as a
  string by `encode()` (`'kind'` or `'kind:value'`) and read by `decode()`; `==`/`hashCode`
  use kind+value. Image wallpapers: `ChatWallpaper.image(path)`; `WallpaperSettings
  .imagePaths` reads `w.value!` as a plain path and `WallpaperImageStore.prune` deletes
  files not in that set (`providers/wallpaper_providers.dart`).
- `utils/chat/chat_background.dart` `ChatWallpaperView` renders each kind; image kind draws
  `Image.file` + a fixed scrim (`imageScrim`: white 30% light / black 40% dark).
- Persisted in `data/local/local_cache.dart` (~215-240) under
  `cache.v1.<account>.wallpaper.default` / `.rooms`.

Design
1. Add a `double opacity` (0.2–1.0, default 1.0) to `ChatWallpaper` as a **separate field,
   not part of `value`** (so `imagePaths`/prune keep working). Encoding becomes
   `kind[:value][@opacity]`, e.g. `image:/path/x.jpg@0.6`; `decode` must accept old strings
   with no `@` (opacity 1.0) and must split on the **last** `@` only. Update `==`, `hashCode`,
   `encode`, `decode`, and all factories (`ChatWallpaper.color/gradient/image`) with an
   optional `opacity` param; add `copyWithOpacity(double)`. `doodles` and `plain` ignore it.
2. `ChatWallpaperView`: apply opacity to the wallpaper layer itself
   (`Opacity`/`withValues(alpha:)` over the page background colour) rather than only the
   scrim. For `image`, keep the existing scrim and multiply the image alpha.
3. `chat_background_page.dart`: add `double _opacity` initialised from the current
   wallpaper; add a `Slider(min: 0.2, max: 1.0, divisions: 16)` with label "Background
   strength" under `_Preview`; pass `_selected.copyWithOpacity(_opacity)` to the preview and
   to `choose(...)`. Disable the slider for `doodles`/`plain`.
4. Upgrade `_Preview` into a realistic **chat preview**: two sample bubbles (one incoming,
   one outgoing, using the real bubble widgets/colours) drawn over `ChatWallpaperView`, in a
   fixed-height box (~220). It must update live while the slider moves (setState).
5. Gallery pick flow stays; after picking, show the preview before saving (already so).

Tests: extend/replace `test/` for wallpaper encoding round trip (old string → opacity 1.0;
new string; path containing `@`), equality, and `imagePaths` still returning plain paths.

---

## 3. Auto-open keyboard on reply (chat)

- `chat_thread_page.dart` `_startReply(LocalMessage)` (~557-564) sets `_replyingTo` and
  nothing else. `_inputFocus` (FocusNode, line ~137) already exists and is passed to
  `ChatInputBar` (`utils/chat/chat_input_bar.dart`, `focusNode`).
- Change: after `setState(() => _replyingTo = message)`, call
  `WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _inputFocus.requestFocus(); });`
- If the sticker panel is open (`_toggleStickers`, ~620), close it first so the keyboard
  and panel never show together.
- The long-press menu has no Reply entry; add one (see §4 for the menu edit) that calls
  `_startReply` — optional but cheap, since swipe-to-reply is hard to discover.
- Test: widget test that triggers reply and asserts `_inputFocus.hasFocus`.

---

## 4. Message forwarding (to friends and group chats)

Nothing exists today. Decisions:
- No backend change. A forward is sent as a **new normal message** with the same content.
- The sender's own copy gets a local-only "Forwarded" label (new Isar field); recipients
  see a normal message. (Optional follow-up, out of scope: add `forwarded` column to
  `messages`, `sql/` migration, ws payloads.)
- Types: text ✔ (to 1-1 and groups); sticker ✔ (text carrying the sticker id,
  `kind:"sticker"`); voice ✔ only when `mediaRemoteId != null` (reuse the id, no re-upload);
  **image → friends/1-1 only**: server `app/api/ws.py handle_group_message` rejects any
  attachment (`attachments_not_supported_in_groups`), so the picker must disable groups
  when the forwarded message is an image, with the hint "Pictures can't be sent to groups".
  Deleted or not-yet-sent (`sending`/`failed`) messages cannot be forwarded.

Model change (Isar)
- `data/domain/local_chat_message.dart` `LocalMessage`: add `bool forwarded = false;`
  Regenerate with build_runner. Do **not** reorder `MessageType`/`MessageStatus` enums.

Menu
- `utils/chat/message_actions.dart`: `enum MessageAction { copy, download, edit, delete }` →
  append `forward` (and optionally `reply`) at the END. Extend `availableMessageActions(...)`
  so `forward` is offered when the message is not deleted and `isConfirmed` (sent+).
- `chat_thread_page.dart` `_showMessageActions(...)` (~332): add the ListTile for forward
  and a `case` in the dispatch switch (see how 'copy' is dispatched). Call sites ~1061 and ~1110.

Picker
- New `presentation/view/forward_page.dart` — `ForwardPage({required List<LocalMessage>
  messages})`; opened with `Navigator.push`. Single message is required; multi-select of
  messages is out of scope.
- Content: search box, then sections **Recent chats** (order via the same recency logic as
  `_byRecentActivity` in `chat_list_page.dart`), **Friends** (`friendsViewProvider.friends`,
  `providers/social_providers.dart`), **Groups** (`myGroupsProvider`,
  `providers/group_providers.dart`; type `GroupSummary`). Multi-select with checkboxes, max
  5 targets; a bottom "Send (n)" button.
- Do not reuse `utils/member_picker.dart` (friends only, no groups); you may copy its row style.

Sending
- For each target build roomId: 1-1 → `ChatViewModel.buildRoomId(myId, friend.id)`;
  group → `groupRoomId(group.id)` (`data/models/group.dart`).
- Add `ChatViewModel.forwardMessage({required LocalMessage source, required String
  recipientId, String? groupId})` in `presentation/viewmodel/chat_viewmodel.dart`, which
  reuses the existing senders with `replyToId: null`:
  - text → `sendMessage(roomId, recipientId, content: source.textContent!, groupId)`
  - image → read bytes of `source.localMediaPath`, `sendMessage(imageBytes: bytes, ...)`
  - sticker → `sendSticker(...)`
  - voice → `sendVoice(...)` reusing `mediaRemoteId`/`durationMs`/`waveform`
  After the local row is written set `forwarded = true` on it.
- Show a snackbar "Forwarded to N chats" and pop. If a target fails, report which.
- For groups `recipientId` is the group id and `groupId` is set (see `utils/group_nav.dart`).

UI
- `utils/chat/` message bubble: when `message.forwarded` render a small
  "↪ Forwarded" label above the content in `AppTextStyles.smallDim`.

Tests: `availableMessageActions` includes forward only for confirmed, undeleted messages;
forward of an image offers no group targets; `forwardMessage` writes a row with
`forwarded == true` (use the fake websocket pattern from existing chat tests).

---

## 5. Whispers filters (All / Friends / Unread / Groups + custom)

File: `presentation/view/chat_list_page.dart` (717 lines).

Facts
- Entries: `_Entry(id, friend, [group])`: `group != null` → group row (`_GroupChatItem`);
  `friend != null` → friend row (`_ChatListItem`); else stranger (`_PeerChatItem`).
  `_byRecentActivity({friends, strangerIds, previews, myId, groups})` builds the sorted list.
- Unread: `roomPreviewsProvider` → `Map<String, RoomPreview>` with `.unread` (int)
  (`providers/local_db_providers.dart`). Room id for an entry: group → `entry.group!.roomId`;
  otherwise `ChatViewModel.buildRoomId(myId, entry.id)`.
- Layout: `Scaffold → SafeArea → Column[AnimatedSize(_SearchField), Expanded(body)]`.

Design
- New file `data/models/chat_filter.dart`:
  - `enum ChatFilterKind { all, friends, unread, groups, custom }`.
  - `class ChatFilter { String id; String name; ChatFilterKind kind; Set<String> roomIds; }`
    — built-ins are constants (`all`, `friends`, `unread`, `groups`); a **custom filter** is a
    user-named set of chats (room ids), created with the "+ Add filter" chip.
  - JSON (de)serialisation (`toJson/fromJson`) for custom ones.
- Persistence: add `chatFilters(String account)` / `saveChatFilters(String account, List<ChatFilter>)`
  to `data/local/local_cache.dart`, mirroring `roomWallpapers/saveRoomWallpapers`
  (key `cache.v1.<account>.chat_filters`, via the existing `_key/_read/_write` helpers).
- Provider `providers/chat_filter_providers.dart`:
  - `ChatFiltersNotifier extends Notifier<List<ChatFilter>>` (custom filters only; reads
    `currentAccountIdProvider` + `localCacheProvider`, like `WallpaperNotifier`), with
    `add(name, roomIds)`, `rename`, `remove`, `setRooms`.
  - `selectedChatFilterProvider` (Notifier<String> id, default `'all'`; session-only).
- UI: a horizontally scrolling chip row **between** the `AnimatedSize` search field and
  `Expanded(body)` in the Column. Chips: All, Friends, Unread (show count badge = number of
  rooms with unread>0), Groups, then custom filters, then a final **"+ Add filter"** chip.
  Selected chip uses the primary fill; others the `paperAlt` border style (see
  `utils/serafim_chip.dart`, reuse it).
- Add filter flow: bottom sheet → name field (max 20 chars) + multi-select list of existing
  chats (same entries as the list) → Save. Long-press a custom chip → Rename / Edit chats /
  Delete.
- Applying: filter the `_byRecentActivity(...)` result before the render loop:
  friends → `entry.friend != null`; groups → `entry.group != null`; unread →
  `previews[roomId]?.unread > 0`; custom → `roomIds.contains(roomId)`. Search text applies on top.
  `OfficialChatItem` is shown only under All.
- Empty states: e.g. "No unread chats." per filter.
- Eyebrow text ('CHAT'/'ALL CHATS') becomes the filter name.

Tests: pure function `applyChatFilter(entries, filter, previews, myId)`; persistence round trip;
widget test that tapping Unread hides read chats.

---

## 6. Posts: heading + content, images at the bottom as a scrollable row

Backend (do first)
1. `sql/015_post_title.sql`:
   `ALTER TABLE posts ADD COLUMN IF NOT EXISTS title VARCHAR(120);` (header comment style as in 014).
2. `app/models/post.py` `Post`: `title = Column(String(120), nullable=True)` after `content`.
3. `app/schemas/post.py`: `TITLE_MAX = 120`; `PostCreate.title: str = ""` (strip; reject
   > 120). In the existing `_something_to_post` validator require: **title non-empty**, and
   (content non-empty **or** at least one image). `PostOut.title: str | None = None`.
4. `app/api/posts.py`: `create_post` passes `title=body.title`; `_post_out` adds `title=post.title`.
   Old rows have `NULL` title and must keep working.
5. Tests in `tests/test_posts.py`: title required; title > 120 rejected; title returned in
   `PostOut`; existing helper `post(env, user, content, circle_id)` must send a title now
   (update helper to `{"title": "T", "content": ...}`) — update existing tests accordingly.

App
- `data/models/post.dart`: `Post.title` (`String?`, `json['title']`); `PostLimits.titleMax = 120`.
- `data/services/post_service.dart` `create(...)`: new `String title` param sent as `'title'`.
- `providers/post_providers.dart` `PostComposerController.post(...)`: pass `title`; also
  invalidate `authorPostsProvider` (profile lists currently don't refresh after posting).
- `presentation/view/composer_page.dart`: add a title `TextField` above the content field
  (own controller `_title`, `maxLength: PostLimits.titleMax`, hint "Heading", `autofocus: true`;
  remove autofocus from the content field). `_post()` rejects empty title ("Add a heading.").
  Content is optional only when images are attached.
- `presentation/view/widgets/post_card.dart`: render title above content
  (`AppTextStyles.fieldInput.copyWith(fontSize: 16, fontWeight: FontWeight.w700)`) when not null.
  The detail page uses the same card — no separate change.
- **Images at the bottom, scrollable row**: in `PostCard.build` move the `PostImages` block
  to AFTER the action row (spark/comment/footer). Rewrite `PostImages`
  (same file) to: one image → full width `AspectRatio(4/3)`; two or more →
  `SizedBox(height: 180, child: ListView.separated(scrollDirection: Axis.horizontal, ...))`
  with each tile width 180 (`CachedNetworkImage`, `BoxFit.cover`), 6px separators, tapping a
  tile opens the existing `_ImageViewer` at that index. Remove the `GridView`.

---

## 7. Delete post

Backend already supports it: `DELETE /posts/{id}` soft-deletes; allowed for the author, and
for a Circle Overseer/Owner on Circle posts; others get 403/404. Nothing to change there.

App
- New `PostDeleteController` (AsyncNotifier<void>) in `providers/post_providers.dart`: calls
  `postServiceProvider.delete(id)` (exists) then invalidates `feedProvider`,
  `authorPostsProvider` (family-wide), `circlePostsProvider` (family-wide), `postProvider`.
- In `PostCard` show a trailing overflow menu (`PopupMenuButton`, items: Delete) in the header
  row when `post.author.id == currentAccountIdProvider` OR a new param `canManage` is true.
  Tapping Delete shows a confirm dialog ("Delete this post? This can't be undone."), then calls
  the controller; on error show a SnackBar via `humanError`.
- `circle_detail_page.dart` `_OverseerActions` has its own delete icon without confirmation:
  keep pin there, remove its delete icon, and pass `canManage: circle.myRole?.canManage == true`
  to `PostCard` so there is one consistent delete flow.
- `post_detail_page.dart`: after a successful delete `Navigator.pop(context)`.

Tests: author sees the delete menu, a non-author doesn't; confirm dialog cancel does nothing;
provider invalidation (use the `_FakeService` pattern in `test/circles_followup_test.dart`).

---

## 8. Daily limit: max 8 image attachments per user per day

Rule: a user may attach at most **8 images per UTC day** across all posts (a post holds ≤ 4).
Deleting a post does NOT refund the quota.

Backend
- `app/core/posts.py`: `DAILY_IMAGES_MAX = 8` and
  `async def images_posted_today(db, user_id) -> int`: select `Post.image_urls` where
  `author_id == user_id` and `created_at >= start_of_utc_day` (do **not** filter `deleted_at`),
  return `sum(len(urls or []) for urls in rows)` (Python-side count keeps it portable across
  SQLite and Postgres JSONB). For SQLite compare with a naive datetime — copy the dialect
  trick used in `app/api/admin.py` `_since` (line ~71) / `app/api/groups.py` (~398).
- `create_post` (`app/api/posts.py`): after the URL-prefix check and before `db.add`, if
  `body.image_urls`: `used = images_posted_today(...)`; if `used + len(body.image_urls) >
  DAILY_IMAGES_MAX` → `HTTPException(429, f"You can share up to 8 pictures a day ({used} used). Try again tomorrow.")`.
- New `GET /posts/image-quota` → `{"used": int, "limit": 8}` (declare **before** `/{post_id}`
  routes so the path is not captured by the id route). Schema `ImageQuota` in `app/schemas/post.py`.
- Tests: 8 images across posts OK; the 9th → 429; a deleted post still counts; another user is
  unaffected; yesterday's posts (backdate via `env.engine_sync.begin()`) don't count;
  `/posts/image-quota` reports used.

App
- `data/services/post_service.dart`: `Future<ImageQuota> imageQuota()` (`GET /posts/image-quota`);
  model `ImageQuota { used, limit; remaining }` in `data/models/post.dart`.
- `composer_page.dart`: on opening (and after each successful post) fetch the quota
  (`FutureProvider.autoDispose` in `post_providers.dart`). Show "Pictures today: used/8".
  Cap `room` in `_addImages` at `min(PostLimits.imagesMax - _images.length, remaining -
  _images.length)`; when remaining is 0 disable the button with the text "Daily picture limit
  reached". This also prevents **orphaned uploads** (images are uploaded to storage before
  the POST; a 429 afterward would leave files behind).
- If a 429 still arrives, show the server message in `_error` (verify `ApiException.fromDio`
  in `core/network/api_exception.dart` surfaces `detail` for 429; add a case if not).

---

## 9. Auto-open keyboard on comment / reply (posts)

`presentation/view/post_detail_page.dart` has no FocusNode today.
- Add `final _focus = FocusNode();` (dispose it) and pass `focusNode: _focus` to the comment `TextField`.
- Reply: in `_thread`'s `onReply`, `setState(() => _replyTo = c); _focus.requestFocus();`.
- Comment icon: `openPost(BuildContext, String postId)` (top of the file) gets
  `{bool focusComment = false}`; `PostDetailPage` gets `final bool focusComment`. On the
  comment `TextField` set `autofocus: widget.focusComment` (the field is built only after the
  post loads, so `autofocus` is the reliable trigger; do not request focus in `initState`).
- Update the comment-icon callers to `openPost(context, post.id, focusComment: true)`:
  `feed_page.dart`, `widgets/profile_posts.dart`, `post_list_page.dart`,
  `circle_detail_page.dart` (~302). Tapping the card body keeps `focusComment: false`.
- On the detail page itself pass `onComment: () => _focus.requestFocus()` to its `PostCard`
  (today the comment icon there does nothing).
- Test: widget test — tapping the comment icon pushes a page whose TextField has focus.

---

## Suggested order
1. Backend: 015 title + quota (+ tests, deploy notes).  2. Posts app side (§6, §7, §8, §9).
3. Chat quick wins (§3).  4. Whispers filters (§5).  5. Forwarding (§4).
6. Wallpaper opacity (§2).  7. Image editor (§1).

## Deploy notes for the owner
- Run `sql/015_post_title.sql` on the database and redeploy the backend (title + quota).
- No Supabase storage changes beyond the `post-images` bucket already set up.
- Forwarding, filters, editor, wallpaper opacity are app-only.

## Definition of done (every feature)
`flutter analyze` shows no new errors/warnings in touched files; `flutter test` green; new
tests added where listed; backend `pytest` green; manual check on a device for §1, §2, §4.
