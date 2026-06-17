# Changelog

All notable changes to Earwig are documented here. Versions follow the `VERSION` file
(marketing version); the build number is the git commit count.

## 0.5 — 2026-06-17

- **Search & Ask** — search across every meeting, a ⌘K spotlight to open any of them, and an
  "Ask your meetings" mode that answers natural-language questions from your transcripts with
  clickable source citations.
- **Claude engine** — Claude joins on-device Ollama and Apple Intelligence as an optional summary
  engine (your own Anthropic key, stored on disk, opt-in and disclosed).
- **Better local summaries** — the default Ollama model is now Qwen2.5 14B (much closer to cloud
  quality); older weak tags upgrade automatically.
- **Faster transcription** — switched Whisper to the large-v3 turbo build for noticeably lower CPU.
- **Notes** — a per-meeting notes tab, autosaved and folded into the summary on regenerate.
- **Feedback & delete** — send feedback from the app, and permanently delete meetings.
- **Live CPU meter** in the sidebar, a new purple/white app icon, and broad UI + performance work
  (search no longer re-tokenises per keystroke, the spotlight loads off the main thread, the
  sidebar equaliser only animates while active).

## 0.2.0 — 2026-06-16

- **Help** and **About** moved out of Settings into the sidebar; About shows the app version +
  build number, in-app release notes, and the privacy statement.
- Added a "How to use Earwig" guide.

## 0.1.0 — 2026-06-16

First shareable build.

- **Summaries** run on-device via **Ollama** (default; install + pull a model) or **Apple
  Intelligence** (macOS 26) — chosen in Settings → Summary. The previous embedded MLX/Qwen
  engine was removed.
- **Light, glossy UI** — white surfaces, indigo→purple gradient actions, bigger type, generous
  spacing; day-grouped meetings, content-on-cards detail.
- **Reliable summaries** — the Ollama context window is sized to the transcript (long meetings no
  longer return empty output), generation retries on a bad parse, and a back-fill summarises past
  meetings that have none (with a visible "couldn't generate / try again" state).
- **Speakers** — name a speaker once and Earwig recognises them in future meetings; the name sheet
  now lists already-enrolled people to assign in one tap.
- **Detection** — modern, ClearRoute-branded "Meeting detected" prompt for Teams / Slack / Zoom /
  Meet; the recording pill switches to "Transcribing…" the moment you stop.
- **In-app version, release notes, and a How-to-use guide** (Settings → About / Help).

100% on-device — audio, transcripts, summaries and voiceprints never leave your Mac.
