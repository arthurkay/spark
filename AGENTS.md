# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

**Spark** — a Flutter mobile app (Android/iOS) that acts as a remote client for a
running `opencode serve` HTTP server. The app's UI branding refers to the backend
as **SparkCode** (e.g. placeholders, headers, notifications). Under the hood it is
still the opencode server API. Spark lets users browse sessions, chat with the AI
(with live streaming), approve permission requests, pick models/agents, and browse
project files and diffs.

- App display name: **Spark** (`android:label`, `ShadcnApp.title`).
- UI library: **shadcn_flutter** (New York theme, zinc `#18181b` bg, cyan `#38bdf8`
  accent, no Material/Cupertino).
- State management: **flutter_riverpod**.
- Networking: **dio** (REST) + manual SSE parsing for the `/event` stream.
- Routing: **go_router**.
- Serialization: hand-written `fromJson`/`toJson` on model classes (build_runner
  is incompatible with the installed Dart 3.10 toolchain, so no codegen).
- Storage: **flutter_secure_storage** (server password) + **shared_preferences**
  (host/port, workspace selection, theme, collapse preference).
- Branding note: the opencode server API username (`opencode`) and the internal
  Dart identifiers (`opencodeClientProvider`, `OpencodeClient`, SharedPreferences
  keys `opencode_*`) are **real server API values** and must NOT be renamed to
  `spark`/`sparkcode` — doing so breaks auth and persistence. Only user-facing
  strings should say "SparkCode".

## Commands

```bash
# Install dependencies
flutter pub get

# Static analysis (ALWAYS run before considering a task done)
flutter analyze

# Format code (ALWAYS run before considering a task done)
dart format .

# Run tests
flutter test

# Run the app (needs a device/emulator)
flutter run
```

## opencode server API

The app talks to the opencode server documented at https://opencode.ai/docs/server/.
Start a server for manual testing with:

```bash
opencode serve --port 4096
# with auth:
OPENCODE_SERVER_PASSWORD=secret opencode serve --port 4096
```

Key endpoints used:

- `GET /global/health` — health check on connect.
- `GET /event` — SSE stream; primary source of real-time updates.
- `GET/POST/DELETE /session`, `GET /session/status` — sessions.
  - `?directory=<worktree>` query param scopes the session list to a project.
  - `POST /session?directory=<worktree>` creates a session rooted at a project.
- `GET /session/:id` — single session (used to resolve its `directory`).
- `GET /session/:id/message`, `POST /session/:id/prompt_async` — messages.
- `POST /session/:id/permissions/:permissionID` — respond to permission requests.
- `GET /config/providers`, `GET /agent` — model + agent lists.
- `GET /project`, `GET /project/current` — workspaces/projects
  (`id`, `worktree`, `vcs`).
- `GET /file?path=&directory=`, `GET /file/content?path=&directory=` — project-
  scoped file browsing/diff. `directory` scopes paths to the project worktree.
- `GET /session/:id/diff` — diffs.

Note: a `directory` query param (not a body field) scopes sessions, files, and
file content to a project worktree. This is how the app keeps a session's file
browser limited to that project.

Session listing gotcha: a bare `GET /session` (no `directory`) only returns
global/unscoped sessions — sessions created with `?directory=<worktree>` are
scoped to that worktree and will NOT appear in the unscoped list. So
`allSessionsProvider` (`lib/features/sessions/sessions_provider.dart`) fetches the
unscoped list AND one `GET /session?directory=<worktree>` per known project, then
merges + dedupes by session id. This ensures sessions created from the app remain
visible after navigating away.

Auth: optional HTTP Basic auth. Username defaults to `opencode`
(`OPENCODE_SERVER_USERNAME`), password from `OPENCODE_SERVER_PASSWORD`.

### SSE event types (`GET /event`)

The `/event` stream emits `GlobalEvent` objects (`{ directory, payload }`) whose
`payload` is a discriminated union on `type`. Event types the app cares about:

- `permission.asked` — a new permission request. `payload.properties`
  is `{ id, sessionID, permission, patterns[], metadata, always[],
  tool: { messageID, callID } }`. The `permission` field is the action
  string (e.g. `bash`, `edit`); `patterns` lists the affected paths.
  There is also a newer `permission.v2.asked` whose properties are
  `{ id, sessionID, action, resources[], save[], metadata, source }`.
