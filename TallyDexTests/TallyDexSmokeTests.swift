import XCTest
import UniformTypeIdentifiers
import UIKit
@testable import TallyDex

final class TallyDexSmokeTests: XCTestCase {
    @MainActor
    func testPhotoExportRejectsInvalidArtwork() {
        XCTAssertNil(CardPhotoExport.pngData(from: Data("not an image".utf8)))
    }

    @MainActor
    func testPhotoExportProducesPNGFromJPEG() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 12)).image { context in
            UIColor.yellow.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 12))
        }
        let input = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let output = try XCTUnwrap(CardPhotoExport.pngData(from: input))
        XCTAssertEqual(Array(output.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(UIImage(data: output)?.cgImage?.width, image.cgImage?.width)
        XCTAssertEqual(UIImage(data: output)?.cgImage?.height, image.cgImage?.height)
    }

    func testPrimaryNavigationIncludesCameraTab() {
        XCTAssertEqual(AppTab.allCases.count, 5)
        XCTAssertTrue(AppTab.allCases.contains(.camera))
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

    func testSharedCardDeepLinkRoundTripsCardIdentifier() {
        let url = CardDeepLink.url(cardID: "me02.5-076")
        let appURL = CardDeepLink.appURL(cardID: "me02.5-076")

        XCTAssertEqual(
            url.absoluteString,
            "https://miranoverhoef.github.io/TallyDex/card/?id=me02.5-076"
        )
        XCTAssertEqual(CardDeepLink.cardID(from: url), "me02.5-076")
        XCTAssertEqual(appURL.absoluteString, "tallydex://card/me02.5-076")
        XCTAssertEqual(CardDeepLink.cardID(from: appURL), "me02.5-076")
        XCTAssertNil(CardDeepLink.cardID(from: URL(string: "https://example.com/card")!))
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
