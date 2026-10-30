import XCTest
@testable import KasaneCore

final class LinkPreviewPolicyTests: XCTestCase {
    func testShouldFetch() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let day = LinkPreviewPolicy.refreshInterval
        XCTAssertTrue(LinkPreviewPolicy.shouldFetch(lastAttempt: nil, now: now), "記録がなければ取りに行く")
        XCTAssertFalse(LinkPreviewPolicy.shouldFetch(lastAttempt: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(LinkPreviewPolicy.shouldFetch(lastAttempt: now.addingTimeInterval(-day + 1), now: now))
        XCTAssertTrue(LinkPreviewPolicy.shouldFetch(lastAttempt: now.addingTimeInterval(-day), now: now), "ちょうど 1 日で取り直す")
        XCTAssertTrue(LinkPreviewPolicy.shouldFetch(lastAttempt: now.addingTimeInterval(-day * 3), now: now))
    }

    func testIsFetchable() {
        XCTAssertTrue(LinkPreviewPolicy.isFetchable("https://example.com/path"))
        XCTAssertTrue(LinkPreviewPolicy.isFetchable("http://example.com"))
        XCTAssertTrue(LinkPreviewPolicy.isFetchable("HTTPS://EXAMPLE.COM"))
        XCTAssertFalse(LinkPreviewPolicy.isFetchable("file:///Users/me/a.txt"))
        XCTAssertFalse(LinkPreviewPolicy.isFetchable("mailto:someone@example.com"))
        XCTAssertFalse(LinkPreviewPolicy.isFetchable("slack://open"))
        XCTAssertFalse(LinkPreviewPolicy.isFetchable("https://"))
        XCTAssertFalse(LinkPreviewPolicy.isFetchable("https://example.com/a b"))
        XCTAssertFalse(LinkPreviewPolicy.isFetchable(""))
    }

    func testSurroundingNewlinesAreIgnored() {
        // コピーしたときは前後の空白と改行を除いて URL の種類にしているので、取りに行くときも同じにする
        XCTAssertEqual(LinkPreviewPolicy.webURL("https://example.com\n")?.absoluteString, "https://example.com")
        XCTAssertEqual(LinkPreviewPolicy.webURL("  https://example.com/a  ")?.absoluteString, "https://example.com/a")
        XCTAssertNil(LinkPreviewPolicy.webURL("https://example.com\nhttps://example.org"))
    }

    #if canImport(Darwin)
    func testJapaneseURL() {
        // 日本語を含む URL も取りに行く（URL(string:) が文字を % に置き換える。macOS 14 から）
        let url = LinkPreviewPolicy.webURL("https://ja.wikipedia.org/wiki/会議")
        XCTAssertEqual(url?.host, "ja.wikipedia.org")
    }
    #endif
}

final class PrefetchSchedulerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func scheduler() -> PrefetchScheduler {
        var s = PrefetchScheduler(visibleDwell: 1.0, selectedDwell: 0.3, maxConcurrent: 2)
        s.show(at: t0)
        return s
    }

    func testVisibleRowIsQueuedAfterDwell() {
        var s = scheduler()
        s.setVisible(1, true, at: t0)
        s.tick(at: t0.addingTimeInterval(0.9))
        XCTAssertEqual(s.takeNext(), [])
        s.tick(at: t0.addingTimeInterval(1.0))
        XCTAssertEqual(s.takeNext(), [1])
    }

    func testRowScrolledPastIsNotQueued() {
        var s = scheduler()
        s.setVisible(1, true, at: t0)
        s.setVisible(1, false, at: t0.addingTimeInterval(0.5))
        s.tick(at: t0.addingTimeInterval(2))
        XCTAssertEqual(s.takeNext(), [])
    }

    func testSelectedRowWaitsOnlyTheShortDwell() {
        var s = scheduler()
        s.select(1, at: t0)
        s.select(2, at: t0.addingTimeInterval(0.1))
        s.select(3, at: t0.addingTimeInterval(0.2))
        s.tick(at: t0.addingTimeInterval(0.5))
        XCTAssertEqual(s.takeNext(), [3], "通り過ぎた 1 と 2 は取らない")
    }

    func testRowIsQueuedOnlyOncePerShow() {
        var s = scheduler()
        s.setVisible(1, true, at: t0)
        s.select(1, at: t0)
        s.tick(at: t0.addingTimeInterval(2))
        XCTAssertEqual(s.takeNext(), [1])
        s.finish(1)
        s.tick(at: t0.addingTimeInterval(3))
        XCTAssertEqual(s.takeNext(), [])
    }

    func testAtMostMaxConcurrent() {
        var s = scheduler()
        for id in Int64(1)...4 { s.setVisible(id, true, at: t0) }
        s.tick(at: t0.addingTimeInterval(2))
        XCTAssertEqual(s.takeNext().count, 2)
        XCTAssertEqual(s.takeNext(), [])
        s.finish(s.inFlight.first!)
        XCTAssertEqual(s.takeNext().count, 1)
    }