- `permission.replied` — a permission was answered. `payload.properties`
  is `{ sessionID, requestID, reply }` where `reply` ∈ `once`/`always`/
  `reject`. Note the event key is `requestID` (not `permissionID`) and
  the answer field is `reply` (not `response`). `permission.v2.replied`
  mirrors this with a `reply` object.
- `message.updated` / `message.removed` — message create/update/delete.
- `message.part.updated` / `message.part.removed` — streaming message parts
  (text/reasoning/tool/file/etc.); `message.part.updated` may carry a `delta`.
- `session.created` / `session.updated` / `session.deleted` — session lifecycle.
- `session.status` — `idle` | `retry` | `busy`.
- `session.idle` / `session.compacted` / `session.diff` / `session.error`.
- `file.edited` / `file.watcher.updated` (`add` | `change` | `unlink`).
- `todo.updated`, `command.executed`, `vcs.branch.updated`.
- `server.connected`, `server.instance.disposed`.
- `installation.updated`, `installation.update-available`.
- `lsp.updated`, `lsp.client.diagnostics`.
- `pty.*` and `tui.*` events are TUI/terminal-specific (unused by the app).

Full type source: `packages/sdk/js/src/gen/types.gen.ts` (`Event` union) in the
`anomalyco/opencode` repo.

### Permission response API

Respond to a `permission.asked` request with:

```
POST /session/:id/permissions/:permissionID
```

The `:permissionID` is the `Permission.id` from the `permission.asked` event.
The body carries the `response` string (e.g. `once` / `always` / `reject`),
mirrored back on the `permission.replied` event as `{ sessionID, requestID,
reply }`. The app models the request as `PermissionRequest` in
`lib/core/models/permission.dart`.

### Questions (separate from permissions)

Questions are a **distinct** API from permissions. They represent prompts the
agent asks the user to choose among options (or provide free text). The app does
NOT treat questions as permissions — it polls and renders them separately.

- `GET /question` — returns the list of pending `QuestionRequest` objects
  (`id` prefixed `que_…`, `sessionID`, `questions[]`, `tool: { messageID,
  callID }`). Each question has `question`, `header`, `options[]` (each
  `{ label, description }`), `multiple` (bool), and `custom` (bool for free
  text). The app keys pending questions by `messageID`/`callID` so a tool chip
  can look up its matching request.
- `POST /question/:requestID/reply` — body `{ "answers": [[label], ...] }`
  (an array of label-arrays, one per question; for single-select, each inner
  array has one label). For free-text (`custom`) questions the answer is the
  typed string.
- `POST /question/:requestID/reject` — dismiss/reject the request.

The app models these as `QuestionRequest` (`lib/core/models/question.dart`),
fetches via `OpencodeClient.listQuestions()` / `replyQuestion()` /
`rejectQuestion()`, and tracks them in `pendingQuestionsProvider`
(`lib/core/api/question_provider.dart`). `QuestionListenerController` polls
`GET /question` every 8s and also refreshes on `question.*` SSE events and
`server.reconnected`. The tool chip's question sheet (`_QuestionSheetBody` in
`lib/features/chat/message_bubble.dart`) looks up the pending request by
`messageID`/`callID`, renders selectable option chips (single vs multi per
`multiple`), and submits via `replyQuestion`. It resolves the `requestID` **live**
from `pendingQuestionsProvider` at submit time (via `messageKey`/`callKey`) so a
question that was populated after the sheet opened still submits — do NOT rely only
on the `requestID` captured when the sheet was built (it may be empty).

## Conventions

- Do NOT add code comments unless explicitly requested.
- Prefer shadcn_flutter widgets (`ShadcnApp`, `Button`, `Card`, `Input`,
  `TextArea`, `Select`, `Sheet`, `Badge`, etc.). Do not import `package:flutter/material.dart`
  for UI unless a specific primitive is unavailable.
- Feature-first folder layout under `lib/features/<feature>/`; shared code under
  `lib/core/` and `lib/shared/`.
