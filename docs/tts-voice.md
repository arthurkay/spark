# Read-aloud & voice mode

## Read aloud

Any assistant message can be narrated via the speaker action on its bubble
(`lib/features/chat/tts_provider.dart`):

1. **Preprocess** — markdown is stripped to speakable prose locally
   (`_preprocessForSpeech`).
2. **LLM rewrite** (long texts only) — the text is sent to a hidden
   `[TTS Preprocessing]` session that rewrites it for natural narration
   (flowing prose, spoken equivalents for code/links, natural cadence). The
   rewrite uses **your chat's selected model** — the same `selectedModelProvider`
   value a chat send would use — and the result is cached per message
   (`NarrationCache`), so replays are instant.
3. **Speech** — on-device `flutter_tts` speaks the text in chunks (bounded for
   Android's utterance limit), with word-level progress driving the seek bar.

Playback controls live in the mini player overlay: play/pause, seek, speed
(`_ttsVoiceTest` stops cover the size stepping), and the player keeps narrating
across navigation. Aborting a session or sending a new message stops narration
immediately.

## Voices

Settings → Narration lists the engine voices reported by the OS
(`parseVoices`: skips nameless entries, dedupes, sorts by locale then name).
Tapping a voice previews it without changing the saved choice; selecting persists
`opencode_tts_voice_name` / `opencode_tts_voice_locale` in SharedPreferences
(falling back to the engine default when cleared). The narration cache can be
cleared from the same screen.

Desktop note: Linux has no `flutter_tts` plugin implementation — TTS calls are
guarded (`try/catch` around `stop()`/`dispose()`) so the app runs unaffected.

## Voice conversation mode

`VoiceModeScreen` (`/session/:id/voice`, full-screen, outside the desktop
shell) is a push-to-talk loop:

- Mic button records via `speech_to_text` (mobile only — no desktop
  implementation, so the mic stays disabled there); the transcript is sent with
  the session's selected model and agent.
- While the model streams, short filler phrases voice its thinking; completed
  replies are narrated through the same pipeline as Read Aloud (preprocess +
  cached rewrite + selected voice) with a live word-ticking transcript.
- When narration ends, listening resumes automatically. Tapping the mic while
  speaking interrupts and listens immediately; closing the screen aborts the
  session turn.

## Privacy

Speech synthesis and recognition are OS services governed by the device
vendor's policy (see [privacy_policy.md](privacy_policy.md)). The only network
call TTS makes is the rewrite round-trip to **your own configured server**;
narration caches stay on-device.
