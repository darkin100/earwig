import XCTest
@testable import Earwig

final class NotesStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("earwig-notes-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testURLHasCorrectSuffix() {
        let url = NotesStore.url(stem: "meeting-abc", notesFolder: dir)
        XCTAssertEqual(url.lastPathComponent, "meeting-abc.notes.md")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                       dir.standardizedFileURL)
    }

    func testWriteThenReadRoundTrip() throws {
        try NotesStore.write("Great meeting today.", stem: "m1", notesFolder: dir)
        XCTAssertEqual(NotesStore.read(stem: "m1", notesFolder: dir), "Great meeting today.")
    }

    func testReadMissingFileReturnsEmpty() {
        XCTAssertEqual(NotesStore.read(stem: "does-not-exist", notesFolder: dir), "")
    }

    func testWriteEmptyStringDeletesFile() throws {
        try NotesStore.write("Some text", stem: "m2", notesFolder: dir)
        try NotesStore.write("", stem: "m2", notesFolder: dir)
        let url = NotesStore.url(stem: "m2", notesFolder: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(NotesStore.read(stem: "m2", notesFolder: dir), "")
    }

    func testWriteWhitespaceOnlyDeletesFile() throws {
        try NotesStore.write("Text", stem: "m3", notesFolder: dir)
        try NotesStore.write("   \n\t  ", stem: "m3", notesFolder: dir)
        let url = NotesStore.url(stem: "m3", notesFolder: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testWriteTrimsAndPersistsText() throws {
        try NotesStore.write("  Hello world  ", stem: "m4", notesFolder: dir)
        XCTAssertEqual(NotesStore.read(stem: "m4", notesFolder: dir), "Hello world")
    }
}
