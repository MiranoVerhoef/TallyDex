import XCTest
@testable import TallyDex

final class TallyDexSmokeTests: XCTestCase {
    func testPrimaryNavigationHasFourTabs() {
        XCTAssertEqual(AppTab.allCases.count, 4)
    }

    func testSetsScopeOffersAllExpectedViews() {
        XCTAssertEqual(SetsScope.allCases.map(\.title), ["All Sets", "My Sets", "Hidden"])
    }

    func testInvalidStoredSetsScopeFallsBackToAllSets() {
        XCTAssertEqual(SetsScope.resolve("unsupported"), .all)
    }

    func testAppearanceDefaultsToSystem() {
        XCTAssertEqual(AppAppearance.resolve("unsupported"), .system)
        XCTAssertNil(AppAppearance.system.colorScheme)
    }

    func testSetsBrowsingStyleOffersBothLayouts() {
        XCTAssertEqual(SetsBrowsingStyle.allCases.map(\.title), ["Series First", "Grouped List"])
        XCTAssertEqual(SetsBrowsingStyle.resolve("unsupported"), .seriesFirst)
    }
}
