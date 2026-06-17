import AppKit
import Foundation

// Headless mode: `Earwig --process <audio-file>` runs the transcription ->
// notes pipeline on an existing recording and exits. Used for testing and for
// re-processing a meeting whose pipeline failed.
let args = CommandLine.arguments

/// Prints a failure to stderr — the friendly `errorDescription` when available, else the
/// full error (e.g. a raw DecodingError from a corrupt sidecar).
func reportFailure(_ error: Error) {
    let detail = (error as? LocalizedError)?.errorDescription ?? "\(error)"
    FileHandle.standardError.write(Data("FAILED: \(detail)\n".utf8))
}

if let flagIndex = args.firstIndex(of: "--process"), args.count > flagIndex + 1 {
    let audioURL = URL(fileURLWithPath: (args[flagIndex + 1] as NSString).expandingTildeInPath)
    let config = Config.load()
    config.ensureFolders()

    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0
    Task {
        do {
            print("Processing \(audioURL.path)...")
            let output = try await DiarizedTranscriber.run(audioURL: audioURL, config: config)

            let now = Date()
            let stampFormatter = DateFormatter()
            stampFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let stamp = stampFormatter.string(from: now)

            // duration unknown for reprocessed recordings → 0.
            let result = try MeetingWriter.write(
                output, stamp: stamp, meetingDate: now,
                duration: 0, apps: ["manual --process run"], config: config)

            if result.sidecarsComplete {
                print("Note written: \(result.noteURL.path) [\(result.mode.rawValue)]")
            } else {
                print("Note written: \(result.noteURL.path) [\(result.mode.rawValue)] — WARNING: sidecar write failed (speakers.json: \(result.speakersSidecarFailed ? "FAILED" : "ok"), transcript.json: \(result.transcriptSidecarFailed ? "FAILED" : "ok"))")
            }
        } catch {
            reportFailure(error)
            exitCode = 1
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(exitCode)
}

// Headless mode: `Earwig --merge <out.m4a> <in1> [in2 ...]` mixes audio files
// into one m4a. Used to salvage recordings that were never stopped in-app.
if let flagIndex = args.firstIndex(of: "--merge"), args.count > flagIndex + 2 {
    let outURL = URL(fileURLWithPath: (args[flagIndex + 1] as NSString).expandingTildeInPath)
    let inputs = args[(flagIndex + 2)...].map {
        URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
    }
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0
    Task {
        do {
            let added = try await Recorder.merge(inputs: Array(inputs), to: outURL)
            if added < inputs.count {
                FileHandle.standardError.write(Data(
                    "WARNING: only \(added) of \(inputs.count) input(s) merged — see log for skipped files\n".utf8))
            }
            print("Merged \(added) of \(inputs.count) file(s) -> \(outURL.path)")
        } catch {
            reportFailure(error)
            exitCode = 1
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(exitCode)
}

// Headless mode: `Earwig --test-record <seconds> <output.m4a>` records mic +
// system audio for N seconds and writes the merged file. Used to verify the
// capture path without the GUI.
if let flagIndex = args.firstIndex(of: "--test-record"), args.count > flagIndex + 2,
   let seconds = Double(args[flagIndex + 1]) {
    let outURL = URL(fileURLWithPath: (args[flagIndex + 2] as NSString).expandingTildeInPath)
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0
    Task {
        let recorder = Recorder()
        do {
            print("Recording \(seconds)s of mic + system audio...")
            try await recorder.start()
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            _ = try await recorder.stop(mergedTo: outURL)
            print("Wrote \(outURL.path)")
        } catch {
            reportFailure(error)
            exitCode = 1
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(exitCode)
}

// Headless mode: `Earwig --test-diarize <audio-file>` runs diarization only and
// prints the speaker segments. Used to validate diarization on sample audio.
if let flagIndex = args.firstIndex(of: "--test-diarize"), args.count > flagIndex + 1 {
    let audioURL = URL(fileURLWithPath: (args[flagIndex + 1] as NSString).expandingTildeInPath)
    let config = Config.load()
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0
    Task {
        do {
            print("Diarizing \(audioURL.path)...")
            let result = try await Diarizer.diarize(
                audioURL: audioURL,
                clusteringThreshold: config.clusteringThreshold,
                minSpeechDuration: config.minSpeechDuration)
            let speakers = Set(result.segments.map(\.clusterId)).sorted()
            print("Speakers: \(speakers.count) — \(speakers.map { "Speaker \($0)" }.joined(separator: ", "))")
            for seg in result.segments.prefix(40) {
                print("  Speaker \(seg.clusterId): \(TimeFormat.timestamp(seg.start)) – \(TimeFormat.timestamp(seg.end))")
            }
        } catch {
            reportFailure(error)
            exitCode = 1
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(exitCode)
}

// `Earwig --enroll-me <meeting> <label>` — register your own voice from a past meeting.
if let i = args.firstIndex(of: "--enroll-me"), args.count > i + 2 {
    let config = Config.load()
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0
    Task {
        do {
            try IdentityService.enrollMe(
                meeting: args[i + 1], label: args[i + 2],
                notesFolder: config.notesFolderURL, voicesURL: Config.voicesURL,
                maxSamples: config.maxSamplesPerVoice)
            print("Enrolled your voice from \(args[i + 1]) / \(args[i + 2]).")
        } catch { reportFailure(error); exitCode = 1 }
        semaphore.signal()
    }
    semaphore.wait(); exit(exitCode)
}

// `Earwig --name <meeting> <label> <name>` — name + enroll a speaker; re-renders the note.
if let i = args.firstIndex(of: "--name"), args.count > i + 3 {
    let config = Config.load()
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0
    Task {
        do {
            let relabeled = try IdentityService.nameSpeaker(
                meeting: args[i + 1], label: args[i + 2], name: args[i + 3],
                notesFolder: config.notesFolderURL, voicesURL: Config.voicesURL,
                maxSamples: config.maxSamplesPerVoice)
            if relabeled {
                print("Named '\(args[i + 2])' as '\(args[i + 3])' and re-rendered the note.")
            } else {
                print("Enrolled '\(args[i + 3])', but the note was not re-rendered (no transcript.json — re-run --process on that recording).")
            }
        } catch { reportFailure(error); exitCode = 1 }
        semaphore.signal()
    }
    semaphore.wait(); exit(exitCode)
}

// `Earwig --identities` — list enrolled voices.
if args.contains("--identities") {
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0
    Task {
        do {
            let ids = try IdentityService.listIdentities(voicesURL: Config.voicesURL)
            if ids.isEmpty { print("No enrolled voices yet.") }
            for id in ids {
                print("\(id.isMe ? "[me] " : "      ")\(id.name) — \(id.samples.count) sample(s)")
            }
        } catch { reportFailure(error); exitCode = 1 }
        semaphore.signal()
    }
    semaphore.wait(); exit(exitCode)
}

// `Earwig --forget <name>` — remove a voice from the registry.
if let i = args.firstIndex(of: "--forget"), args.count > i + 1 {
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0
    Task {
        do {
            try IdentityService.forget(args[i + 1], voicesURL: Config.voicesURL)
            print("Forgot '\(args[i + 1])'.")
        } catch { reportFailure(error); exitCode = 1 }
        semaphore.signal()
    }
    semaphore.wait(); exit(exitCode)
}

// Headless: `Earwig --summarize <engine-or-model> [text…]` — run the summary path and print
// the result. Pass "apple" to use Apple Foundation Models, or an Ollama tag (e.g. "qwen2.5:3b")
// to use Ollama. Used to reproduce/diagnose the summary path outside the GUI.
if let i = args.firstIndex(of: "--summarize"), args.count > i + 1 {
    let arg = args[i + 1]
    let engine: SummaryEngineKind = arg == "apple" ? .apple : .ollama
    let modelID = engine == .apple ? "" : arg
    let text = args.count > i + 2
        ? args[(i + 2)...].joined(separator: " ")
        : "Me: Hi everyone. Let's ship the beta on Friday. Speaker 1: Sounds good, I'll write the release notes. Me: Great, Nev will draft the spec by Wednesday."
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0
    Task {
        do {
            print("Summarizing via \(engine.displayName)\(modelID.isEmpty ? "" : " (\(modelID))")…")
            let result = try await Summarizer.shared.summarize(
                transcript: text, template: SummaryTemplate.dailyStandup, custom: "",
                engine: engine, modelID: modelID)
            print("TLDR: \(result.tldr)")
            print("Key points: \(result.keyPoints)")
            print("Action items: \(result.actionItems)")
        } catch { reportFailure(error); exitCode = 1 }
        semaphore.signal()
    }
    semaphore.wait(); exit(exitCode)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular) // real window + Dock icon; status item stays
app.run()
