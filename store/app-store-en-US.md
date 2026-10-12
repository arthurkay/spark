# App Store listing — en-US

## App name

SparkCode

## Subtitle (max 30 chars)

Remote control for your AI coder

## Keywords (max 100 chars, comma-separated)

ai,coding,agent,terminal,code,diff,voice,opencode,developer

<!-- Do NOT put "OpenCode", model names, or superlatives in the name/subtitle.
     "SparkCode" matches the in-app branding. -->

## Description (max 4000 chars)

SparkCode turns your phone into a remote control for an AI coding agent
running on your own computer.

You run the open-source opencode server on a machine you control; SparkCode
connects to it over your network, so you can supervise and direct coding work
away from your desk.

WHAT YOU CAN DO

• Chat with the coding agent with live streaming replies, including its
  step-by-step reasoning and each tool it uses.
• Approve or reject the agent's permission requests (file edits, shell
  commands) directly from a notification.
• Browse projects and sessions grouped by workspace, with search and
  active/idle filters.
• Review code with a file browser, syntax highlighting, and diffs of the
  agent's edits.
• Create, rename, and delete files and folders on the connected machine.
• Use a full terminal with arrow keys, Tab, Ctrl, and Esc.
• Talk instead of typing: voice conversation mode listens, sends, and reads
  the reply back with a live transcript.
• Read any reply aloud with selectable system voices, a seek bar, and a mini
  player that keeps playing while you navigate.
• Export replies as PDF documents.
• Keep working offline: previously loaded sessions and chats stay readable
  without a connection, and messages you send are queued until the server is
  reachable again.

WHAT YOU NEED

SparkCode is a client app only — it does not include an AI model and cannot
work standalone. It requires the address of a running opencode server (an
independent open-source project) on a machine you control, with optional
HTTP Basic authentication.

SparkCode is an independent project and is not affiliated with or endorsed by
opencode or any AI model provider.

## Age rating (answers for the questionnaire)

- Unrestricted web access: NO (connects only to servers the user configures).
- User-generated content / messaging with strangers: NO (single-user client
  for the user's own server; no accounts, no social features).
- Expected rating: **4+**.

## Export compliance

`ITSAppUsesNonExemptEncryption = false` is set in `ios/Runner/Info.plist`.
The app uses only standard TLS networking to user-configured servers — no
proprietary encryption.

## Privacy nutrition (App Privacy)

- Microphone — voice dictation and voice conversation mode only; audio is
  sent to the user's own configured server, never to the developer.
- No data collected by the developer. No tracking. No third-party SDKs.
- Privacy policy: https://spark.cloud.co.zm/privacy_policy.html

## Review notes (App Review)

The app cannot do anything without a server connection — attach the same
demo-server address, credentials, and connect steps as for Play review, and
keep that server up during review. Otherwise the reviewer lands on the
welcome screen with no way to evaluate the app.

## Pre-submission checklist (App Store Connect)

- [ ] Screenshots: 6.7" + 6.5" required (generated via
      `python3 tools/generate_store_assets.py`); refresh the chat set from
      `docs/screenshots/chat-following.jpeg` / `chat-resume.jpeg` so the
      listing shows the current UI.
- [ ] Privacy policy URL set (required with microphone usage).
- [ ] Export compliance resolves automatically via the plist key.
- [ ] Age rating questionnaire answered (expect 4+).
- [ ] Review notes include live demo-server credentials.
