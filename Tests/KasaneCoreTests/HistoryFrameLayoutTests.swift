import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import KasaneCore

final class HistoryFrameLayoutTests: XCTestCase {
    private let window = CGRect(x: 100, y: 200, width: 880, height: 560)

    func testBodyLeavesTheResizeMargin() {
        let body = HistoryFrameLayout.body(in: window)
        XCTAssertEqual(body, CGRect(x: 104, y: 204, width: 872, height: 552))
    }

    /// 本体を囲むウインドウは、本体を取り出すと元に戻る（覚えた本体の大きさで開き直しても、見える大きさが変わらない）
    func testWindowAroundBodyIsTheInverseOfBody() {
        let body = CGRect(x: 300, y: 150, width: 800, height: 580)
        let around = HistoryFrameLayout.window(aroundBody: body)
        XCTAssertEqual(around, CGRect(x: 296, y: 146, width: 808, height: 588))
        XCTAssertEqual(HistoryFrameLayout.body(in: around), body)
    }

    /// 本体を置ける所は、画面と中心が同じで、余白の分だけ狭い（中心からのずれで覚えた位置が、余白の前と同じ所を指す）
    func testBodyAreaKeepsTheScreenCenter() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let area = HistoryFrameLayout.bodyArea(in: screen)
        XCTAssertEqual(area, CGRect(x: 4, y: 4, width: 1504, height: 936))
        XCTAssertEqual(area.midX, screen.midX)
        XCTAssertEqual(area.midY, screen.midY)
    }

    /// 本体で置いて余白を足したウインドウは、画面からはみ出さない
    func testWindowAroundAPlacedBodyStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let body = WindowPlacement.frame(
            in: HistoryFrameLayout.bodyArea(in: screen),
            savedSize: CGSize(width: 3_000, height: 3_000), savedOffset: CGPoint(x: 900, y: 900),
            defaultSize: CGSize(width: 800, height: 580), minSize: CGSize(width: 720, height: 420)
        )
        XCTAssertTrue(screen.contains(HistoryFrameLayout.window(aroundBody: body)))
    }

    /// 影のウインドウの中の本体は、画面の上で履歴ウインドウの本体と重なる
    func testShadowCasterMatchesTheBodyOnScreen() {
        let shadow = HistoryFrameLayout.shadowFrame(window: window)
        let caster = HistoryFrameLayout.shadowCaster(inShadowOfSize: shadow.size)
        let onScreen = caster.offsetBy(dx: shadow.minX, dy: shadow.minY)
        XCTAssertEqual(onScreen, HistoryFrameLayout.body(in: window))
    }

    /// 影は下へ 30 ずれ、ぼかしの 3 標準偏差（120）まで描ける広さがある
    func testShadowFrameHoldsTheWholeShadow() {
        let shadow = HistoryFrameLayout.shadowFrame(window: window)
        XCTAssertLessThanOrEqual(shadow.minY, window.minY - 30 - 120)
        XCTAssertLessThanOrEqual(shadow.minX, window.minX - 120)
    }

    func testMockValues() {
        XCTAssertEqual(HistoryFrameLayout.cornerRadius, 20)
        XCTAssertEqual(HistoryFrameLayout.borderWidth, 1)
        XCTAssertEqual(HistoryFrameLayout.borderWhiteOpacity(dark: true), 0.12)
        XCTAssertEqual(HistoryFrameLayout.borderWhiteOpacity(dark: false), 0.70)
        XCTAssertEqual(HistoryFrameLayout.shadowOpacity, 0.35)
    }

    private let size = CGSize(width: 880, height: 560)

    /// 見える縁（ウインドウの端から 4pt）の外 3pt から内 3pt までが、端をつかむ所
    func testEdgeGripReachesThreeInsideTheVisibleEdge() {
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 880 - 4 + 3, y: 280), in: size), .right)
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 880 - 4 - 3, y: 280), in: size), .right)
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 880 - 4 - 4, y: 280), in: size), [])
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 0.5, y: 280), in: size), .left)
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 440, y: 559.5), in: size), .top)
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 440, y: 0.5), in: size), .bottom)
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 440, y: 280), in: size), [])
    }

    func testCornersResizeBothWays() {
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 2, y: 2), in: size), [.left, .bottom])
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 878, y: 558), in: size), [.right, .top])
        // 角から 16pt 離れた端の上も、まだ角
        XCTAssertEqual(HistoryFrameLayout.edges(at: CGPoint(x: 878, y: 16), in: size), [.right, .bottom])
    }

    func testResizeKeepsTheOppositeEdge() {
        let frame = CGRect(x: 100, y: 200, width: 880, height: 560)
        let min = CGSize(width: 720, height: 420)
        XCTAssertEqual(HistoryFrameLayout.resized(frame, edges: .right, dx: 30, dy: 0, minSize: min), CGRect(x: 100, y: 200, width: 910, height: 560))
        XCTAssertEqual(HistoryFrameLayout.resized(frame, edges: [.left, .top], dx: -20, dy: 10, minSize: min), CGRect(x: 80, y: 200, width: 900, height: 570))
        // 最小より小さくしようとしたら、最小で止め、右と上の端は動かさない
        let shrunk = HistoryFrameLayout.resized(frame, edges: [.left, .bottom], dx: 500, dy: 500, minSize: min)
        XCTAssertEqual(shrunk, CGRect(x: 260, y: 340, width: 720, height: 420))
    }
}
