# Earwig evals

A regression suite built from real captured meetings. It exists because two
pipeline "enhancements" in a row silently deleted dialogue (Whisper prompt
priming on 2026-07-28; over-eager cross-channel echo suppression on
2026-07-29) and nothing caught it until a human read the notes.

## What lives where

- **This folder (committed to a public repo):** the harness (`run_eval.py`),
  the case manifest (`manifest.json`), this README. The manifest is a test
  *specification* only — thresholds, tiers, expected speaker ranges. It is
  version-controlled deliberately, so that loosening a pass threshold shows
  up in a diff instead of happening quietly. It carries no dates, no names,
  and no meeting filenames.
- **`~/EarwigEvals/` (local only — NEVER commit or upload):** the meeting
  audio, reference transcripts, and run results. Meeting content is
  confidential.
  - `CASES.md` — maps each opaque case id back to the meeting it came from.
    The only file that connects a case to a real conversation, which is
    exactly why it lives here and not in the repo.
  - `audio/` — merged recordings as `case-NN.m4a`, plus `pair-NN/mic.caf` +
    `system.caf` raw channel captures salvaged from failed pipeline runs.
    The pairs are precious: they are the only inputs that exercise the
    two-channel path (energy gate, echo suppression, echo guard, channel
    interleaving).
  - `references/` — plain-Whisper transcriptions of each file (no
    diarization, no repair, no vocabulary): the validated "nothing deleted"
    baseline.
  - `results/<timestamp>/` — notes + `report.json` from each run.

## Running

```bash
./build.sh                                  # eval runs the built app binary
python3 evals/run_eval.py                   # quick tier (~40 min of audio)
python3 evals/run_eval.py --tier full       # everything (~3.5 h of audio)
python3 evals/run_eval.py --case pair-standup-short
python3 evals/run_eval.py --make-references # only needed for new cases
```

The harness refuses to run while a meeting is being recorded (transcription
would starve the call — pass `--wait-for-idle` to block until it ends). It
swaps in an isolated config and moves the speaker catalogue aside for the
duration, restoring both on exit, so eval runs never touch real notes or
pollute the voice catalogue.

## Metrics

| Metric | Meaning | Failure it catches |
|---|---|---|
| `recall` | fraction of reference token-trigrams present in the note | transcript truncation, dropped windows, over-filtering |
| `mic_unique_recall` | pair cases: recall over trigrams appearing *only* in the mic channel — the local speaker's own words | echo suppression wrongly deleting the mic channel |
| `system_unique_recall` | same for the remote side | system channel loss |
| `speakers` | frontmatter speaker count vs expected range | diarization collapse (warn only — clustering is fuzzy) |
| `wpm`, `words`, `runtime_s` | reported for trend-watching | gradual drift |

Thresholds live per-case in `manifest.json`. They are deliberately loose
(recall ≥ 0.9 merged, ≥ 0.85 pair; unique-channel recall ≥ 0.65): Whisper is
not perfectly deterministic and legitimate filtering (real hallucinations,
real echoes) removes some reference content. A genuine regression blows
through them — the priming bug scored recall ≈ 0.15, and the echo-suppression
bug scores mic_unique_recall ≈ 0.

## Workflow

Run the quick tier before committing any pipeline change; run `--tier full`
before anything that touches transcription, diarization, or the echo logic.
CI cannot run this (the audio is private and the models are ~1.5 GB) — it is
a local pre-commit ritual.

## Adding a case

1. Copy the audio into `~/EarwigEvals/audio/` as the next `case-NN.m4a` (or
   a `pair-NN/` dir for raw channel captures — grab them from
   `$TMPDIR/earwig-*/` after a pipeline failure, before macOS purges them).
   Never use the original `meeting-<date>-<time>` name: the manifest is
   public and those filenames are a record of your calendar.
2. Add an entry to `manifest.json`, and a row to `~/EarwigEvals/CASES.md`
   recording which meeting it actually is. Give the case an id that describes
   the *audio* ("four-speaker-call"), never who or when.
3. `python3 evals/run_eval.py --make-references --case <id>`
4. Sanity-read the reference transcript, then run the case and check the
   numbers look like the healthy cases before trusting them.
