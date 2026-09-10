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

    @MainActor
    func testCapturedPhotoDecoderDownsamplesForOCR() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1_200)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 1_200))
        }
        let data = try XCTUnwrap(source.jpegData(compressionQuality: 0.9))
        let decoded = try XCTUnwrap(
            CardCapturedImageDecoder.image(from: data, maximumPixelSize: 400)
        )
        XCTAssertEqual(max(decoded.size.width, decoded.size.height), 400)
        XCTAssertEqual(decoded.imageOrientation, .up)
    }

    @MainActor
    func testCardRectangleDetectorFindsAndStraightensPortraitCard() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1_200)).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 1_200))
            UIColor.white.setFill()
            context.fill(CGRect(x: 245, y: 180, width: 410, height: 565))
            UIColor.systemYellow.setStroke()
            context.cgContext.setLineWidth(14)
            context.cgContext.stroke(CGRect(x: 252, y: 187, width: 396, height: 551))
            UIColor.black.setFill()
            context.fill(CGRect(x: 285, y: 230, width: 330, height: 55))
            context.fill(CGRect(x: 285, y: 630, width: 260, height: 18))
        }

        let detection = await CardRectangleDetector.detect(in: source)

        XCTAssertNotNil(detection.corners)
        XCTAssertGreaterThan(detection.cardImage.size.height, detection.cardImage.size.width)
        XCTAssertGreaterThan(detection.cardImage.size.width, 300)
    }

    func testScannerNameValidationRejectsUnrelatedNumberMatch() {
        let candidates = ["Bewear 130", "Split Spiral Punch"]
        XCTAssertTrue(CardTextRecognizer.nameLooksLikeCard("Bewear", candidates: candidates))
        XCTAssertFalse(CardTextRecognizer.nameLooksLikeCard("Omastar", candidates: candidates))
    }

    func testScannerFuzzyTitleMatchingRecoversDamagedOCRWithoutFalsePositive() {
        let recognized = [
            "Pikachu utth Grey Fat Hat 60",
            "Pikachu with Gray Palt Hat",
            "Pika-Portrait",
        ]
        let candidates = CardTextRecognizer.nameCandidates(in: recognized)

        XCTAssertTrue(
            CardTextRecognizer.nameLooksLikeCard(
                "Pikachu with Grey Felt Hat",
                candidates: candidates
            )
        )
        XCTAssertFalse(CardTextRecognizer.nameLooksLikeCard("Omastar", candidates: candidates))
        XCTAssertEqual(CardTextRecognizer.fallbackNameQueries(in: recognized).first, "Pikachu")
    }

    func testAutomaticScannerWaitsForStableFullCard() {
        let card = CardRectangleCorners(
            topLeft: CGPoint(x: 0.2, y: 0.85),
            topRight: CGPoint(x: 0.8, y: 0.85),
            bottomRight: CGPoint(x: 0.8, y: 0.15),
            bottomLeft: CGPoint(x: 0.2, y: 0.15)
        )
        var tracker = CardRectangleStabilityTracker(requiredStableFrames: 3)

        XCTAssertFalse(tracker.observe(card))
        XCTAssertFalse(tracker.observe(card))
        XCTAssertTrue(tracker.observe(card))
        tracker.reset()
        XCTAssertFalse(tracker.observe(card))
        XCTAssertFalse(tracker.observe(nil))
        XCTAssertEqual(tracker.consecutiveStableFrames, 0)
    }

    func testCameraCaptureModeDefaultsToManualWhileAutomaticRemainsAvailable() {
        XCTAssertEqual(CardScannerCaptureMode.defaultMode, .manual)
        XCTAssertEqual(CardScannerCaptureMode.resolve("automatic"), .automatic)
        XCTAssertEqual(CardScannerCaptureMode.resolve("manual"), .manual)
        XCTAssertEqual(CardScannerCaptureMode.resolve("unsupported"), .manual)
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

    func testAppExperiencePresentsIntroductionBeforeReleaseNotes() {
        XCTAssertEqual(
            AppExperienceSettings.nextDestination(
                introductionCompleted: false,
                lastSeenReleaseVersion: "",
                currentVersion: "0.9.14"
            ),
            .introduction
        )
        XCTAssertEqual(
            AppExperienceSettings.nextDestination(
                introductionCompleted: true,
                lastSeenReleaseVersion: "0.9.13",
                currentVersion: "0.9.14"
            ),
            .whatsNew
        )
        XCTAssertNil(
            AppExperienceSettings.nextDestination(
                introductionCompleted: true,
                lastSeenReleaseVersion: "0.9.14",
                currentVersion: "0.9.14"
            )
        )

        let completedState = AppExperienceSettings.stateAfterCompletingIntroduction(
            currentVersion: "0.9.16"
        )
        XCTAssertTrue(completedState.introductionCompleted)
        XCTAssertEqual(completedState.lastSeenReleaseVersion, "0.9.16")
        XCTAssertNil(
            AppExperienceSettings.nextDestination(
                introductionCompleted: completedState.introductionCompleted,
                lastSeenReleaseVersion: completedState.lastSeenReleaseVersion,
                currentVersion: "0.9.16"
            )
        )
    }

    func testCurrentReleaseNotesAreUsefulAndUnique() {
        XCTAssertEqual(AppReleaseNotes.current.version, "0.9.17")
        XCTAssertGreaterThanOrEqual(AppReleaseNotes.current.notes.count, 1)
        XCTAssertEqual(
            Set(AppReleaseNotes.current.notes.map(\.id)).count,
            AppReleaseNotes.current.notes.count
        )
        XCTAssertTrue(AppReleaseNotes.current.notes.allSatisfy { !$0.detail.isEmpty })
    }

    func testPricePreferenceOffersNativeEURAndUSDMarkets() {
        XCTAssertEqual(CatalogPriceSource.cardmarket.currencyCode, "EUR")
        XCTAssertEqual(CatalogPriceSource.tcgplayer.currencyCode, "USD")
        XCTAssertEqual(Set(CatalogPriceSource.allCases.map(\.currencyCode)), ["EUR", "USD"])
    }

    func testCollectionBackupTypeIsRegisteredAsJSON() {
        XCTAssertEqual(UTType.tallyDexCollection.identifier, PortableCollectionDocument.formatIdentifier)
        XCTAssertTrue(UTType.tallyDexCollection.conforms(to: .json))
        XCTAssertEqual(UTType.tallyDexCollection.preferredFilenameExtension, "pokecollection")
    }

    func testSharedCardDeepLinkRoundTripsCardIdentifier() {
        let url = CardDeepLink.url(cardID: "me02.5-076")
        XCTAssertEqual(url.absoluteString, "tallydex://card/me02.5-076")
        XCTAssertEqual(CardDeepLink.cardID(from: url), "me02.5-076")
        XCTAssertNil(CardDeepLink.cardID(from: URL(string: "https://miranoverhoef.github.io/TallyDex/card/?id=me02.5-076")!))
        XCTAssertNil(CardDeepLink.cardID(from: URL(string: "https://example.com/card")!))
    }

    func testSharedCardDocumentIsRegisteredAndRoundTripsCardIdentifier() throws {
        let document = SharedCardDocument(
            cardID: "me02.5-076",
            cardName: "Lillie's Clefairy ex"
        )
        let url = try document.temporaryURL()

        XCTAssertEqual(UTType.tallyDexCard.identifier, SharedCardDocument.formatIdentifier)
        XCTAssertEqual(url.pathExtension, "tallydexcard")
        XCTAssertEqual(SharedCardDocument.cardID(from: url), "me02.5-076")
    }

    func testFutureCardmarketCurrenciesRemainExplicit() {
        XCTAssertEqual(
            CardmarketCurrencyPreference.allCases.map(\.rawValue),
            ["EUR", "USD"]
        )
        XCTAssertEqual(PricingSettings.defaultCardmarketCurrency, .eur)
    }

    func testRichCardDetailsAreCollapsedByDefault() {
        XCTAssertFalse(CardDisplaySettings.defaultDetailsExpanded)
        XCTAssertFalse(CardDisplaySettings.detailsExpandedByDefaultKey.isEmpty)
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
