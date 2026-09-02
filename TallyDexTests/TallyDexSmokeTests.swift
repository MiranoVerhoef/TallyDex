import XCTest
import UniformTypeIdentifiers
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

    func testCollectionBackupTypeIsRegisteredAsJSON() {
        XCTAssertEqual(UTType.tallyDexCollection.identifier, PortableCollectionDocument.formatIdentifier)
        XCTAssertTrue(UTType.tallyDexCollection.conforms(to: .json))
        XCTAssertEqual(UTType.tallyDexCollection.preferredFilenameExtension, "pokecollection")
    }

    func testFutureCardmarketCurrenciesRemainExplicit() {
        XCTAssertEqual(
            CardmarketCurrencyPreference.allCases.map(\.rawValue),
            ["EUR", "USD"]
        )
        XCTAssertEqual(PricingSettings.defaultCardmarketCurrency, .eur)
    }

    func testFutureCardmarketCountryMappingUsesOfficialSellerIdentifiers() {
        XCTAssertNil(CardmarketCountryPreference.all.cardmarketSellerCountryID)
        XCTAssertEqual(CardmarketCountryPreference.netherlands.cardmarketSellerCountryID, 23)
        XCTAssertEqual(CardmarketCountryPreference.unitedKingdom.cardmarketSellerCountryID, 13)
        XCTAssertEqual(CardmarketCountryPreference.iceland.cardmarketSellerCountryID, 37)
        XCTAssertEqual(
            Set(CardmarketCountryPreference.allCases.compactMap(\.cardmarketSellerCountryID)).count,
            CardmarketCountryPreference.allCases.count - 1
        )
    }
}
