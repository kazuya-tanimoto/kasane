import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
#if canImport(AppKit)
import AppKit
import SwiftUI
#endif
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

    /// 影は帯の内側の端の外にだけ出し、帯には重ねない。大きさはモックの影を画面の割合で戻した値（10.7pt ずらし、ぼかし 35.6pt）
    func testShadowSitsOutsideTheInnerEdge() {
        let band = CGRect(x: 1000, y: 0, width: 282, height: 737)
        let right = QueueBandLayout.shadowFrame(band: band, side: .right)
        XCTAssertEqual(right.maxX, band.minX)
        XCTAssertEqual(right.minY, band.minY)
        XCTAssertEqual(right.height, band.height)
        let left = QueueBandLayout.shadowFrame(band: band, side: .left)
        XCTAssertEqual(left.minX, band.maxX)
        XCTAssertEqual(QueueBandLayout.Metrics.shadowOffset, 10.7, accuracy: 0.05)
        XCTAssertEqual(QueueBandLayout.Metrics.shadowBlur, 35.6, accuracy: 0.05)
        XCTAssertEqual(right.width, 10.7 + 35.6 * 1.5, accuracy: 0.1)
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
            let character = QueueBandLayout.fullWidthCharacterWidth(fontSize: size)
            XCTAssertEqual(body, 40 * character + QueueBandLayout.maxWidthSlack, accuracy: 0.001)
            XCTAssertLessThan(body, 41 * character)
        }
        // 文字を大きくすると最大も広がる
        XCTAssertGreaterThan(
            QueueBandLayout.maxWidth(fontSize: 16, screen: screen),
            QueueBandLayout.maxWidth(fontSize: 13, screen: screen)
        )
    }

    #if canImport(AppKit)
    /// 実際の文字で並べて、一番広い帯の本文の 1 行目に全角 40 字が入り、41 字目は次の行に回る（2026-10-31、43 字入った不具合）
    func testMaxWidthBreaksAfterFortyCharactersWithTheRealFont() {
        for size: CGFloat in [13, 14.5, 16] {
            let maxBody = QueueBandLayout.maxWidth(fontSize: size, screen: screen) - QueueBandLayout.chromeWidth(fontSize: size)
            let minBody = QueueBandLayout.minWidth(fontSize: size, screen: screen) - QueueBandLayout.chromeWidth(fontSize: size)
            let maxLine = firstLineLength(width: maxBody, fontSize: size)
            let minLine = firstLineLength(width: minBody, fontSize: size)
            print("QueueBand: \(size)pt 全角 1 字 \(QueueBandLayout.fullWidthCharacterWidth(fontSize: size))pt、最大の本文 \(maxBody)pt に \(maxLine) 字、最小の本文 \(minBody)pt に \(minLine) 字")
            XCTAssertEqual(maxLine, 40)
        }
    }

    /// 帯の文字は SwiftUI の Text で描く。AppKit の並べ方と同じかを、SwiftUI で描いて 1 行に入る字数で確かめる
    @MainActor
    func testSwiftUITextBreaksAfterFortyCharactersAtMaxWidth() {
        for size: CGFloat in [13, 14.5, 16] {
            let maxBody = QueueBandLayout.maxWidth(fontSize: size, screen: screen) - QueueBandLayout.chromeWidth(fontSize: size)
            let oneLine = renderedHeight(count: 1, width: maxBody, fontSize: size)
            var fits = 0
            for count in 30...50 where renderedHeight(count: count, width: maxBody, fontSize: size) <= oneLine {
                fits = count
            }
            // 字の幅を文字の大きさとしていた前の最大（40 × 文字の大きさ + 1）でも数える（43 字入った不具合の原因を見るため）
            let oldBody = 40 * size + 1
            var oldFits = 0
            for count in 30...50 where renderedHeight(count: count, width: oldBody, fontSize: size) <= oneLine {
                oldFits = count
            }
            print("QueueBand SwiftUI: \(size)pt 最大の本文 \(maxBody)pt に \(fits) 字、前の最大 \(oldBody)pt に \(oldFits) 字")
            XCTAssertEqual(fits, 40)
        }
    }

    @MainActor
    private func renderedHeight(count: Int, width: CGFloat, fontSize: CGFloat) -> CGFloat {
        let view = Text(String(repeating: "一", count: count))
            .font(.system(size: fontSize))
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        return ImageRenderer(content: view).nsImage?.size.height ?? 0
    }

    private func firstLineLength(width: CGFloat, fontSize: CGFloat) -> Int {
        let storage = NSTextStorage(
            string: String(repeating: "一", count: 60),
            attributes: [.font: NSFont.systemFont(ofSize: fontSize)]
        )
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var range = NSRange()
        _ = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: &range)
        return range.length
    }
    #endif

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
    func testTextJoinsLinesWithSlashesUpToThreeLines() {
        let card = QueueCardContent.make(kind: .text, title: "a b", text: "a\nb", hasThumbnail: false, linkTitle: nil, hasLinkImage: false)
        XCTAssertEqual(card.body, "a / b")
        XCTAssertEqual(card.bodyLines, 3)
        XCTAssertEqual(card.picture, .none)
        XCTAssertNil(card.heading)
    }

    /// ファイルの本文はフルパスなので、名前（題名）を出す
    func testFileShowsTheNameNotThePath() {
        let card = QueueCardContent.make(kind: .file, title: "見積書_v2.pdf", text: "/Users/someone/Documents/見積書_v2.pdf", hasThumbnail: false, linkTitle: nil, hasLinkImage: false)
        XCTAssertEqual(card.body, "見積書_v2.pdf")
    }

    /// 画像のファイル（CleanShot などがファイルとしてコピーした絵）は、縮小と名前 1 行。縮小が無ければ名前だけ
    func testImageFileShowsTheThumbnailAndOneLineName() {
        let card = QueueCardContent.make(kind: .file, title: "CleanShot 2026-10-31 at 18.34.01.png", text: "/Users/someone/Desktop/CleanShot 2026-10-31 at 18.34.01.png", hasThumbnail: true, linkTitle: nil, hasLinkImage: false)
        XCTAssertEqual(card.picture, .thumbnail)
        XCTAssertEqual(card.body, "CleanShot 2026-10-31 at 18.34.01.png")
        XCTAssertEqual(card.bodyLines, 1)
        let plain = QueueCardContent.make(kind: .file, title: "見積書_v2.pdf", text: "/Users/someone/見積書_v2.pdf", hasThumbnail: false, linkTitle: nil, hasLinkImage: false)
        XCTAssertEqual(plain.picture, .none)
        XCTAssertEqual(plain.bodyLines, QueueCardContent.maxLines)
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

    func testLinkURLIsGrayOnlyUnderATitle() {
        let withTitle = QueueCardContent.make(kind: .url, title: "https://a.example", text: "https://a.example", hasThumbnail: false, linkTitle: "A", hasLinkImage: true)
        XCTAssertTrue(withTitle.bodyIsSecondary)
        let imageOnly = QueueCardContent.make(kind: .url, title: "https://a.example", text: "https://a.example", hasThumbnail: false, linkTitle: nil, hasLinkImage: true)
        XCTAssertEqual(imageOnly.picture, .linkImage)
        XCTAssertFalse(imageOnly.bodyIsSecondary, "代表画像だけでタイトルの無いときは、URL を本文の色にする")
    }

    // MARK: 改行を「 / 」でつなぐ（合意したモックの 1 枚目のカード）

    func testJoinedLinesMatchesTheMock() {
        XCTAssertEqual(
            QueueCardContent.joinedLines("name: kasane\nversion: 0.1.0\ndescription: clipboard"),
            "name: kasane / version: 0.1.0 / description: clipboard"
        )
    }

    func testJoinedLinesDropsEmptyLinesIndentAndWindowsLineEnds() {
        XCTAssertEqual(QueueCardContent.joinedLines("a\r\n\r\n    b  \n\n\tc\n"), "a / b / c")
        XCTAssertEqual(QueueCardContent.joinedLines("one line"), "one line")
        XCTAssertEqual(QueueCardContent.joinedLines("\n \n"), "")
    }

    // MARK: カードの絵の大きさ

    func testCardPictureIsWideEnoughForTheBand() {
        // 横長（Retina のスクリーンショット）: 長い辺＝横を帯のピクセル数にする
        XCTAssertEqual(QueueBandLayout.cardPictureMaxPixel(width: 3024, height: 1964, pixelWidth: 1400), 1400)
        // 縦長: 横を帯の幅にするため、長い辺（縦）を伸ばす
        XCTAssertEqual(QueueBandLayout.cardPictureMaxPixel(width: 1000, height: 2000, pixelWidth: 1400), 2000)
        XCTAssertEqual(QueueBandLayout.cardPictureMaxPixel(width: 2000, height: 3000, pixelWidth: 1400), 2100)
    }

    func testCardPictureIsNeverLargerThanTheOriginalOrTheLimit() {
        XCTAssertEqual(QueueBandLayout.cardPictureMaxPixel(width: 300, height: 200, pixelWidth: 1400), 300)
        XCTAssertEqual(QueueBandLayout.cardPictureMaxPixel(width: 1000, height: 9000, pixelWidth: 1400), 4096)
        XCTAssertEqual(QueueBandLayout.cardPictureMaxPixel(width: 0, height: 100, pixelWidth: 1400), 0)
    }
}
