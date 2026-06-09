# Earwig 🦻

A macOS menu bar app that listens for meetings (Microsoft Teams, Google Meet, Slack Huddles, Zoom), asks if you want to record, then records **both sides** of the conversation, transcribes it **on-device**, and uses Claude to write markdown meeting notes into a folder.

## How it works

1. **Detect** — polls CoreAudio every 2s for "microphone in use". When the mic goes active while a known meeting app is running, a floating *"Meeting detected — Record / Ignore"* panel appears (top-right of screen).
2. **Record** — your mic via `AVAudioEngine` + everyone else via ScreenCaptureKit system-audio capture. The two streams are merged into one `.m4a`.
3. **Transcribe** — on-device with the macOS 26 `SpeechAnalyzer` long-form API (falls back to `SFSpeechRecognizer`). Audio never leaves your Mac.
4. **Notes** — the transcript is piped through `claude -p` (Claude Code CLI) to produce structured markdown (title, summary, key points, action items, cleaned transcript), written to `~/MeetingNotes/meeting-YYYY-MM-DD-HHmm.md`.

## Build & run

```sh
./build.sh          # builds Earwig.app
open Earwig.app
```

First recording will prompt for permissions:
- **Microphone** (your voice)
- **Screen & System Audio Recording** (the other participants) — System Settings → Privacy & Security
- **Speech Recognition** (transcription)

After granting Screen Recording you may need to relaunch the app.

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

- Browser detection is heuristic: any mic use while Chrome/Safari/etc. is running may prompt (it can't see *which* tab). Dedicated apps (Teams, Slack, Zoom) take precedence in the prompt label.
- Recording stops manually from the menu bar (the mic-in-use signal can't distinguish the meeting ending from our own recording).
- One audio file with both sides mixed; no speaker diarisation yet.
