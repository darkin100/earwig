# Earwig 🦻

A privacy-first macOS menu-bar app that records your meetings, transcribes and separates speakers
**on-device**, then summarises them and lets you **search and ask questions** across everything you
have recorded. Nothing leaves your Mac by default.

![platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue)
![swift](https://img.shields.io/badge/Swift-6-orange)
![license](https://img.shields.io/badge/license-MIT-green)

Earwig watches for online meetings (Teams, Google Meet, Slack, Zoom, WhatsApp), offers to record,
captures **both sides** of the call, transcribes it locally, identifies who said what, and writes
everything to a folder you control. Summaries run on a local model by default, with Apple
Intelligence and Claude as options.

## Features

**Capture**
- Auto-detects online meetings and offers to record; manual record from the menu bar or sidebar
- Records your mic plus system audio (the other participants), merged into one track
- Auto-stops when every app has released the microphone; handles back-to-back calls

**Transcription and speakers**
- On-device transcription with WhisperKit (Whisper large-v3 turbo, CoreML)
- Speaker diarization (who said what) via FluidAudio, with word-level alignment
- Name a speaker once and Earwig recognises them in future meetings; enrol your own voice as "Me"

**Summaries and insights**
- AI summaries with a choice of engine: local Ollama (Qwen2.5 14B, default), Apple Intelligence
  (macOS 26), or Claude (bring your own Anthropic key)
- Templates and custom instructions; auto-summarise after each meeting, plus Regenerate and
  back-fill for older meetings
- Extracted action items, and per-meeting notes that fold into the summary

**Search and ask**
- Spotlight-style search (Cmd-K) across every meeting's title, summary and transcript
- "Ask your meetings": natural-language questions answered from your transcripts, with clickable
  source citations

**Manage**
- Day-grouped meeting browser, copy transcript or summary, delete meetings
- In-app feedback, a live CPU meter, in-app About and Help with release notes

## Requirements

- **macOS 15 (Sequoia) or later.**
- **Apple Silicon recommended** (transcription runs on the Neural Engine); Intel works too (the
  distributable build is universal).
- **Xcode Command Line Tools** to build (`xcode-select --install`) - no full Xcode needed.
- Transcription and diarization model files (~600 MB total) download once on first use and are
  cached locally.
- Summaries are optional. For the local engine, install [Ollama](https://ollama.com) and let the
  app download Qwen2.5 14B (~9 GB, needs 16 GB+ of memory). Apple Intelligence needs macOS 26;
  Claude needs your own API key.

## Build and run (from source)

```sh
git clone https://github.com/darkin100/earwig.git
cd earwig

swift build          # compile
swift test           # run the test suite

./build.sh           # build + sign Earwig.app
./earwig.sh restart  # (re)launch the app

# or in one step:
./earwig.sh rebuild  # build, then relaunch
```

Useful `earwig.sh` commands: `start`, `stop`, `restart`, `rebuild`, `logs`.

To launch at login: System Settings -> General -> Login Items -> add `Earwig.app`.

### Keeping permissions across rebuilds

macOS ties permission grants to the app's code signature. `build.sh` signs with a stable local
identity named `Earwig Dev Signing` if it exists, so grants survive rebuilds. Create it once with
`./scripts/create-signing-identity.sh` (or Keychain Access -> Certificate Assistant -> Create a
Certificate of type "Code Signing"). Without it, signing is ad-hoc and each rebuild re-prompts.

## Packaging for others

```sh
./package.sh
```

Builds a **universal** (Apple Silicon + Intel) signed app and zips it to
`~/Desktop/Earwig-Share/Earwig-<version>.zip` with a README for the recipient. The bundle contains
code only: no meetings, transcripts, or personal keys. As it is not notarised, recipients clear the
quarantine flag once with `xattr -dr com.apple.quarantine /Applications/Earwig.app` (or right-click
-> Open).

## How it works

1. **Detect** - polls CoreAudio for per-process microphone use. When a known meeting app starts
   using the mic, a "Meeting detected" prompt appears.
2. **Record** - your mic via `AVAudioEngine` plus everyone else via a CoreAudio process tap (system
   audio only, no screen access), merged into a single `.m4a`.
3. **Transcribe and diarize** - on-device. WhisperKit transcribes the merged track; FluidAudio
   splits it into speakers, with each word aligned to a speaker by time. Falls back to
   `SFSpeechRecognizer` if Whisper cannot load.
4. **Write** - a markdown note with YAML frontmatter lands in your notes folder, alongside
   structured sidecars (`*.transcript.json`, `*.summary.json`, `*.speakers.json`, `*.notes.md`).
5. **Summarise / search / ask** - the chosen engine summarises each meeting; the in-memory index
   powers Cmd-K search and the Ask feature.

### Speakers and identities

Earwig identifies speakers by **voice**, not by audio channel: it diarizes both your mic and the
system audio, merges voice clusters that match across the two, and matches each voice against a
local registry of enrolled people. Unknown voices appear as Speaker 1 / 2 / ...; name someone once
(in the People view or the name sheet) and they are recognised automatically next time. The same
operations are available on the command line:

```sh
./earwig.sh enroll-me <meeting> "Speaker 1"      # register your own voice -> "Me"
./earwig.sh name <meeting> "Speaker 2" "Cecile"  # name a speaker; re-renders the note
./earwig.sh identities                           # list enrolled voices
./earwig.sh forget "Cecile"                      # remove an enrolled voice
```

`<meeting>` is a note stem like `meeting-2026-06-11-0930` (or a path to one of its files).

## Summary engines

Choose the engine in Settings -> Summary:

| Engine | Notes |
|---|---|
| **Ollama** (default) | Fully local. Install Ollama, then download Qwen2.5 14B in Settings (~9 GB). Runs offline. |
| **Apple Intelligence** | On-device, nothing to download. Needs macOS 26 on Apple Silicon. |
| **Claude** | Cloud, best quality. Paste your Anthropic API key (stored locally, opt-in, disclosed). |

## Configuration

`~/Library/Application Support/Earwig/config.json` (created on first run) controls the notes/audio
folders, locale, whether to keep audio, and diarization tuning (`clusteringThreshold`,
`voiceMatchThreshold`, etc.). Summary engine and model are also stored here; the Anthropic API key
is kept separately in `~/Library/Application Support/Earwig/secrets/` and never in config.

Transcripts and notes are written to `~/MeetingNotes` by default.

## Headless / CLI

```sh
./Earwig.app/Contents/MacOS/Earwig --process recording.m4a    # re-transcribe an audio file
./Earwig.app/Contents/MacOS/Earwig --merge out.m4a in1.caf in2.caf  # mix audio files
./Earwig.app/Contents/MacOS/Earwig --test-diarize meeting.m4a # print detected speaker segments
```

If a recording is interrupted, the raw captures survive in `$TMPDIR/earwig-*`; `--merge` then
`--process` recovers the meeting.

## Project layout

```
Sources/Earwig/        # app, services, pipeline
Sources/Earwig/UI/     # SwiftUI views (menu-bar window, onboarding, settings)
Tests/EarwigTests/     # unit tests (swift test)
build.sh               # build + sign Earwig.app
package.sh             # universal distributable zip
earwig.sh              # start/stop/restart/rebuild/logs + identity commands
scripts/               # signing identity + icon generation
VERSION / CHANGELOG.md # marketing version (build number = git commit count) + history
```

Swift 6, SwiftPM (no Xcode project). Dependencies: WhisperKit (argmax-oss-swift) and FluidAudio.

## Privacy

- Audio, transcripts, summaries and voiceprints **never leave your Mac** by default.
- Transcription and diarization run on-device via CoreML; model files download once (models only,
  never your audio).
- Voiceprints are numeric embeddings (not audio), stored locally.
- The **only** cloud option is the Claude summary engine, which is opt-in and disclosed; when
  enabled it sends just that request's transcript text to Anthropic.
- Transcripts of real meetings are sensitive. Mind your local laws and company policy on recording
  consent.

## Known limitations

- Browser detection is per-process, not per-tab: any mic use by a browser may prompt.
- Diarization of far-field or compressed multi-speaker audio is best-effort.
- Separating several people around one laptop mic (far-field) is a hardware limit.

## Credits

Created by **Glyn Darkin**. Lead development by **Navnit Anuth** (speaker diarization, the app UI,
search/ask, summaries, and more).

## License

MIT. See [LICENSE](LICENSE).
