# Rabbit Hole — Effort Thinking Mode

A persistent toggle that prepends a system prompt instructing the model to think
more deeply, validate assumptions with tools (adb, xcode, tests, debugging), and
focus on testable code with good coverage.

## Implementation

### Persistence — `lib/core/storage/settings_store.dart`
- `loadRabbitHole() → Future<bool>` (default `false`)
- `saveRabbitHole(bool value) → Future<void>`
- Key: `opencode_rabbit_hole`

### API — `lib/core/api/opencode_client.dart`
- Added `String? system` param to `sendPromptAsync()`
- Forwarded as `system` field in the POST body (supported by `/session/:id/prompt_async`)

### Provider + system prompt — `lib/features/chat/chat_provider.dart`
- `RabbitHoleNotifier` (StateNotifier<bool>) loads from SettingsStore on init
- `rabbitHoleProvider` — global Riverpod provider
- `ChatController.send()` reads the toggle and passes `_rabbitHolePrompt` when enabled

### Composer chip — `lib/features/chat/chat_screen.dart`
- Brain icon chip in the composer toolbar, between tools button and model chip
- Active: primary color tint + "deep" label. Inactive: muted icon only
- Taps `rabbitHoleProvider.notifier.toggle()`
- Persists across sessions and app restarts

### System prompt
```
Before answering, think deeply and thoroughly about the problem. Do not assume
— validate your reasoning by using the available tools:

- Run tests to confirm your changes work
- Use debugging tools (adb, xcodebuild, etc.) to inspect runtime state
- Check for edge cases and error paths
- Verify assumptions against the actual codebase, not memory

Write testable code with good coverage. Prefer correctness over speed.
```

### Offline behavior
Queued messages (offline → online drain) use the rabbit hole state at drain time,
not at enqueue time. Acceptable trade-off since the toggle persists globally.