- Riverpod providers live next to the feature they serve.
- Models use hand-written `fromJson`/`toJson`; there is no code generation.
- Chat text is rendered with `lib/shared/widgets/markdown_view.dart` (pure-Dart
  `markdown` package → AST → shadcn/flutter widgets). Fenced code blocks and
  inline `code` are routed to `CodeHighlightView` (`re_highlight`). Markdown
  parse results are cached by source string in a module-level map. Do NOT import
  `package:flutter/material.dart` inside `markdown_view.dart` (it conflicts with
  shadcn's `Column`/`Row`/`Table`); it intentionally imports only
  `package:flutter/widgets.dart`.
- Tool-call chips in `lib/features/chat/message_bubble.dart`: `_expandableToolTypes`
  lists tools whose content expands inline (`glob`, `read`, `edit`, `todowrite`,
  `write`, `bash`, `grep`). `_buildContentPreview` renders a structured widget per
  tool — `todowrite` parses its JSON payload into a checkbox/todo list
  (`_TodoRow` + `_TodoPriorityBadge`); `grep` shows Pattern/Path/Results; `bash`
  shows Command + Output. Content blocks use `ConstrainedBox` + `SingleChildScrollView`
  so short content (e.g. a single command or filename) stays minimal height while
  long output scrolls within a cap. Do NOT give `_codeBlock`/`_diffBlock` a fixed
  height or rely on `SelectableText.maxLines` for sizing (reserves full height).
- **edit tool chips** render a single interleaved unified diff (green `+` / red `-`
  lines via `CodeHighlightView(language: 'diff')`) under a "Diff" label, instead of
  two separate Removed/Added blocks. The diff is computed by `_unifiedEditDiff()`
  (LCS-based, in `message_bubble.dart`) from the tool's `oldString`/`newString`.
  When only one side exists it falls back to the single colored block.
- **App + notification icons** are generated, not codegen'd. Run
  `python3 tools/generate_icons.py` (Pillow only) to (re)write
  `android/app/src/main/res/mipmap-*/ic_launcher.png` (color launcher, zinc rounded
  square + cyan sparkle — matches the `LucideIcons.sparkles` AI chat avatar) and
  `ic_notification.png` (monochrome white sparkle for the status bar). The
  notification small icon is referenced in `lib/core/notifications/notification_service.dart`
  via `@mipmap/ic_notification`. Do NOT use `flutter_launcher_icons` — it is not wired
  up and would overwrite these hand-generated assets. Keep the launcher glyph in sync
  with the chat AI avatar if that icon changes.

## Chat working state

- `ChatController` (`lib/features/chat/chat_provider.dart`) drives the "working"
  indicator. On `send()` it sets `_optimisticBusy = true` and marks the session busy;
  it is cleared when `session.idle` / `session.status` idle / `idle` / `step-finish` /
  `session.error` SSE events arrive, OR when a `load()` observes the conversation tail
  is no longer an in-progress assistant message (robust against missing idle events).
- `_deriveWorking()` treats the session as busy ONLY when the **last message** is an
  assistant message with no `timeCompleted`. A stale incomplete assistant message left
  by an interrupted turn (server restarted mid-generation) must NOT keep "working" on
  once a newer message follows it.
- On a failed `send()` the error is surfaced in the composer (red banner) and the
  **Abort session** action is shown so a stuck/busy session can be recovered via
  `controller.abort()`.
- `abort()` calls `POST /session/:id/abort` then keeps `_aborting = true` until a
  `session.idle` / `session.status` idle event arrives (via `_clearAbort()`), OR a
  15-second `_abortTimer` fires as a fallback. This prevents subsequent
  `session.status` busy events from re-enabling "working" before the server
  confirms the session actually stopped. On `server.reconnected`,
  `_verifySessionStatus()` auto-aborts if the conversation tail is a stale
  incomplete assistant message.

## Layout

```
lib/
  main.dart              # ShadcnApp root, theme, router, app-lifecycle refresh
  app/                   # router, theme
  core/
    api/                 # opencode_client, sse_client, endpoints, providers
    models/              # data models (hand-written fromJson/toJson)
    notifications/       # local notification service (permission alerts)
    storage/             # connection + settings persistence
  features/
    connection/          # server setup, connection state, settings screen
    sessions/            # sessions list, project grouping, workspace selection
    chat/                # message thread + composer + streaming + tool chips
    permissions/         # permission approval (banner + sheet)
    models/              # model + agent selector
    files/               # file browser + diff viewer
  shared/widgets/        # reusable widgets (markdown, code highlight, sheets)
```
