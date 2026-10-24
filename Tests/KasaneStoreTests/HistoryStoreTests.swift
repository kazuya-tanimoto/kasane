import XCTest
import GRDB
import KasaneCore
@testable import KasaneStore

final class HistoryStoreTests: XCTestCase {
    var store: HistoryStore!

    override func setUpWithError() throws {
        store = try HistoryStore(directory: nil)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: store.directory)
    }

    func textCapture(_ text: String, extra: [Capture.Representation] = []) -> Capture {
        let data = Data(text.utf8)
        return Capture(
            kind: .text, title: text, text: text, primaryData: data,
            representations: [.init(itemIndex: 0, type: "public.utf8-plain-text", data: data)] + extra
        )
    }

    func testSaveAndLoad() throws {
        let result = try store.save(textCapture("hello"), limit: 100)
        XCTAssertTrue(result.isNew)
        let id = try XCTUnwrap(result.item.id)
        XCTAssertEqual(try store.item(id: id)?.text, "hello")
        XCTAssertEqual(try store.representations(itemID: id).map(\.type), ["public.utf8-plain-text"])
    }

    func testDuplicateMovesToTop() throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let a = try store.save(textCapture("A"), limit: 100, now: t0)
        _ = try store.save(textCapture("B"), limit: 100, now: t0.addingTimeInterval(1))
        let again = try store.save(textCapture("A"), limit: 100, now: t0.addingTimeInterval(2))
        XCTAssertFalse(again.isNew)
        XCTAssertEqual(again.item.id, a.item.id)
        XCTAssertEqual(again.item.copyCount, 2)
        XCTAssertEqual(try store.count(), 2)
        XCTAssertEqual(try store.loadIndex(sort: .recent).map(\.summary.title), ["A", "B"])
    }

    func testDuplicateReplacesRepresentations() throws {
        _ = try store.save(textCapture("A", extra: [.init(itemIndex: 0, type: "public.rtf", data: Data("old".utf8))]), limit: 100)
        let again = try store.save(textCapture("A", extra: [.init(itemIndex: 0, type: "public.html", data: Data("new".utf8))]), limit: 100)
        let types = try store.representations(itemID: again.item.id!).map(\.type)
        XCTAssertEqual(types, ["public.utf8-plain-text", "public.html"])
    }

    func testDuplicateIgnoresSurroundingWhitespaceAndLineEndings() throws {
        let a = try store.save(textCapture("そういうことですか。"), limit: 100)
        let b = try store.save(textCapture("そういうことですか。\n"), limit: 100)
        let c = try store.save(textCapture("\n  そういうことですか。\r\n\n"), limit: 100)
        XCTAssertEqual(b.item.id, a.item.id)
        XCTAssertEqual(c.item.id, a.item.id)
        XCTAssertEqual(c.item.copyCount, 3)
        // 貼り付けるのは最後にコピーした形
        XCTAssertEqual(try store.item(id: a.item.id!)?.text, "\n  そういうことですか。\r\n\n")
        XCTAssertEqual(try store.count(), 1)
    }

    func testDifferentLinesAreNotMerged() throws {
        _ = try store.save(textCapture("1行目"), limit: 100)
        _ = try store.save(textCapture("1行目\n2行目"), limit: 100)
        _ = try store.save(textCapture("1行目\r\n2行目"), limit: 100)
        XCTAssertEqual(try store.count(), 2)
    }

    func testRichTextMergesWithPlainText() throws {
        let plain = try store.save(textCapture("同じ文"), limit: 100)
        var rich = textCapture("同じ文", extra: [.init(itemIndex: 0, type: "public.rtf", data: Data("{\\rtf1 同じ文}".utf8))])
        rich.kind = .richText
        let again = try store.save(rich, limit: 100)
        XCTAssertEqual(again.item.id, plain.item.id)
        XCTAssertEqual(again.item.kind, .richText)
        XCTAssertEqual(try store.item(id: plain.item.id!)?.kind, .richText)
        XCTAssertEqual(try store.count(), 1)
    }

    func testPlainTextKeepsExistingRichText() throws {
        var rich = textCapture("同じ文", extra: [.init(itemIndex: 0, type: "public.rtf", data: Data("{\\rtf1 同じ文}".utf8))])
        rich.kind = .richText
        let first = try store.save(rich, limit: 100, now: Date(timeIntervalSince1970: 100))
        let id = try XCTUnwrap(first.item.id)
        let again = try store.save(textCapture("同じ文\n"), limit: 100, now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(again.item.id, id)
        XCTAssertFalse(again.isNew)
        // 書式付きのまま。日時と回数だけ新しくなる
        let item = try XCTUnwrap(try store.item(id: id))
        XCTAssertEqual(item.kind, .richText)
        XCTAssertEqual(item.text, "同じ文")
        XCTAssertEqual(item.copyCount, 2)
        XCTAssertEqual(item.copiedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(try store.representations(itemID: id).map(\.type), ["public.utf8-plain-text", "public.rtf"])
        XCTAssertEqual(try store.count(), 1)
    }

    func testURLIsNotMergedWithText() {
        var url = textCapture("https://example.com")
        url.kind = .url
        XCTAssertNotEqual(url.contentHash, textCapture("https://example.com").contentHash)
    }

    func testPruneKeepsPinned() throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let first = try store.save(textCapture("1"), limit: 2, now: t0)
        try store.setPinned(true, itemID: first.item.id!)
        _ = try store.save(textCapture("2"), limit: 2, now: t0.addingTimeInterval(1))
        _ = try store.save(textCapture("3"), limit: 2, now: t0.addingTimeInterval(2))
        let fourth = try store.save(textCapture("4"), limit: 2, now: t0.addingTimeInterval(3))
        XCTAssertEqual(fourth.prunedIDs.count, 1)
        let titles = Set(try store.loadIndex(sort: .recent).map(\.summary.title))
        XCTAssertEqual(titles, ["1", "3", "4"], "ピン留めは件数に含めず、古い 2 が消える")
    }

    func testUnpinnedCountLeavesOutPinned() throws {
        let a = try store.save(textCapture("A"), limit: 100)
        _ = try store.save(textCapture("B"), limit: 100)
        _ = try store.save(textCapture("C"), limit: 100)
        try store.setPinned(true, itemID: a.item.id!)
        XCTAssertEqual(try store.unpinnedCount(), 2)
        XCTAssertEqual(try store.count(), 3)
    }

    func testLargeDataGoesToFileAndIsDeleted() throws {
        let big = Data(repeating: 7, count: HistoryStore.inlineDataLimit + 1)
        let capture = Capture(
            kind: .image, title: "画像", text: nil, primaryData: big,
            representations: [.init(itemIndex: 0, type: "public.png", data: big)]
        )
        let id = try XCTUnwrap(try store.save(capture, limit: 100).item.id)
        let blobs = try FileManager.default.contentsOfDirectory(atPath: store.blobDirectory.path)
        XCTAssertEqual(blobs.count, 1)
        XCTAssertEqual(try store.data(itemID: id, types: ["public.png"])?.data, big)

        try store.delete(itemID: id)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.blobDirectory.path).count, 0)
        XCTAssertNil(try store.item(id: id))
    }

    func testSortByPasteCount() throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let a = try store.save(textCapture("A"), limit: 100, now: t0)
        _ = try store.save(textCapture("B"), limit: 100, now: t0.addingTimeInterval(1))
        try store.recordPaste(itemID: a.item.id!)
        try store.recordPaste(itemID: a.item.id!)
        XCTAssertEqual(try store.loadIndex(sort: .mostPasted).map(\.summary.title), ["A", "B"])
        XCTAssertEqual(try store.loadIndex(sort: .recent).map(\.summary.title), ["B", "A"])
    }

    func testReuseMovesItemToTopOfRecent() throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let a = try store.save(textCapture("A"), limit: 100, now: t0)
        _ = try store.save(textCapture("B"), limit: 100, now: t0.addingTimeInterval(1))
        XCTAssertEqual(try store.loadIndex(sort: .recent).map(\.summary.title), ["B", "A"])
        try store.recordReuse(itemID: a.item.id!, now: t0.addingTimeInterval(2))
        XCTAssertEqual(try store.loadIndex(sort: .recent).map(\.summary.title), ["A", "B"])
    }

    func testDeleteAllKeepsPinned() throws {
        let a = try store.save(textCapture("A"), limit: 100)
        _ = try store.save(textCapture("B"), limit: 100)
        try store.setPinned(true, itemID: a.item.id!)
        try store.deleteAll(keepPinned: true)
        XCTAssertEqual(try store.loadIndex(sort: .recent).map(\.summary.title), ["A"])
    }

    func testIndexIsSearchableByRomaji() throws {
        var capture = textCapture("明日の会議")
        capture.romaji = "ashitanokaigi"
        _ = try store.save(capture, limit: 100)
        let candidates = try store.loadIndex(sort: .recent).map(\.candidate)
        XCTAssertEqual(FuzzyMatcher.search("kaigi", in: candidates).count, 1)
    }

    func testContentHashDiffersByKindAndData() {
        let d = Data("x".utf8)
        XCTAssertNotEqual(ContentHash.make(kind: .text, data: d), ContentHash.make(kind: .url, data: d))
        XCTAssertNotEqual(ContentHash.make(kind: .text, data: d), ContentHash.make(kind: .text, data: Data("y".utf8)))
        XCTAssertEqual(ContentHash.make(kind: .text, data: d), ContentHash.make(kind: .text, data: Data("x".utf8)))
    }

    /// 2026-10-21 より前に保存した履歴は、見出しが「最初の 1 行」のまま。移行で、改行を空白にした見出しに作り直す
    func testMigrationRebuildsOldListTitles() throws {
        let db = try DatabaseQueue()
        try HistoryStore.migrator.migrate(db, upTo: "v1")
        try db.write { db in
            let insert = """
                INSERT INTO item (kind, title, text, contentHash, byteSize, createdAt, copiedAt, copyCount, pasteCount, isPinned)
                VALUES (?, ?, ?, ?, 0, '2026-10-20 00:00:00', '2026-10-20 00:00:00', 1, 0, 0)
                """
            try db.execute(sql: insert, arguments: ["text", "会議", "会議\n\n  10時から", "a"])
            try db.execute(sql: insert, arguments: ["image", "画像 10×10", nil, "b"])
            try db.execute(sql: insert, arguments: ["richText", "見出し", "見出し\n本文", "c"])
            try db.execute(sql: insert, arguments: ["url", "https://example.com", "https://example.com\n", "d"])
        }
        try HistoryStore.migrator.migrate(db)
        let titles = try db.read { db in
            try String.fetchAll(db, sql: "SELECT title FROM item ORDER BY contentHash")
        }
        XCTAssertEqual(titles, ["会議 10時から", "画像 10×10", "見出し 本文", "https://example.com"], "画像の見出しは変えない")
    }
}
