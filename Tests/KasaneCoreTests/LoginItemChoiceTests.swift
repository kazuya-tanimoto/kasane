import XCTest
@testable import KasaneCore

/// 初回の案内の「ログイン時に起動」（requirements.md §3.8）
final class LoginItemChoiceTests: XCTestCase {
    func testFirstLaunchStartsChecked() {
        XCTAssertTrue(LoginItemChoice.initialValue(hasCompletedOnboarding: false, currentlyEnabled: false))
        XCTAssertTrue(LoginItemChoice.initialValue(hasCompletedOnboarding: false, currentlyEnabled: true))
    }

    func testShownAgainKeepsTheCurrentSetting() {
        XCTAssertFalse(LoginItemChoice.initialValue(hasCompletedOnboarding: true, currentlyEnabled: false), "許可が外れて出し直すときは、オフの人をオンにしない")
        XCTAssertTrue(LoginItemChoice.initialValue(hasCompletedOnboarding: true, currentlyEnabled: true))
    }

    func testChangesOnlyWhenDifferent() {
        XCTAssertEqual(LoginItemChoice.change(checked: true, currentlyEnabled: false), true)
        XCTAssertEqual(LoginItemChoice.change(checked: false, currentlyEnabled: true), false)
        XCTAssertNil(LoginItemChoice.change(checked: true, currentlyEnabled: true))
        XCTAssertNil(LoginItemChoice.change(checked: false, currentlyEnabled: false))
    }
}
