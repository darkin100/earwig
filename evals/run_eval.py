#!/usr/bin/env python3
"""Earwig regression eval.

Runs the real Earwig binary over a fixed set of captured meeting audio and
scores the resulting notes against locally stored reference transcripts.
Catches the failure mode that has bitten twice: a pipeline "enhancement"
silently deleting real dialogue.

Usage:
  python3 evals/run_eval.py                     # quick tier
  python3 evals/run_eval.py --tier full         # everything (slow)
  python3 evals/run_eval.py --case huddle-1to1-echoey
  python3 evals/run_eval.py --make-references   # (re)build reference transcripts
  python3 evals/run_eval.py --wait-for-idle ... # block until no live meeting first

How it scores (no hand-made ground truth needed):
  - References are plain Whisper transcriptions of each file — no diarization,
    no repair, no cross-channel logic. That configuration was validated by hand
    against real meetings and is the "nothing deleted" baseline.
  - A case run uses the full pipeline (diarization on; repair off, for
    determinism and speed) and must reproduce the reference's content:
      recall               fraction of reference token-trigrams present in the
                           candidate note (union of channels for pair cases)
      mic_unique_recall    pair cases only: recall over trigrams that appear
                           ONLY in the mic channel — i.e. the local speaker's
                           own words. This is the number that collapses when
                           echo suppression wrongly drops the mic channel.
      system_unique_recall same, for the remote side.
  - Speaker count from the note frontmatter is checked against a loose
    expected range (reported as WARN, never FAIL: diarization clustering is
    genuinely fuzzy).

The harness swaps ~/Library/Application Support/Earwig/config.json (and moves
the speaker catalogue aside so runs are deterministic and the real catalogue
is never polluted), restoring both on exit — and refuses to start while a
meeting is being recorded.
"""

import argparse
import atexit
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BINARY = REPO / "Earwig.app/Contents/MacOS/Earwig"
APP_SUPPORT = Path.home() / "Library/Application Support/Earwig"
CONFIG = APP_SUPPORT / "config.json"
SPEAKERS = APP_SUPPORT / "speakers.json"
SPEAKER_CLIPS = APP_SUPPORT / "Speakers"


def load_manifest():
    manifest = json.loads((REPO / "evals/manifest.json").read_text())
    store = Path(manifest["eval_store"]).expanduser()
    return manifest, store


# ---------------------------------------------------------------- live guard

def live_meeting():
    """A mic.caf in any earwig temp dir modified in the last 60s means a
    recording is in progress (or a merge is imminent)."""
    tmp = Path(tempfile.gettempdir())
    for caf in tmp.glob("earwig-*/mic.caf"):
        try:
            if time.time() - caf.stat().st_mtime < 60:
                return True
        except FileNotFoundError:
            pass
    return False


def wait_for_idle():
    while live_meeting():
        print("meeting in progress — waiting 60s (evals would starve the call)")
        time.sleep(60)


# ------------------------------------------------------- config isolation

_restore = {}


def isolate(diarize, out_dir):
    """Swap in an eval config; move the speaker catalogue aside. Registers
    restoration on exit the first time it is called."""
    if "config" not in _restore:
        _restore["config"] = CONFIG.read_bytes()
        if SPEAKERS.exists():
            _restore["speakers"] = SPEAKERS.read_bytes()
        _restore["clips"] = set(p.name for p in SPEAKER_CLIPS.glob("*"))
        atexit.register(restore)
    if SPEAKERS.exists():
        SPEAKERS.unlink()
    CONFIG.write_text(json.dumps({
        "notesFolder": str(out_dir),
        "audioFolder": str(out_dir / "audio"),
        "keepAudio": True,
        "localeIdentifier": "en_GB",
        "autoStopGraceSeconds": 30,
        "whisperModel": "large-v3-v20240930_turbo",
        "enableDiarization": diarize,
        "enableTranscriptRepair": False,
        "voiceMatchThreshold": 0.6,
        "vocabulary": [],
    }, indent=2))


def restore():
    if "config" in _restore:
        CONFIG.write_bytes(_restore["config"])
    if "speakers" in _restore:
        SPEAKERS.write_bytes(_restore["speakers"])
    elif SPEAKERS.exists():
        SPEAKERS.unlink()
    for clip in SPEAKER_CLIPS.glob("*"):
        if clip.name not in _restore.get("clips", {clip.name}):
            clip.unlink()
    print("restored real config + speaker catalogue")
    _restore.clear()


# ------------------------------------------------------------ running earwig

def run_process(args_list, out_dir, label):
    """Run the Earwig CLI with notes going to a fresh out_dir; return the
    transcript text of the single note it wrote."""
    out_dir.mkdir(parents=True, exist_ok=True)
    started = time.time()
    result = subprocess.run([str(BINARY)] + args_list,
                            capture_output=True, text=True, timeout=7200)
    elapsed = time.time() - started
    notes = sorted(out_dir.glob("meeting-*.md"))
    if result.returncode != 0 or not notes:
        raise RuntimeError(
            f"{label}: earwig exited {result.returncode}, "
            f"{len(notes)} note(s) written\n{result.stdout[-2000:]}")
    text = notes[-1].read_text()
    transcript = text[text.index("## Transcript"):] if "## Transcript" in text else text
    return transcript, text, elapsed


def transcribe_plain(audio_path, work_root, label):
    """Reference transcription: no diarization, no repair, no vocabulary."""
    out_dir = work_root / f"ref-{label}"
    isolate(diarize=False, out_dir=out_dir)
    transcript, _, elapsed = run_process(
        ["--process", str(audio_path)], out_dir, label)
    return transcript, elapsed


