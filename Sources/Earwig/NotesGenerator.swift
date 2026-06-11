import Foundation

/// Turns a raw transcript into polished markdown meeting notes by piping it
/// through the `claude` CLI in print mode. Falls back to a plain markdown
/// wrapper around the raw transcript if the CLI is unavailable or fails.
enum NotesGenerator {
    static func generateNotes(
        transcript: String,
        meetingDate: Date,
        duration: TimeInterval,
        apps: [String],
        claudeCommand: String,
        claudeModel: String
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateString = dateFormatter.string(from: meetingDate)
        let minutes = Int(duration / 60)

        let header = """
        ---
        date: \(dateString)
        duration_minutes: \(minutes)
        source: \(apps.isEmpty ? "manual recording" : apps.joined(separator: ", "))
        generated_by: earwig
        ---

        """

        let prompt = """
        You are formatting a raw speech-to-text transcript of a work meeting into clean markdown meeting notes.

        Produce exactly this structure:
        # <A short descriptive meeting title you infer from the content>

        ## Summary
        2-4 sentence overview of what the meeting was about.

        ## Key Points
        Bullet list of the main topics and decisions.

        ## Action Items
        Bullet list of action items with owners if identifiable. Write "None identified" if there are none.

        ## Transcript
        The transcript lightly cleaned up: fix obvious speech-to-text errors, add paragraph breaks at topic changes, but do NOT summarise or omit content.

        Output only the markdown, no preamble. The raw transcript follows:

        \(transcript)
        """

        if let notes = runClaude(command: claudeCommand, model: claudeModel, prompt: prompt),
           !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return header + notes
        }

        Log.info("claude CLI unavailable or failed; writing raw transcript markdown")
        return header + """
        # Meeting \(dateString)

        ## Transcript

        \(transcript)
        """
    }

    private static func runClaude(command: String, model: String, prompt: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command, "-p", "--model", model]
        // GUI apps inherit a minimal PATH; include Homebrew + local bins.
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env

        // Run claude in our own Application Support dir. Its project-context
        // scanning then stays out of TCC-protected folders (Desktop/Documents),
        // which would otherwise trigger folder-access prompts blamed on Earwig.
        let workdir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Earwig", isDirectory: true)
        try? FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        process.currentDirectoryURL = workdir

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            Log.info("Failed to launch claude CLI: \(error)")
            return nil
        }

        // Write the prompt on stdin off the main thread, then close.
        DispatchQueue.global().async {
            if let data = prompt.data(using: .utf8) {
                stdin.fileHandleForWriting.write(data)
            }
            try? stdin.fileHandleForWriting.close()
        }

        // Read output concurrently to avoid pipe-buffer deadlock on long notes.
        var outputData = Data()
        let reader = DispatchQueue(label: "io.darkin.earwig.claude-out")
        let done = DispatchSemaphore(value: 0)
        reader.async {
            outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }

        // Allow up to 10 minutes for long transcripts.
        let deadline = Date().addingTimeInterval(600)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
        }
        if process.isRunning {
            Log.info("claude CLI timed out; terminating")
            process.terminate()
            return nil
        }
        done.wait()

        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            Log.info("claude CLI exited \(process.terminationStatus): \(err.prefix(500))")
            return nil
        }
        return String(data: outputData, encoding: .utf8)
    }
}
