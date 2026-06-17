import XCTest
@testable import Earwig

final class MeetingDeleteTests: XCTestCase {
    private let stem = "meeting-2026-06-15-1403"
    private let notesFolder = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
    private let audioFolder = URL(fileURLWithPath: "/tmp/audio", isDirectory: true)

    private var urls: [URL] {
        Meeting.associatedFileURLs(stem: stem, notesFolder: notesFolder, audioFolder: audioFolder)
    }

    func testAssociatedFileURLsCount() {
        XCTAssertEqual(urls.count, 6)
    }

    func testAssociatedFileURLsStems() {
        for url in urls {
            XCTAssertTrue(
                url.lastPathComponent.hasPrefix(stem),
                "\(url.lastPathComponent) does not start with the meeting stem"
            )
        }
    }

    func testAssociatedFileURLsExtensions() {
        let filenames = urls.map(\.lastPathComponent)
        XCTAssertTrue(filenames.contains("\(stem).md"))
        XCTAssertTrue(filenames.contains("\(stem).transcript.json"))
        XCTAssertTrue(filenames.contains("\(stem).summary.json"))
        XCTAssertTrue(filenames.contains("\(stem).speakers.json"))
        XCTAssertTrue(filenames.contains("\(stem).notes.md"))
        XCTAssertTrue(filenames.contains("\(stem).m4a"))
    }

    func testAudioLivesUnderAudioFolder() {
        let audioURLs = urls.filter { $0.lastPathComponent.hasSuffix(".m4a") }
        XCTAssertEqual(audioURLs.count, 1)
        XCTAssertEqual(audioURLs[0].deletingLastPathComponent(), audioFolder)
    }

    func testNoteSidecarsLiveUnderNotesFolder() {
        let noteURLs = urls.filter { !$0.lastPathComponent.hasSuffix(".m4a") }
        XCTAssertEqual(noteURLs.count, 5)
        for url in noteURLs {
            XCTAssertEqual(
                url.deletingLastPathComponent(), notesFolder,
                "\(url.lastPathComponent) should live under notesFolder"
            )
        }
    }
}
