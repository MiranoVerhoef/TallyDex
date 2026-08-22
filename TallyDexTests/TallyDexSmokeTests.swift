import XCTest
@testable import TallyDex

final class TallyDexSmokeTests: XCTestCase {
    func testPrimaryNavigationHasFourTabs() {
        XCTAssertEqual(AppTab.allCases.count, 4)
    }
}

