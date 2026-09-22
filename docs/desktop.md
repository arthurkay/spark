# Desktop app

On Windows, macOS, and Linux, Spark adapts to the bigger screen instead of
stretching the phone UI. The mobile layout is kept for narrow windows (under
1024 px wide); everything below activates at 1024 px and up.

## App shell

All content routes render inside `DesktopShell` (`lib/app/desktop_shell.dart`),
a `ShellRoute` wrapper that pairs a 260 px sidebar with the current page:

- **Projects / Settings** navigation with the active route highlighted.
- **Session list grouped by project**, collapsed by default. Each project header
  shows a session count and expands on tap; the group holding the currently open
  session auto-expands (an explicit collapse wins).
- Busy sessions show a highlighted icon; tapping a session pushes it.
- A **New session** button in the footer.
- The sidebar is hidden when no servers are configured (Welcome stays
  full-screen) and on the voice-mode screen (full-screen).

## Chat on desktop

- Transcript and composer widen from 760 px to 960 px.
- The AppBar shows inline actions — Files, Workspace, Terminal, Models, Agents,
  and the auto-allow toggle (highlighted when on) — instead of hiding everything
  behind the ⋮ menu. The menu itself stays available.
- The back button falls back to the project list when there is nothing to pop
  (sidebar `go()` navigation leaves no stack).
- **Enter sends** the composer input; **Shift+Enter** inserts a newline
  (mobile keeps the send-button flow).

## Workspace (IDE)

`WorkspaceScreen` (`lib/features/workspace/`) is desktop-only: it is hidden
from the mobile chat menu, and the `/session/:id/workspace` route redirects to
the chat on mobile. Open it from the chat toolbar. The app sidebar steps aside
while workspace is open so the file tree gets the full width.

- **File tree** (260 px, collapsible via the toolbar or Ctrl/⌘+B): project files
  with per-directory expansion, a **search field** filtering the whole project
  (fuzzy, lazily indexed on first keystroke), skeleton placeholders while
  loading, and scrolling for long listings. Toggle with Ctrl/⌘+B.
- **Tabbed editor**: syntax-highlighted editing with line numbers, multi-tab
  strip (double-tap a tab to close), and **in-file find** (Ctrl/⌘+F) with a match
  counter and prev/next navigation.
- **Quick-open** (Ctrl/⌘+P): fuzzy file jump across the project.
- **Dirty tracking**: edits mark a tab dirty (dot in the strip). Closing a dirty
  tab asks to Save / Discard / Cancel; clean tabs close immediately. Dirty
  comparison ignores line-ending differences (the editor normalizes CRLF→LF).
- **Auto-save** (Settings → Workspace, **on by default**): saves a dirty file
  silently 2 s after you stop typing. Manual save (Ctrl/⌘+S, save button) still
  toasts; failures always toast.
- **Embedded chat** (≥ 1280 px): the session chat docks on the right; on smaller
  widths the chat action returns to the full chat screen.
- Files are written through the server PTY (`PtyFileWriter`).

### Known constraints

- Riverpod 3 forbids mutating providers during widget lifecycles, so session
  setup and tree expansion are deferred out of `initState`.
- `EditorPane` is keyed by path *and* loading state so the editor controller is
  rebuilt with real content once a file finishes loading.

## Local server

On desktop the app can run its own `opencode serve` (`lib/features/local_server/`):

- One-click install (`curl -fsSL https://opencode.ai/install | bash` on
  Unix, npm on Windows) and upgrade, log viewer, free-port selection, health
  monitoring, and automatic shutdown when the app detaches.
- Manage it from Settings → Local server; switch between local and remote
  servers from the project list like any other connection.

## Window restore

`lib/app/window_bounds.dart` (via `window_manager`) restores the window's
position and size before first show and persists them — debounced on move/resize
plus a best-effort save on close — in SharedPreferences
(`opencode_window_bounds`). First launch defaults to 1280×800 centered, with a
360×520 minimum size.
