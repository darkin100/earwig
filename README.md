# Earwig 🦻

A macOS menu bar app that listens for meetings (Microsoft Teams, Google Meet, Slack Huddles, Zoom), asks if you want to record, then records **both sides** of the conversation, transcribes it **on-device**, and uses Claude to write markdown meeting notes into a folder.

## How it works

1. **Detect** — polls CoreAudio every 2s for per-process microphone usage. When a known meeting app starts capturing the mic, a floating *"Meeting detected — Record / Ignore"* panel appears (top-right of screen). When the meeting app releases the mic for 45s, recording **auto-stops** and processing begins.
2. **Record** — your mic via `AVAudioEngine` + everyone else via a CoreAudio process tap (system audio only — no screen access). The two streams are merged into one `.m4a`.
3. **Transcribe** — on-device with the macOS 26 `SpeechAnalyzer` long-form API (falls back to `SFSpeechRecognizer`). Audio never leaves your Mac.
4. **Notes** — the transcript is piped through `claude -p` (Claude Code CLI) to produce structured markdown (title, summary, key points, action items, cleaned transcript), written to `~/MeetingNotes/meeting-YYYY-MM-DD-HHmm.md`.

## Build & run

```sh
./build.sh          # builds Earwig.app
open Earwig.app
```

First recording will prompt for permissions:
- **Microphone** (your voice)
- **System Audio Recording Only** (the other participants)
- **Speech Recognition** (transcription)

## Menu bar

- **Start/Stop Recording** — manual control (⌘R)
- **Simulate Meeting Detection** — test the prompt without a real meeting
- **Open Notes Folder / Config File / Log**

## Configuration

`~/Library/Application Support/Earwig/config.json`:

```json
{
  "notesFolder": "/Users/you/MeetingNotes",
  "audioFolder": "/Users/you/MeetingNotes/audio",
  "keepAudio": true,
  "claudeCommand": "claude",
  "localeIdentifier": "en_GB"
}
```

Point `notesFolder` at the folder your Claude Cowork project watches.

## Re-process a recording

If the pipeline fails (e.g. Claude CLI offline), the audio is preserved. Re-run it:

```sh
./Earwig.app/Contents/MacOS/Earwig --process ~/MeetingNotes/audio/meeting-....m4a
```

## Start at login

System Settings → General → Login Items → add `Earwig.app`.

## Notes / limitations (MVP)

- Browser detection is per-process but not per-tab: any mic use by Chrome/Safari/etc. may prompt (Meet or otherwise). Dedicated apps (Teams, Slack, Zoom) take precedence in the prompt label.
- Auto-stop applies only when a meeting app was seen on the mic during the recording; manual test recordings never auto-stop.
- One audio file with both sides mixed; no speaker diarisation yet.

## Salvage an unstopped recording

If a recording is interrupted (app killed, crash), the raw captures live in a
`$TMPDIR/earwig-*` folder. Merge and process them:

```sh
./Earwig.app/Contents/MacOS/Earwig --merge out.m4a <dir>/mic.caf <dir>/system.caf
./Earwig.app/Contents/MacOS/Earwig --process out.m4a
```
