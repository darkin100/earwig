# Earwig 🦻

A macOS menu bar app that listens for meetings (Microsoft Teams, Google Meet, Slack Huddles, Zoom, WhatsApp), asks if you want to record, then records **both sides** of the conversation, transcribes it **on-device**, and writes the raw transcript as markdown into a folder.

Earwig deliberately stops at speech-to-text. Summarisation, action items, and any further processing happen downstream — point your own tooling (an LLM workflow, a Claude Cowork project, a shell script) at the notes folder.

## How it works

1. **Detect** — polls CoreAudio every 2s for *per-process* microphone usage. When a known meeting app starts capturing the mic, a floating *"Meeting detected — Record / Ignore"* panel appears (top-right of screen).
2. **Record** — your mic via `AVAudioEngine` + everyone else via a CoreAudio process tap (system audio only — no screen access). The two streams are merged into one `.m4a`.
3. **Auto-stop** — a call is considered ended when no *meeting app* has held the microphone for `autoStopGraceSeconds` (default 30s); the recording then stops and processing begins. Each call becomes its own recording and transcript — a new call after the grace window gets a fresh detection prompt, even while the previous one is still transcribing. A quick handoff *within* the grace window (e.g. Teams call rolling into a WhatsApp call) stays one session, and every app that joined is listed in the note's `source:`. Unrelated mic users (dictation tools, a stray browser tab) can't keep a session alive. If the call is on an app Earwig doesn't recognise, it falls back to stopping when the mic is released entirely; manual recordings with nothing on the mic never auto-stop.
4. **Transcribe** — on-device with the macOS 26 `SpeechAnalyzer` long-form API (falls back to `SFSpeechRecognizer` on older systems). Audio never leaves your Mac. Transcription runs in the background, so back-to-back meetings are detected while the previous one is still processing.
5. **Write** — the raw transcript lands as markdown with YAML frontmatter in the notes folder:

```markdown
---
date: 2026-06-11 09:30
duration_minutes: 42
source: Microsoft Teams
generated_by: earwig
status: raw-transcript
---

# Meeting 2026-06-11 09:30

## Transcript
...
```

The `status: raw-transcript` field lets downstream tooling tell which files it hasn't processed yet.

## Requirements

- **macOS 15+** to build and run; **macOS 26+** recommended (uses the modern `SpeechAnalyzer` long-form transcription API — older systems fall back to `SFSpeechRecognizer`, which is weaker on long recordings).
- Xcode Command Line Tools (`xcode-select --install`) — no full Xcode needed.

## Build & run

```sh
./build.sh          # builds and signs Earwig.app
open Earwig.app
```

To start it automatically: System Settings → General → Login Items → add `Earwig.app`.

## Permissions

The first recording prompts for:

| Permission | Why |
|---|---|
| **Microphone** | Your side of the conversation |
| **System Audio Recording Only** | The other participants (via CoreAudio process tap — deliberately *not* the broader Screen & System Audio Recording permission) |
| **Speech Recognition** | On-device transcription |

### Keeping grants across rebuilds

macOS ties permission grants to the app's code signature. `build.sh` signs ad-hoc by default, which produces a *new* signature every build — so each rebuild re-prompts. If you rebuild often, create a stable self-signed certificate named `Earwig Dev Signing` (Keychain Access → Certificate Assistant → Create a Certificate → type "Code Signing") and `build.sh` will pick it up automatically.

## Configuration

`~/Library/Application Support/Earwig/config.json` (created on first run):

```json
{
  "notesFolder": "/Users/you/MeetingNotes",
  "audioFolder": "/Users/you/MeetingNotes/audio",
  "keepAudio": true,
  "localeIdentifier": "en-GB",
  "autoStopGraceSeconds": 30
}
```

- `notesFolder` — where transcript markdown files are written; point your downstream tooling here.
- `keepAudio` — set `false` to delete the merged `.m4a` after a successful transcription.
- `localeIdentifier` — speech recognition language (defaults to your system locale).
- `autoStopGraceSeconds` — how long a call must be off the microphone before the recording auto-stops (default 30). Raise it if flaky network reconnects split your meetings; lower it for snappier splits between back-to-back calls.

## Menu bar

- **Start/Stop Recording** (⌘R) — manual control; the icon is a red dot while recording, a waveform while transcribing.
- **Simulate Meeting Detection** — test the prompt without a real meeting.
- **Open Notes Folder / Config File / Log**

## Headless modes

```sh
# Re-run transcription on any audio file (writes a transcript note)
./Earwig.app/Contents/MacOS/Earwig --process recording.m4a

# Mix several audio files into one m4a
./Earwig.app/Contents/MacOS/Earwig --merge out.m4a in1.caf in2.caf

# Record N seconds of mic + system audio (capture-path smoke test)
./Earwig.app/Contents/MacOS/Earwig --test-record 10 /tmp/test.m4a
```

If a recording is interrupted (crash, force quit), the raw captures survive in a `$TMPDIR/earwig-*` folder — `--merge` then `--process` recovers the meeting.

## Privacy

- Audio and transcripts **never leave your Mac** — recording, transcription, and file output are all local.
- Earwig records *system audio*, i.e. everything your Mac plays while recording — music included.
- Transcripts of real meetings are sensitive. Treat the notes folder accordingly, and check your local laws/company policy on call recording consent.

## Known limitations

- Browser detection is per-process, not per-tab: any mic use by Chrome/Safari/Arc/Edge/Brave/Firefox may prompt, whether or not it's Google Meet. Dedicated apps take precedence in the prompt label.
- No speaker diarisation — both sides are mixed into one transcript stream.
- Transcription quality is Apple's on-device model; far-field/multi-speaker audio can get rough.
- The log file (`~/Library/Application Support/Earwig/earwig.log`) grows unbounded; delete it whenever.
