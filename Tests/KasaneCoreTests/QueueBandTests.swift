import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import KasaneCore

final class QueueBandLayoutTests: XCTestCase {
    /// 帯を出せる範囲（MacBook Air 13 インチの画面からメニューバーを除いた形）
    private let screen = CGRect(x: 0, y: 0, width: 1470, height: 926)
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

    /// Dock は避けずにかぶせるので、Dock が下でも右でも、画面の端と画面の下まで届く。上はメニューバーの下まで。
    /// 値は CI の Mac（1024×768、メニューバー 31pt）で測った visibleFrame
    func testCoversTheDockAndReachesTheScreenBottom() {
        let full = CGRect(x: 0, y: 0, width: 1024, height: 768)
        for visible in [
            CGRect(x: 0, y: 63, width: 1024, height: 674), // Dock が下
            CGRect(x: 0, y: 0, width: 974, height: 737), // Dock が右
            CGRect(x: 0, y: 0, width: 1024, height: 737), // Dock を自動で隠す
        ] {
            let area = QueueBandLayout.bandArea(screenFrame: full, visibleFrame: visible)
            XCTAssertEqual(area, CGRect(x: 0, y: 0, width: 1024, height: 737))
            let frame = QueueBandLayout.frame(side: .right, width: 282, screen: area)
            XCTAssertEqual(frame.maxX, 1024)
            XCTAssertEqual(frame.minY, 0)
            XCTAssertEqual(frame.maxY, 737)
        }
    }

    /// 影は帯の内側の端の外にだけ出し、帯には重ねない
    func testShadowSitsOutsideTheInnerEdge() {
        let band = CGRect(x: 1000, y: 0, width: 282, height: 737)
        let right = QueueBandLayout.shadowFrame(band: band, side: .right, fontSize: 12)
        XCTAssertEqual(right.maxX, band.minX)
        XCTAssertEqual(right.width, QueueBandLayout.Metrics.shadowExtent, accuracy: 0.001)
        XCTAssertEqual(right.minY, band.minY)
        XCTAssertEqual(right.height, band.height)
        let left = QueueBandLayout.shadowFrame(band: band, side: .left, fontSize: 12)
        XCTAssertEqual(left.minX, band.maxX)
        // 文字を大きくすると影も比例して大きくなる
        let big = QueueBandLayout.shadowFrame(band: band, side: .right, fontSize: 16)
        XCTAssertEqual(big.width, QueueBandLayout.Metrics.shadowExtent * 16 / 12, accuracy: 0.001)
    }

    func testInitialWidthIsThePreviousWidth() {
        let width = QueueBandLayout.width(savedBaseWidth: nil, fontSize: standard, screen: screen)
        XCTAssertEqual(width, 260 * standard / 12, accuracy: 0.001)
    }

    func testMaxWidthHoldsFortyFullWidthCharacters() {
        for size: CGFloat in [13, 14.5, 16] {
            let max = QueueBandLayout.maxWidth(fontSize: size, screen: screen)
            let body = max - QueueBandLayout.chromeWidth(fontSize: size)
            // 40 字分に、丸めで 39 字目で折り返さないための余裕を足す。余裕は 1 字より小さく、41 字目は入らない
            XCTAssertEqual(body, 40 * size + QueueBandLayout.maxWidthSlack, accuracy: 0.001)
            XCTAssertLessThan(body, 41 * size)
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
