import AppKit
import Foundation

// Headless mode: `Earwig --process <audio-file>` runs the transcription ->
// notes pipeline on an existing recording and exits. Used for testing and for
// re-processing a meeting whose pipeline failed.
let args = CommandLine.arguments

// Headless mode: `Earwig --process-pair <mic> <system> [micOffsetSeconds]`
// runs the two-channel pipeline on raw channel captures. Used for testing and
// for salvaging interrupted recordings.
if let flagIndex = args.firstIndex(of: "--process-pair"), args.count > flagIndex + 2 {
    let micURL = URL(fileURLWithPath: (args[flagIndex + 1] as NSString).expandingTildeInPath)
    let systemURL = URL(fileURLWithPath: (args[flagIndex + 2] as NSString).expandingTildeInPath)
    let micOffset = args.count > flagIndex + 3 ? (Double(args[flagIndex + 3]) ?? 0) : 0
    let config = Config.load()
    config.ensureFolders()

    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0
    Task {
        do {
            let baseName = micURL.deletingPathExtension().lastPathComponent
            let samplesDir = config.audioFolderURL.appendingPathComponent(
                "\(baseName)-pair-speakers", isDirectory: true)
            let channels = Recorder.ChannelFiles(
                mic: micURL, system: systemURL,
                directory: micURL.deletingLastPathComponent(), micOffset: micOffset)
            print("Two-channel processing (mic offset \(micOffset)s)...")
            let result = try await Transcriber.transcribe(
                audioURL: micURL, localeIdentifier: config.localeIdentifier,
                whisperModel: config.effectiveWhisperModel,
                diarize: config.effectiveDiarization,
                sampleClipsDir: samplesDir,
                voiceMatchThreshold: config.effectiveVoiceMatchThreshold,
                channels: channels,
                repairTranscript: config.effectiveTranscriptRepair)
            if let speakers = result.speakerCount { print("Speakers: \(speakers)") }
            let notes = TranscriptNote.markdown(
                transcript: result.text,
                meetingDate: Date(),
                duration: 0,
                apps: ["manual --process-pair run"],
                speakerCount: result.speakerCount,
                speakerSamples: result.speakerSamples.map {
                    ($0.speaker, AppDelegate.notePath(for: $0.url, notesFolder: config.notesFolderURL))
                },
                transcriptCleanup: result.repaired ? "auto (on-device model)" : nil)
            let stampFormatter = DateFormatter()
            stampFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let noteURL = config.notesFolderURL
                .appendingPathComponent("meeting-\(stampFormatter.string(from: Date())).md")
            try notes.write(to: noteURL, atomically: true, encoding: .utf8)
            for record in result.speakerRecords {
                SpeakerCatalog.shared.addAppearance(
                    id: record.recordID, noteFile: noteURL.lastPathComponent, label: record.label)
            }
            print("Note written: \(noteURL.path)")
        } catch {
            print("FAILED: \(error)")
            exitCode = 1
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(exitCode)
}

if let flagIndex = args.firstIndex(of: "--process"), args.count > flagIndex + 1 {
    let audioURL = URL(fileURLWithPath: (args[flagIndex + 1] as NSString).expandingTildeInPath)
    let config = Config.load()
    config.ensureFolders()

    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0
    Task {
        do {
            print("Transcribing \(audioURL.path)...")
            let baseName = audioURL.deletingPathExtension().lastPathComponent
            let samplesDir = config.audioFolderURL.appendingPathComponent(
                "\(baseName)-speakers", isDirectory: true)
            let result = try await Transcriber.transcribe(
                audioURL: audioURL, localeIdentifier: config.localeIdentifier,
                whisperModel: config.effectiveWhisperModel,
                diarize: config.effectiveDiarization,
                sampleClipsDir: samplesDir,
                voiceMatchThreshold: config.effectiveVoiceMatchThreshold,
                repairTranscript: config.effectiveTranscriptRepair)
            let transcript = result.text
            if let speakers = result.speakerCount { print("Speakers: \(speakers)") }
            print("Transcript (\(transcript.count) chars):\n---\n\(transcript.prefix(2000))\n---")
            let notes = TranscriptNote.markdown(
                transcript: transcript,
                meetingDate: Date(),
                duration: 0,
                apps: ["manual --process run"],
                speakerCount: result.speakerCount,
                speakerSamples: result.speakerSamples.map {
                    ($0.speaker, AppDelegate.notePath(for: $0.url, notesFolder: config.notesFolderURL))
                },
                transcriptCleanup: result.repaired ? "auto (on-device model)" : nil)
            let stampFormatter = DateFormatter()
            stampFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let noteURL = config.notesFolderURL
                .appendingPathComponent("meeting-\(stampFormatter.string(from: Date())).md")
            try notes.write(to: noteURL, atomically: true, encoding: .utf8)
            for record in result.speakerRecords {
                SpeakerCatalog.shared.addAppearance(
                    id: record.recordID, noteFile: noteURL.lastPathComponent, label: record.label)
            }
            print("Note written: \(noteURL.path)")
        } catch {
            print("FAILED: \(error)")
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
            try await Recorder.merge(inputs: Array(inputs), to: outURL)
            print("Merged \(inputs.count) file(s) -> \(outURL.path)")
        } catch {
            print("FAILED: \(error)")
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
            print("FAILED: \(error)")
            exitCode = 1
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(exitCode)
}

// Headless mode: `Earwig --repair-note <note.md>` runs context-aware repair
// of speech-to-text errors over an existing note's transcript, in place.
if let flagIndex = args.firstIndex(of: "--repair-note"), args.count > flagIndex + 1 {
    let noteURL = URL(fileURLWithPath: (args[flagIndex + 1] as NSString).expandingTildeInPath)
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0
    Task {
        do {
            guard TranscriptRepair.isAvailable else {
                print("Apple Intelligence on-device model is not available on this Mac.")
                exitCode = 1
                semaphore.signal()
                return
            }
            let content = try String(contentsOf: noteURL, encoding: .utf8)
            guard let range = content.range(of: "## Transcript") else {
                print("No '## Transcript' section found in \(noteURL.lastPathComponent)")
                exitCode = 1
                semaphore.signal()
                return
            }
            let head = String(content[..<range.lowerBound])
            let transcript = String(content[range.lowerBound...])
            let names = TranscriptRepair.speakerNames(in: transcript)
            print("Repairing transcript (\(transcript.count) chars, speakers: \(names.joined(separator: ", ")))...")
            if let repaired = await TranscriptRepair.repair(
                transcript: transcript, speakerNames: names) {
                var newHead = head
                if !newHead.contains("transcript_cleanup:"),
                   let statusRange = newHead.range(of: "status: raw-transcript") {
                    newHead.replaceSubrange(statusRange, with:
                        "status: raw-transcript\ntranscript_cleanup: \"auto (on-device model)\"")
                }
                try (newHead + repaired).write(to: noteURL, atomically: true, encoding: .utf8)
                print("Repairs applied and saved.")
            } else {
                print("No repairs needed (or model unavailable).")
            }
        } catch {
            print("FAILED: \(error)")
            exitCode = 1
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(exitCode)
}

// Headless mode: `Earwig --list-speakers` prints the catalogue.
if args.contains("--list-speakers") {
    for record in SpeakerCatalog.shared.all() {
        let appearances = record.appearances?.count ?? 0
        print("\(record.id.uuidString.prefix(8))  \(record.name ?? "<unnamed>")  [\(record.context)]  notes: \(appearances)")
    }
    exit(0)
}

// Headless mode: `Earwig --set-speaker-name <id-prefix> <name>` names a
// catalogued voice and retroactively updates the meeting notes it appears in.
if let flagIndex = args.firstIndex(of: "--set-speaker-name"), args.count > flagIndex + 2 {
    let idPrefix = args[flagIndex + 1].lowercased()
    let name = args[flagIndex + 2]
    let matches = SpeakerCatalog.shared.all().filter {
        $0.id.uuidString.lowercased().hasPrefix(idPrefix)
    }
    guard matches.count == 1 else {
        print(matches.isEmpty
            ? "No speaker record matches id prefix '\(idPrefix)' (see --list-speakers)"
            : "Ambiguous id prefix '\(idPrefix)' — matches \(matches.count) records")
        exit(1)
    }
    SpeakerCatalog.shared.setName(id: matches[0].id, name: name)
    print("Named \(matches[0].id.uuidString.prefix(8)) as \(name)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
