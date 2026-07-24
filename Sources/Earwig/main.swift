import AppKit
import Foundation

// Headless mode: `Earwig --process <audio-file>` runs the transcription ->
// notes pipeline on an existing recording and exits. Used for testing and for
// re-processing a meeting whose pipeline failed.
let args = CommandLine.arguments
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
                voiceMatchThreshold: config.effectiveVoiceMatchThreshold)
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
                })
            let stampFormatter = DateFormatter()
            stampFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let noteURL = config.notesFolderURL
                .appendingPathComponent("meeting-\(stampFormatter.string(from: Date())).md")
            try notes.write(to: noteURL, atomically: true, encoding: .utf8)
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
