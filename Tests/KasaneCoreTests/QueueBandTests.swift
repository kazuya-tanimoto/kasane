import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import KasaneCore

final class QueueBandLayoutTests: XCTestCase {
    /// MacBook Air 13 インチの使える範囲（メニューバーと下の Dock を除いた形）
    private let screen = CGRect(x: 0, y: 70, width: 1470, height: 856)
    private let standard: CGFloat = 13

    func testFillsTheScreenHeightOnTheChosenSide() {
        let width = QueueBandLayout.width(savedBaseWidth: nil, fontSize: standard, screen: screen)
        let right = QueueBandLayout.frame(side: .right, width: width, screen: screen)
        XCTAssertEqual(right.maxX, screen.maxX)
        XCTAssertEqual(right.minY, screen.minY)
        XCTAssertEqual(right.height, screen.height)
        let left = QueueBandLayout.frame(side: .left, width: width, screen: screen)
        XCTAssertEqual(left.minX, screen.minX)
        XCTAssertEqual(left.height, screen.height)
    }

    /// 同じ端に Dock があるときは、使える範囲がその分狭くなっているので、Dock の内側に出る
    func testStaysInsideADockOnTheSameSide() {
        let dockOnRight = CGRect(x: 0, y: 0, width: 1400, height: 926)
        let frame = QueueBandLayout.frame(side: .right, width: 282, screen: dockOnRight)
        XCTAssertEqual(frame.maxX, 1400)
    }

    func testInitialWidthIsThePreviousWidth() {
        let width = QueueBandLayout.width(savedBaseWidth: nil, fontSize: standard, screen: screen)
        XCTAssertEqual(width, 260 * standard / 12, accuracy: 0.001)
    }

    func testMaxWidthHoldsFortyFullWidthCharacters() {
        for size: CGFloat in [13, 14.5, 16] {
            let max = QueueBandLayout.maxWidth(fontSize: size, screen: screen)
            let body = max - QueueBandLayout.chromeWidth(fontSize: size)
            XCTAssertEqual(body, 40 * size, accuracy: 0.001)
        }
        // 文字を大きくすると最大も広がる
        XCTAssertGreaterThan(
            QueueBandLayout.maxWidth(fontSize: 16, screen: screen),
            QueueBandLayout.maxWidth(fontSize: 13, screen: screen)
        )
    }

    func testDraggingTheInnerEdge() {
        let start: CGFloat = 300
        // 右の帯は左端をつかむので、左へ動かすと広がる
        XCTAssertEqual(QueueBandLayout.draggedWidth(from: start, deltaX: -50, side: .right, fontSize: standard, screen: screen), 350)
        XCTAssertEqual(QueueBandLayout.draggedWidth(from: start, deltaX: 50, side: .left, fontSize: standard, screen: screen), 350)
    }

    func testDraggingStopsAtMinAndMax() {
        let min = QueueBandLayout.minWidth(fontSize: standard, screen: screen)
        let max = QueueBandLayout.maxWidth(fontSize: standard, screen: screen)
        XCTAssertEqual(QueueBandLayout.draggedWidth(from: 300, deltaX: 500, side: .right, fontSize: standard, screen: screen), min)
        XCTAssertEqual(QueueBandLayout.draggedWidth(from: 300, deltaX: -2000, side: .right, fontSize: standard, screen: screen), max)
    }

    /// 覚えた幅は 12pt のときの値なので、文字の大きさを変えても 1 行の字数がほぼ変わらない
    func testSavedWidthFollowsTheTextSize() {
        let dragged: CGFloat = 400
        let base = QueueBandLayout.baseWidth(for: dragged, fontSize: standard)
        XCTAssertEqual(QueueBandLayout.width(savedBaseWidth: base, fontSize: standard, screen: screen), dragged, accuracy: 0.001)
        XCTAssertEqual(QueueBandLayout.width(savedBaseWidth: base, fontSize: 16, screen: screen), dragged * 16 / 13, accuracy: 0.001)
    }

    /// 狭い画面でも、帯が画面からはみ出さない
    func testNeverWiderThanTheScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 240, height: 600)
        XCTAssertEqual(QueueBandLayout.width(savedBaseWidth: 600, fontSize: 16, screen: narrow), 240)
    }
}

final class QueueCardContentTests: XCTestCase {
    func testTextShowsTheBodyWithLineBreaksUpToThreeLines() {
        let card = QueueCardContent.make(kind: .text, title: "a b", text: "a\nb", hasThumbnail: false, linkTitle: nil, hasLinkImage: false)
        XCTAssertEqual(card.body, "a\nb")
        XCTAssertEqual(card.bodyLines, 3)
        XCTAssertEqual(card.picture, .none)
        XCTAssertNil(card.heading)
    }

    /// ファイルの本文はフルパスなので、名前（題名）を出す
    func testFileShowsTheNameNotThePath() {
        let card = QueueCardContent.make(kind: .file, title: "見積書_v2.pdf", text: "/Users/someone/Documents/見積書_v2.pdf", hasThumbnail: false, linkTitle: nil, hasLinkImage: false)
        XCTAssertEqual(card.body, "見積書_v2.pdf")
    }

    func testImageShowsTheThumbnailAndOneLineName() {
        let card = QueueCardContent.make(kind: .image, title: "スクリーンショット", text: nil, hasThumbnail: true, linkTitle: nil, hasLinkImage: false)
        XCTAssertEqual(card.picture, .thumbnail)
        XCTAssertEqual(card.body, "スクリーンショット")
        XCTAssertEqual(card.bodyLines, 1)
    }

    func testLinkWithPageInfoShowsImageTitleAndOneLineURL() {
        let url = "https://github.com/example-org/sample-app/pull/12"
        let card = QueueCardContent.make(kind: .url, title: url, text: url, hasThumbnail: false, linkTitle: "Add FIFO mode", hasLinkImage: true)
        XCTAssertEqual(card.picture, .linkImage)
        XCTAssertEqual(card.heading, "Add FIFO mode")
        XCTAssertEqual(card.body, url)
        XCTAssertEqual(card.bodyLines, 1)
        XCTAssertTrue(card.bodyIsSecondary)
    }

    func testLinkWithoutPageInfoShowsOnlyTheURLUpToThreeLines() {
        let url = "https://developer.apple.com/design/human-interface-guidelines/"
        for title: String? in [nil, "  "] {
            let card = QueueCardContent.make(kind: .url, title: url, text: url, hasThumbnail: false, linkTitle: title, hasLinkImage: false)
            XCTAssertEqual(card.picture, .none)
            XCTAssertNil(card.heading)
            XCTAssertEqual(card.body, url)
            XCTAssertEqual(card.bodyLines, 3)
            XCTAssertFalse(card.bodyIsSecondary)
        }
    }

    /// とても長い文は先頭だけを持つ（描画が遅くならないように）
    func testLongTextIsCutToTheSnippet() {
        let long = String(repeating: "あ", count: 1_000_000)
        let card = QueueCardContent.make(kind: .text, title: "あ", text: long, hasThumbnail: false, linkTitle: nil, hasLinkImage: false)
        XCTAssertEqual(card.body.count, QueueCardContent.snippetLimit)
        XCTAssertEqual(QueueCardContent.snippet("短い"), "短い")
    }

    func testEmptyTextKeepsTheCardHeight() {
        let card = QueueCardContent.make(kind: .text, title: "", text: "", hasThumbnail: false, linkTitle: nil, hasLinkImage: false)
        XCTAssertEqual(card.body, " ")
    }
}
