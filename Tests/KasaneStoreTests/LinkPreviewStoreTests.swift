import XCTest
import GRDB
import KasaneCore
@testable import KasaneStore

/// URL のタイトルと画像の保存（design/link-prefetch-implementation-2026-10-23.md §2）
final class LinkPreviewStoreTests: XCTestCase {
    var store: HistoryStore!

    override func setUpWithError() throws {
        store = try HistoryStore(directory: nil)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: store.directory)
    }

    private func saveURL(_ url: String, now: Date = Date()) throws -> Int64 {
        let data = Data(url.utf8)
        let capture = Capture(
            kind: .url, title: url, text: url, primaryData: data,
            representations: [.init(itemIndex: 0, type: "public.utf8-plain-text", data: data)]
        )
        return try XCTUnwrap(store.save(capture, limit: 100, now: now).item.id)
    }

    private let png = LinkPreview.ImageFile(data: Data([0x89, 0x50, 0x4E, 0x47]), fileExtension: "png")
    private let jpg = LinkPreview.ImageFile(data: Data([0xFF, 0xD8, 0xFF]), fileExtension: "jpg")

    private func linkFiles() throws -> [String] {
        let directory = store.directory.appendingPathComponent("blobs/links")
        return (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    func testSaveAndRead() throws {
        let id = try saveURL("https://example.com")
        let at = Date(timeIntervalSince1970: 2_000)
        try store.saveLinkPreview(itemID: id, title: "Example", icon: png, image: jpg, at: at)
        let saved = try XCTUnwrap(store.linkPreview(itemID: id))
        XCTAssertEqual(saved.title, "Example")
        XCTAssertEqual(saved.icon, png.data)
        XCTAssertEqual(saved.image, jpg.data)
        XCTAssertEqual(saved.attemptedAt, at)
        XCTAssertTrue(saved.succeeded)
        XCTAssertEqual(try store.linkPreviewAttempt(itemID: id), at)
        XCTAssertEqual(try linkFiles().count, 2)
    }

    func testFailureKeepsThePreviousResult() throws {
        let id = try saveURL("https://example.com")
        try store.saveLinkPreview(itemID: id, title: "Example", icon: nil, image: jpg, at: Date(timeIntervalSince1970: 2_000))
        let failedAt = Date(timeIntervalSince1970: 200_000)
        try store.markLinkPreviewFailed(itemID: id, at: failedAt)
        let saved = try XCTUnwrap(store.linkPreview(itemID: id))
        XCTAssertEqual(saved.title, "Example")
        XCTAssertEqual(saved.image, jpg.data)
        XCTAssertFalse(saved.succeeded)
        XCTAssertEqual(saved.attemptedAt, failedAt, "取れなかったときも日時を記録し、1 日たつまで取り直さない")
    }

    func testFailureWithoutPreviousResult() throws {
        let id = try saveURL("https://intranet.example")
        try store.markLinkPreviewFailed(itemID: id, at: Date(timeIntervalSince1970: 3_000))
        let saved = try XCTUnwrap(store.linkPreview(itemID: id))
        XCTAssertNil(saved.title)
        XCTAssertFalse(saved.succeeded)
    }

    func testRefreshReplacesTheOldFiles() throws {
        let id = try saveURL("https://example.com")
        try store.saveLinkPreview(itemID: id, title: "Old", icon: png, image: jpg, at: Date(timeIntervalSince1970: 2_000))
        try store.saveLinkPreview(itemID: id, title: "New", icon: nil, image: png, at: Date(timeIntervalSince1970: 100_000))
        XCTAssertEqual(try store.linkPreview(itemID: id)?.title, "New")
        XCTAssertEqual(try linkFiles().count, 1, "古い画像のファイルは消える")
    }

    func testDeletedWhileFetchingLeavesNoFiles() throws {
        let id = try saveURL("https://example.com")
        try store.delete(itemID: id)
        try store.saveLinkPreview(itemID: id, title: "Example", icon: png, image: jpg, at: Date())
        try store.markLinkPreviewFailed(itemID: id, at: Date())
        XCTAssertNil(try store.linkPreview(itemID: id))
        XCTAssertEqual(try linkFiles(), [])
    }

    func testDeletingItemsRemovesPreviewsAndFiles() throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let a = try saveURL("https://a.example", now: t0)
        let b = try saveURL("https://b.example", now: t0.addingTimeInterval(1))
        let c = try saveURL("https://c.example", now: t0.addingTimeInterval(2))
        for id in [a, b, c] {
            try store.saveLinkPreview(itemID: id, title: "t", icon: png, image: jpg, at: t0)
        }
        // 1 件の削除
        try store.delete(itemID: c)
        XCTAssertNil(try store.linkPreview(itemID: c))
        XCTAssertEqual(try linkFiles().count, 4)
        // 保存件数を超えた分の削除（いちばん古い a）
        try store.prune(limit: 1)
        XCTAssertNil(try store.linkPreview(itemID: a))
        XCTAssertEqual(try linkFiles().count, 2)
        // 「履歴を削除…」
        try store.deleteAll(keepPinned: true)
        XCTAssertNil(try store.linkPreview(itemID: b))
        XCTAssertEqual(try linkFiles(), [])
    }

    func testCopyingTheSameURLAgainKeepsThePreview() throws {
        let id = try saveURL("https://example.com")
        try store.saveLinkPreview(itemID: id, title: "Example", icon: png, image: jpg, at: Date())
        _ = try saveURL("https://example.com")
        XCTAssertEqual(try store.linkPreview(itemID: id)?.title, "Example")
        XCTAssertEqual(try linkFiles().count, 2)
    }
}
