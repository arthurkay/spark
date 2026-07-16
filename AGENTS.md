# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

`opencode_companion` — a Flutter mobile app (Android/iOS) that acts as a remote
client for a running `opencode serve` HTTP server. It lets users browse sessions,
chat with the AI (with live streaming), approve permission requests, pick
models/agents, and browse project files and diffs.

- UI library: **shadcn_flutter** (New York theme, no Material/Cupertino).
- State management: **flutter_riverpod**.
- Networking: **dio** (REST) + manual SSE parsing for the `/event` stream.
- Routing: **go_router**.
- Serialization: hand-written `fromJson`/`toJson` on model classes (build_runner
  is incompatible with the installed Dart 3.10 toolchain, so no codegen).
- Storage: **flutter_secure_storage** (server password) + **shared_preferences** (host/port).

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

Auth: optional HTTP Basic auth. Username defaults to `opencode`
(`OPENCODE_SERVER_USERNAME`), password from `OPENCODE_SERVER_PASSWORD`.

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

## Layout

```
lib/
  main.dart              # ShadcnApp root, theme, router
  app/                   # router, theme
  core/
    api/                 # opencode_client, sse_client, endpoints
    models/              # data models (json_serializable)
    storage/             # connection persistence
  features/
    connection/          # server setup + connection state
    sessions/            # sessions list
    chat/                # message thread + composer + streaming
    permissions/         # permission approval
    models/              # model + agent selector
    files/               # file browser + diff viewer
  shared/widgets/        # reusable widgets
```