# ------------------------------------------------------------------- metrics

def tokens(text):
    return [t for t in re.sub(r"[^a-z0-9 ]", " ", text.lower()).split() if t]


def trigrams(toks):
    return set(zip(toks, toks[1:], toks[2:]))


def recall(reference_trigrams, candidate_trigrams):
    if not reference_trigrams:
        return 1.0
    return len(reference_trigrams & candidate_trigrams) / len(reference_trigrams)


def speaker_count(note_text):
    m = re.search(r"^speakers: (\d+)$", note_text, re.M)
    return int(m.group(1)) if m else None


# ----------------------------------------------------------------- reference

def make_references(cases, store):
    refs = store / "references"
    refs.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="earwig-eval-ref-") as tmp:
        work = Path(tmp)
        for case in cases:
            cid = case["id"]
            if case["type"] == "merged":
                targets = {f"{cid}.txt": store / case["audio"]}
            else:
                targets = {f"{cid}.mic.txt": store / case["mic"],
                           f"{cid}.system.txt": store / case["system"]}
            for name, audio in targets.items():
                out = refs / name
                if out.exists():
                    print(f"{name}: exists, skipping (delete to regenerate)")
                    continue
                print(f"{name}: transcribing {audio.name} "
                      f"({case['duration_min']} min)...")
                transcript, elapsed = transcribe_plain(audio, work, name)
                out.write_text(transcript)
                print(f"{name}: {len(tokens(transcript))} words in {elapsed:.0f}s")


# ---------------------------------------------------------------------- eval

def run_case(case, store, work):
    cid = case["id"]
    refs = store / "references"
    out_dir = work / cid
    isolate(diarize=True, out_dir=out_dir)

    if case["type"] == "merged":
        transcript, note, elapsed = run_process(
            ["--process", str(store / case["audio"])], out_dir, cid)
        ref = trigrams(tokens((refs / f"{cid}.txt").read_text()))
        cand = trigrams(tokens(transcript))
        metrics = {"recall": recall(ref, cand)}
    else:
        transcript, note, elapsed = run_process(
            ["--process-pair", str(store / case["mic"]),
             str(store / case["system"]), "0"], out_dir, cid)
        mic = trigrams(tokens((refs / f"{cid}.mic.txt").read_text()))
        system = trigrams(tokens((refs / f"{cid}.system.txt").read_text()))
        cand = trigrams(tokens(transcript))
        metrics = {
            "recall": recall(mic | system, cand),
            "mic_unique_recall": recall(mic - system, cand),
            "system_unique_recall": recall(system - mic, cand),
        }

    metrics["words"] = len(tokens(transcript))
    metrics["wpm"] = round(metrics["words"] / case["duration_min"], 1)
    metrics["speakers"] = speaker_count(note)
    metrics["runtime_s"] = round(elapsed)

    failures = []
    for name, minimum in case["thresholds"].items():
        metric = name.removesuffix("_min")
        if metrics[metric] < minimum:
            failures.append(f"{metric} {metrics[metric]:.2f} < {minimum:.2f}")
    warnings = []
    lo, hi = case.get("speakers_expected", [1, 99])
    if metrics["speakers"] is not None and not lo <= metrics["speakers"] <= hi:
        warnings.append(f"speakers {metrics['speakers']} outside [{lo},{hi}]")
    return metrics, failures, warnings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", default="quick", choices=["quick", "full"])
    ap.add_argument("--case", action="append", help="run only these case ids")
    ap.add_argument("--make-references", action="store_true")
    ap.add_argument("--wait-for-idle", action="store_true")
    args = ap.parse_args()

    if not BINARY.exists():
        sys.exit(f"binary not found: {BINARY} — run ./build.sh first")
    manifest, store = load_manifest()
    cases = manifest["cases"]
    if args.case:
        cases = [c for c in cases if c["id"] in args.case]
    elif not args.make_references and args.tier == "quick":
        cases = [c for c in cases if c["tier"] == "quick"]

    if args.wait_for_idle:
        wait_for_idle()
    if live_meeting():
        sys.exit("A meeting is being recorded right now — evals would starve "
                 "the call and race the app for config. Re-run later or use "
                 "--wait-for-idle.")

    if args.make_references:
        make_references(cases, store)
        return

    results_dir = store / "results" / datetime.now().strftime("%Y-%m-%d-%H%M%S")
    results_dir.mkdir(parents=True)
    report, failed = {}, False
    for case in cases:
        print(f"\n=== {case['id']} ({case['duration_min']} min, {case['type']})")
        try:
            metrics, failures, warnings = run_case(case, store, results_dir)
        except Exception as e:  # noqa: BLE001 — a broken case must not stop the suite
            print(f"ERROR {e}")
            report[case["id"]] = {"error": str(e)}
            failed = True
            continue
        status = "FAIL" if failures else "PASS"
        failed = failed or bool(failures)
        print(f"{status}  " + "  ".join(
            f"{k}={v}" for k, v in metrics.items()))
        for f in failures:
            print(f"  FAIL: {f}")
        for w in warnings:
            print(f"  warn: {w}")
        report[case["id"]] = {"status": status, "metrics": metrics,
                              "failures": failures, "warnings": warnings}

    (results_dir / "report.json").write_text(json.dumps(report, indent=2))
    print(f"\nreport: {results_dir / 'report.json'}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
