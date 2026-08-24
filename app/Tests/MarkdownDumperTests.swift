import Foundation
import XCTest
@testable import FluidPushToTalk

final class MarkdownDumperTests: XCTestCase {
    func testDumpWithoutImagesPreservesTextOnlyFormat() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let result = try fixture.dumper.dumpRaw("hello", imageURLs: [])

        XCTAssertEqual(result.noteURL, fixture.noteURL)
        XCTAssertTrue(try String(contentsOf: fixture.noteURL, encoding: .utf8).contains("hello"))
        XCTAssertTrue(result.attachmentURLs.isEmpty)
    }

    func testDumpCopiesOrderedImagesAndWritesRelativeMarkdownEmbeds() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let first = try fixture.image(named: "first image.png", bytes: [1, 2, 3])
        let second = try fixture.image(named: "second.png", bytes: [4, 5, 6])

        let result = try fixture.dumper.dumpRaw("with images", imageURLs: [first, second])
        let markdown = try String(contentsOf: fixture.noteURL, encoding: .utf8)

        XCTAssertEqual(result.attachmentURLs.count, 2)
        XCTAssertEqual(try Data(contentsOf: result.attachmentURLs[0]), Data([1, 2, 3]))
        XCTAssertEqual(try Data(contentsOf: result.attachmentURLs[1]), Data([4, 5, 6]))
        let firstRelative = "attachments/2026-08-24/\(result.attachmentURLs[0].lastPathComponent)"
        let secondRelative = "attachments/2026-08-24/\(result.attachmentURLs[1].lastPathComponent)"
        XCTAssertTrue(markdown.contains("![Screenshot 1](\(firstRelative))"))
        XCTAssertTrue(markdown.contains("![Screenshot 2](\(secondRelative))"))
        XCTAssertLessThan(
            try XCTUnwrap(markdown.range(of: firstRelative)?.lowerBound),
            try XCTUnwrap(markdown.range(of: secondRelative)?.lowerBound)
        )
    }

    func testFiveImagesUseCollisionFreeNames() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let images = try (1...5).map { index in
            try fixture.image(named: "source-\(index).png", bytes: [UInt8(index)])
        }

        let result = try fixture.dumper.dumpRaw("five", imageURLs: images)

        XCTAssertEqual(result.attachmentURLs.count, 5)
        XCTAssertEqual(Set(result.attachmentURLs.map(\.lastPathComponent)).count, 5)
        XCTAssertEqual(try result.attachmentURLs.map { try Data(contentsOf: $0).first }, (1...5).map(UInt8.init))
    }

    func testAppendPreservesExistingNoteAndAddsOneImage() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try "existing".write(to: fixture.noteURL, atomically: true, encoding: .utf8)
        let image = try fixture.image(named: "one.png", bytes: [7])

        let result = try fixture.dumper.dumpRaw("new entry", imageURLs: [image])
        let markdown = try String(contentsOf: fixture.noteURL, encoding: .utf8)

        XCTAssertTrue(markdown.hasPrefix("existing"))
        XCTAssertTrue(markdown.contains("new entry"))
        XCTAssertTrue(markdown.contains("![Screenshot 1](attachments/2026-08-24/"))
        XCTAssertEqual(result.attachmentURLs.count, 1)
    }

    func testOverwriteReplacesExistingNote() throws {
        let fixture = try Fixture(append: false)
        defer { fixture.cleanup() }
        try "old entry".write(to: fixture.noteURL, atomically: true, encoding: .utf8)

        _ = try fixture.dumper.dumpRaw("replacement", imageURLs: [])
        let markdown = try String(contentsOf: fixture.noteURL, encoding: .utf8)

        XCTAssertFalse(markdown.contains("old entry"))
        XCTAssertTrue(markdown.contains("replacement"))
    }

    func testFailedNoteWriteRollsBackNewAttachments() throws {
        let fixture = try Fixture(noteIsDirectory: true)
        defer { fixture.cleanup() }
        let image = try fixture.image(named: "source.png", bytes: [9])

        XCTAssertThrowsError(try fixture.dumper.dumpRaw("cannot write", imageURLs: [image]))

        let attachmentRoot = fixture.root.appendingPathComponent("attachments", isDirectory: true)
        let retainedFiles = (try? FileManager.default.subpathsOfDirectory(atPath: attachmentRoot.path)) ?? []
        XCTAssertTrue(retainedFiles.filter { $0.hasSuffix(".png") }.isEmpty)
        XCTAssertEqual(try Data(contentsOf: image), Data([9]))
    }

    func testFailedNoteWritePreservesPreexistingEmptyAttachmentDirectories() throws {
        let fixture = try Fixture(noteIsDirectory: true)
        defer { fixture.cleanup() }
        let dateDirectory = fixture.root.appendingPathComponent("attachments/2026-08-24", isDirectory: true)
        try FileManager.default.createDirectory(at: dateDirectory, withIntermediateDirectories: true)
        let image = try fixture.image(named: "source.png", bytes: [10])

        XCTAssertThrowsError(try fixture.dumper.dumpRaw("cannot write", imageURLs: [image]))

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dateDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}

private final class Fixture {
    let root: URL
    let noteURL: URL
    let dumper: MarkdownDumper

    init(noteIsDirectory: Bool = false, append: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        noteURL = root.appendingPathComponent("2026-08-24.md", isDirectory: noteIsDirectory)
        if noteIsDirectory {
            try FileManager.default.createDirectory(at: noteURL, withIntermediateDirectories: true)
        }
        var config = AppConfig()
        config.dump.enabled = true
        config.dump.markdownFile = noteURL.path
        config.dump.append = append
        config.dump.includeTimestamp = false
        let fixedDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-24T12:00:00Z"))
        dumper = MarkdownDumper(config: config, now: { fixedDate })
    }

    func image(named name: String, bytes: [UInt8]) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
