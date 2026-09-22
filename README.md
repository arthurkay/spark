# Spark

**Spark** is a Flutter client for a running [`opencode serve`](https://opencode.ai/docs/server/)
HTTP server — on your phone (Android/iOS) and on your desktop (Windows/macOS/Linux).
Browse sessions, chat with the AI with live streaming, approve permission requests,
pick models/agents, browse project files and diffs, use a full terminal, and on
desktop work in a full IDE-style workspace with a local embedded server.

In the UI the backend is branded as **SparkCode**, but underneath it is still the
standard opencode server API.

## Features

- Connect to one or more opencode servers (host/port, optional HTTP Basic auth).
- Session list grouped by project/worktree, with search and active/idle filters.
- Chat thread with live streaming of text, reasoning, and tool calls.
- Tool-call chips that expand inline to show structured content:
  - `todowrite` → checklist with status icons and priority badges.
  - `bash` → command + output; `grep` → pattern/path/results.
  - `read` / `edit` / `write` / `glob` → file paths and diffs.
- Permission approval banner + sheet; optional auto-approve toggle.
- Agent questions (option pickers) rendered inline, separate from permissions.
- Model and agent pickers sourced from the server config.
- Project-scoped file browser and diff viewer.
- Full terminal with PTY support, keyboard toolbar (arrows, Tab, Ctrl, Esc).
- Read aloud: on-device text-to-speech with an LLM speech rewrite (uses your
  chat's selected model), per-message cache, selectable system voices, seek bar,
  and a mini player that keeps playing while you navigate.
- Voice conversation mode: listen, send, and hear the reply with a live transcript.
- Export replies as PDF documents.
- Offline support: cached sessions stay readable; outgoing messages queue until
  the server is reachable again.
- Local notifications for incoming permission requests.

### Desktop only

- IDE-style shell: navigation sidebar with collapsible per-project session lists
  (windows ≥ 1024 px wide; narrower windows use the mobile layout).
- Workspace: file tree with search, tabbed editor with syntax highlighting,
  in-file find (Ctrl/⌘+F), quick-open (Ctrl/⌘+P), and auto-save (on by default,
  toggleable in Settings → Workspace).
- Embedded local `opencode serve` process with one-click install/upgrade.
- Window position and size restored across restarts.
- Enter sends, Shift+Enter inserts a newline in the composer.

## Getting Started

You need the [Flutter SDK](https://docs.flutter.dev/) (Dart 3.10 toolchain).

```bash
# Install dependencies
flutter pub get

# Static analysis (always run before considering work done)
flutter analyze

# Format code (always run before considering work done)
dart format .

# Run the tests
flutter test

# Run the app (needs a device/emulator; use -d for a target)
flutter run
flutter run -d linux
```

## Connecting to an opencode server

Start a server for manual testing:

```bash
opencode serve --port 4096
# with auth:
OPENCODE_SERVER_PASSWORD=secret opencode serve --port 4096
```

Then in Spark, open the connection screen (menu → settings) and add a server
pointing at `http://<host>:4096`. The server's default auth username is
`opencode`; the password is the one you set above. See
[docs/server-setup.md](docs/server-setup.md) for running the server headless
under systemd, and [docs/desktop.md](docs/desktop.md) for the embedded local
server on desktop.

## Branding note

The app is named **Spark** and labels the backend **SparkCode** in user-facing
strings. Internal identifiers tied to the opencode API (`opencodeClientProvider`,
`OpencodeClient`, the `opencode_*` SharedPreferences keys, the default `opencode`
auth username) must **not** be renamed — they are real server API values and
renaming them breaks auth/persistence.

## Project layout

```
lib/
  main.dart              # ShadcnApp root, theme, router, app-lifecycle refresh
  app/                   # router, theme, desktop shell, window bounds, motion
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
    terminal/            # PTY terminal + toolbar
    workspace/           # IDE: file tree, tabbed editor, quick-open (desktop)
    local_server/        # embedded opencode binary manager (desktop)
  shared/widgets/        # reusable widgets (markdown, code highlight, sheets)
```

State is managed with **flutter_riverpod**; UI uses **shadcn_flutter** (New York
theme, zinc background, cyan accent); networking is **dio** (REST) plus a
hand-parsed SSE stream for `/event`.

## Docs

| Doc | Contents |
|-----|----------|
| [docs/desktop.md](docs/desktop.md) | Desktop shell, workspace IDE, local server, window restore |
| [docs/tts-voice.md](docs/tts-voice.md) | Read-aloud narration and voice conversation mode |
| [docs/server-setup.md](docs/server-setup.md) | Running the opencode backend (systemd, TLS, firewall) |
| [docs/deployment.md](docs/deployment.md) | Store releases via tags + Codemagic |
| [docs/privacy_policy.md](docs/privacy_policy.md) | Privacy policy |
| [docs/plan/](docs/plan/) | Archived feature plans (historical) |
| [store/](store/play-listing-en-US.md) | Play Store listing text |
| [AGENTS.md](AGENTS.md) | Agent/contributor conventions for this repo |
