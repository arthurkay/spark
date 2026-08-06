# Spark

**Spark** is a Flutter mobile app (Android/iOS) that acts as a remote client for a
running [`opencode serve`](https://opencode.ai/docs/server/) HTTP server. From your
phone you can browse sessions, chat with the AI (with live streaming), approve
permission requests, switch models/agents, browse project files and diffs, and
even access a full terminal.

In the UI the backend is branded as **SparkCode**, but underneath it is still the
standard opencode server API.

---

## Showcase

<div align="center">

### Chat with your AI, from anywhere

Live streaming responses, inline tool calls, diffs, and reasoning — all in a clean,
native mobile interface.

![Chat](screenshots/chat.jpeg)

</div>

---

<div align="center">

### Your projects, organized

Browse workspaces grouped by project, search across sessions, and filter by activity.
Jump into any session with a single tap.

![Home](screenshots/home.jpeg)

</div>

---

<div align="center">

### Terminal at your fingertips

Full PTY support with a custom keyboard toolbar — arrow keys, Tab, Ctrl, Esc.
Run commands on your server from your phone.

![Terminal](screenshots/terminal.jpeg)

</div>

---

## Features

| Capability | Details |
|------------|---------|
| **Multi-server** | Connect to one or more opencode servers with optional HTTP Basic auth |
| **Session management** | Grouped by project/worktree, with search and active/idle filters |
| **Live chat** | Streaming text, reasoning, and tool calls in real time |
| **Tool chips** | Expand inline to show `todowrite` checklists, `bash` output, `grep` results, `edit` diffs |
| **Permissions** | Approve or reject server requests via banner + sheet |
| **Models & agents** | Pick from server-configured models and agents |
| **File browser** | Project-scoped file tree and diff viewer |
| **Terminal** | Full PTY with keyboard toolbar (arrows, Tab, Ctrl, Esc) |
| **Notifications** | Local alerts for incoming permission requests |

## Getting Started

This is a Flutter project. You will need the [Flutter SDK](https://docs.flutter.dev/)
(uses the bundled Dart 3.12 toolchain).

```bash
# Install dependencies
flutter pub get

# Static analysis (always run before a commit)
flutter analyze

# Format code
dart format .

# Run the app (needs a device/emulator)
flutter run
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
`opencode`; the password is the one you set above.

## Branding note

The app is named **Spark** and labels the backend **SparkCode** in user-facing
strings. Internal identifiers tied to the opencode API (`opencodeClientProvider`,
`OpencodeClient`, the `opencode_*` SharedPreferences keys, the default `opencode`
auth username) must **not** be renamed — they are real server API values and
renaming them breaks auth/persistence.

## Project layout

```
lib/
  main.dart              # ShadcnApp root, theme, router, lifecycle refresh
  app/                   # router, theme
  core/                  # api, models, notifications, storage
  features/              # connection, sessions, chat, permissions, models, files, terminal
  shared/widgets/        # markdown, code highlight, sheet helpers
```

State is managed with **flutter_riverpod**; UI uses **shadcn_flutter** (New York
theme, zinc background, cyan accent); networking is **dio** (REST) plus a
hand-parsed SSE stream for `/event`.
