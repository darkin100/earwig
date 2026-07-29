# The processing pipeline

How a meeting goes from "an app grabbed the microphone" to a markdown note in
the notes folder. File locations and retention are covered in
[audio-storage.md](audio-storage.md).

## Meeting lifecycle

```mermaid
flowchart TD
    detect["MeetingDetector<br/>polls CoreAudio: which app holds the mic?"]
    prompt["Record prompt<br/>(Glass sound + meeting title via Accessibility)"]
    record["Recorder<br/>mic → mic.caf (AVAudioEngine)<br/>system audio → system.caf (CoreAudio process tap)"]
    live["Live notes sidebar<br/>user jots notes during the call"]
    autostop{"Call ended?<br/>meeting app off mic for grace period (30s default),<br/>call windows all closed (10s), or manual stop"}
    merge["Merge channels → audio/meeting-&lt;stamp&gt;.m4a<br/>stash live notes → meeting-&lt;stamp&gt;-livenotes.txt"]
    rearm["Detection re-arms immediately<br/>(back-to-back meetings each get their own recording)"]
    queue["Transcription queue<br/>serialized; deferred while any meeting is live<br/>(Whisper would starve the video stream)"]
    transcribe["Transcribe + diarize<br/>(see next diagram)"]
    note["Write meeting-&lt;stamp&gt;.md<br/>frontmatter status: raw-transcript · Hero sound"]

    detect -->|meeting app on mic| prompt
    prompt -->|user accepts| record
    record --> live
    record --> autostop
    autostop -->|yes| merge
    merge --> rearm
    merge --> queue
    queue --> transcribe
    transcribe --> note
```

Downstream of the note, summarisation and action items are owned by a separate
project watching the notes folder — Earwig deliberately stops at the raw
transcript.

## Transcription and diarization

The preferred path processes the two channels separately: the system channel
is clean remote voices, the mic channel is the local speaker. Each falls back
gracefully — two-channel → merged single-channel Whisper → Apple
SpeechAnalyzer (macOS 26+) → SFSpeechRecognizer.

```mermaid
flowchart TD
    subgraph channels["Per channel (mic and system independently)"]
        whisper["WhisperKit large-v3-turbo<br/>VAD chunking, CPU + Neural Engine"]
        gate["Mic energy gate<br/>drops room-ambience 'speech' below the energy floor"]
        halluc["Hallucination filter<br/>noSpeechProb/avgLogprob gates, compression ratio,<br/>repeated-phrase detection"]
        diarize["FluidAudio diarization<br/>speaker clusters + mean embeddings"]
        whisper --> gate --> halluc
        whisper -.-> diarize
    end

    echo["Cross-channel echo suppression<br/>mic cluster whose embedding matches a system cluster<br/>(cosine ≥ 0.65) is a speaker-leak echo — dropped wholesale"]
    catalog["Speaker catalogue match<br/>cosine ≥ 0.6 against known voiceprints;<br/>named voices get their name, new voices are registered"]
    attribute["Attribute text to speakers<br/>Whisper segment → diarized cluster with most overlap;<br/>mic timeline shifted by its start offset"]
    guard2["Text-level echo guard<br/>fuzzy token overlap kills residual duplicated mic segments"]
    interleave["Interleave both channels by timestamp<br/>fold consecutive same-speaker segments into turns"]
    samples["Export one sample clip per speaker<br/>for human identification"]
    dict["User dictionary corrections<br/>deterministic word-boundary 'wrong → right' replacements"]
    repair["Transcript repair (Apple on-device Foundation Model)<br/>chunked; content-preserving by construction —<br/>structurally altered chunks are discarded"]

    channels --> echo --> catalog --> attribute --> guard2 --> interleave --> samples --> dict --> repair
```

> **Why the dictionary never primes Whisper:** conditioning WhisperKit 1.0.0's
> decoder with a prompt (any size, all confidence gates disabled) makes it end
> windows early and silently drop most real speech — measured 12,085 → ~1,800
> chars on the same 17-minute meeting. The dictionary is applied only after
> transcription: deterministic corrections and the repair model's glossary.
> See the NOTE in `Transcriber.swift` before re-adding priming.

## Salvage CLI

Every stage's inputs are preserved on failure, so the pipeline can be re-run
headless:

| Command | Use |
|---|---|
| `Earwig --process <audio.m4a>` | Re-run the full pipeline on a merged recording |
| `Earwig --process-pair <mic> <system> [offset]` | Re-run the two-channel pipeline on raw channel captures |
| `Earwig --merge <out.m4a> <in1> [in2 …]` | Mix stray channel files into one m4a |
| `Earwig --repair-note <note.md>` | Re-apply dictionary corrections + on-device repair to an existing note |
