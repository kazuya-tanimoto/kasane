import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import KasaneCore

final class WindowPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private let defaultSize = CGSize(width: 880, height: 560)
    private let minSize = CGSize(width: 720, height: 420)

    private func place(in screen: CGRect, size: CGSize? = nil, offset: CGPoint? = nil) -> CGRect {
        WindowPlacement.frame(in: screen, savedSize: size, savedOffset: offset, defaultSize: defaultSize, minSize: minSize)
    }

    func testDefaultIsCenteredSlightlyAbove() {
        let frame = place(in: screen)
        XCTAssertEqual(frame.size, defaultSize)
        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertGreaterThan(frame.midY, screen.midY)
    }

    func testSavedFrameRoundTrips() {
        let moved = CGRect(x: 100, y: 200, width: 1000, height: 600)
        let offset = WindowPlacement.offset(of: moved, in: screen)
        XCTAssertEqual(place(in: screen, size: moved.size, offset: offset), moved)
    }

    func testSameOffsetOnAnotherScreen() {
        // 右側に並べた外部ディスプレイでも、中心からのずれが同じ位置に出す
        let external = CGRect(x: 1512, y: -200, width: 2560, height: 1415)
        let offset = CGPoint(x: -150, y: 80)
        let frame = place(in: external, offset: offset)
        XCTAssertEqual(frame.midX, external.midX - 150)
        XCTAssertEqual(frame.midY, external.midY + 80)
    }

    func testKeptInsideWhenOffsetIsTooLarge() {
        // 大きな画面で端に寄せた位置を、小さな画面で使う
        let frame = place(in: screen, offset: CGPoint(x: 2000, y: -2000))
        XCTAssertEqual(frame.maxX, screen.maxX)
        XCTAssertEqual(frame.minY, screen.minY)
    }

    func testSizeLargerThanScreenIsShrunk() {
        let frame = place(in: screen, size: CGSize(width: 3000, height: 2000))
        XCTAssertEqual(frame, screen)
    }

    func testSizeSmallerThanMinimumIsEnlarged() {
        let frame = place(in: screen, size: CGSize(width: 100, height: 100))
        XCTAssertEqual(frame.size, minSize)
    }

    func testScreenSmallerThanMinimumUsesScreen() {
        let tiny = CGRect(x: 0, y: 0, width: 640, height: 400)
        XCTAssertEqual(place(in: tiny), tiny)
    }
}