    func testHideDropsTheQueueAndShowRestartsTheDwell() {
        var s = scheduler()
        s.setVisible(1, true, at: t0)
        s.setVisible(2, true, at: t0)
        s.tick(at: t0.addingTimeInterval(2))
        XCTAssertEqual(s.takeNext().count, 2)
        s.setVisible(3, true, at: t0.addingTimeInterval(2))
        s.hide()
        s.tick(at: t0.addingTimeInterval(5))
        XCTAssertEqual(s.takeNext(), [], "閉じている間は入れない")
        // 開き直すと、見えたままの行（「見えた」が来ない）も待ちを始め直す
        let t1 = t0.addingTimeInterval(10)
        s.finish(1)
        s.finish(2)
        s.show(at: t1)
        s.tick(at: t1.addingTimeInterval(0.5))
        XCTAssertEqual(s.takeNext(), [])
        s.tick(at: t1.addingTimeInterval(1))
        let started = s.takeNext()
        XCTAssertEqual(started.count, 2, "同時に 2 件まで")
        started.forEach { s.finish($0) }
        XCTAssertEqual(s.takeNext().count, 1, "3 つ目も、見えたままなら取る")
    }

    func testNextDeadline() {
        var s = scheduler()
        XCTAssertNil(s.nextDeadline())
        s.setVisible(1, true, at: t0)
        s.select(2, at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(s.nextDeadline()!.timeIntervalSince(t0), 0.5, accuracy: 1e-6)
        s.hide()
        XCTAssertNil(s.nextDeadline())
    }

    func testRowsLeavingTheListAreForgotten() {
        var s = scheduler()
        s.setVisible(1, true, at: t0)
        s.setVisible(2, true, at: t0)
        // 検索で 1 が一覧から外れた（「見えなくなった」は届いていない）
        s.keepRows([2])
        s.tick(at: t0.addingTimeInterval(2))
        XCTAssertEqual(s.takeNext(), [2])
    }

    func testRequestedRowIsTakenWithoutWaiting() {
        var s = scheduler()
        s.request(1)
        XCTAssertEqual(s.takeNext(), [1], "FIFO / LIFO 中にキューへ入った行は待たずに取る")
    }

    func testRequestedRowIsTakenWhileHidden() {
        var s = scheduler()
        s.hide()
        s.request(1)
        XCTAssertEqual(s.takeNext(), [1], "履歴ウインドウを閉じていても取る")
        s.request(2)
        s.hide()
        XCTAssertEqual(s.takeNext(), [2], "閉じても、すぐ取る行は残す")
    }

    func testRequestedRowGoesBeforeVisibleRows() {
        var s = scheduler()
        s.setVisible(1, true, at: t0)
        s.setVisible(2, true, at: t0)
        s.setVisible(3, true, at: t0)
        s.tick(at: t0.addingTimeInterval(2))
        XCTAssertEqual(s.takeNext().count, 2)
        s.request(4)
        s.finish(s.inFlight.first!)
        XCTAssertEqual(s.takeNext(), [4], "見えている行より先に取る")
    }

    func testRequestedRowIsNotTakenTwice() {
        var s = scheduler()
        s.request(1)
        s.request(1)
        XCTAssertEqual(s.takeNext(), [1])
        s.request(1)
        XCTAssertEqual(s.takeNext(), [], "取っている途中なら入れない")
        s.setVisible(1, true, at: t0)
        s.finish(1)
        s.tick(at: t0.addingTimeInterval(2))
        XCTAssertEqual(s.takeNext(), [], "開いている間に取った行は、見えても入れ直さない")
    }

    func testCancelAllDropsRequestedRows() {
        var s = scheduler()
        s.request(1)
        s.cancelAll()
        XCTAssertEqual(s.takeNext(), [])
    }

    func testCancelAll() {
        var s = scheduler()
        s.setVisible(1, true, at: t0)
        s.tick(at: t0.addingTimeInterval(2))
        _ = s.takeNext()
        s.cancelAll()
        XCTAssertTrue(s.inFlight.isEmpty)
    }
}

final class OfflineErrorTests: XCTestCase {
    private func urlError(_ code: Int) -> NSError {
        NSError(domain: "NSURLErrorDomain", code: code)
    }

    func testOfflineErrors() {
        XCTAssertTrue(LinkPreviewPolicy.isOfflineError(urlError(-1009)), "インターネットにつながっていない")
        XCTAssertTrue(LinkPreviewPolicy.isOfflineError(urlError(-1005)), "途中で切れた")
    }

    func testOfflineErrorInsideAnotherError() {
        let wrapped = NSError(domain: "LPErrorDomain", code: 1, userInfo: [NSUnderlyingErrorKey: urlError(-1009)])
        XCTAssertTrue(LinkPreviewPolicy.isOfflineError(wrapped))
    }

    func testOtherErrorsAreRecorded() {
        XCTAssertFalse(LinkPreviewPolicy.isOfflineError(urlError(-1003)), "ホストが見つからないのは記録する")
        XCTAssertFalse(LinkPreviewPolicy.isOfflineError(urlError(-1001)), "タイムアウトは記録する")
        XCTAssertFalse(LinkPreviewPolicy.isOfflineError(NSError(domain: "LPErrorDomain", code: 1)))
    }
}
