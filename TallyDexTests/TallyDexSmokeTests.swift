import XCTest
import UniformTypeIdentifiers
import UIKit
import ImageIO
import StoreKit
import StoreKitTest
@testable import TallyDex

final class TallyDexSmokeTests: XCTestCase {
    @MainActor
    func testSupplementalSetCoversAreBundledAndSmall() throws {
        for (id, name) in [
            ("tallydex-tot-2022", "Trick or Trade 2022"),
            ("tallydex-tot-2023", "Trick or Trade 2023"),
            ("tallydex-tot-2024", "Trick or Trade 2024"),
            ("mfb", "My First Battle"),
            ("sma", "Hidden Fates Shiny Vault"),
            ("xya", "Yellow A Alternate")
        ] {
            let set = CatalogSet(id: id, seriesID: "test", name: name, abbreviation: nil,
                logoURL: nil, symbolURL: nil, officialCardCount: 0, totalCardCount: 0,
                releaseDate: nil, rarityCounts: nil)
            let image = try XCTUnwrap(BundledSetLogo.image(for: set), id)
            XCTAssertLessThanOrEqual(try XCTUnwrap(image.cgImage).width, 420, id)
            XCTAssertLessThanOrEqual(try XCTUnwrap(image.cgImage).height, 160, id)
            let url = try XCTUnwrap(Bundle.main.url(forResource: id, withExtension: id == "xya" ? "png" : "webp",
                subdirectory: "BundledSetLogos"), id)
            XCTAssertLessThanOrEqual(try Data(contentsOf: url).count, 20_000, id)
        }
    }

    func testSettingsPreferencePagesHaveStableUniqueRoutes() {
        XCTAssertEqual(SettingsPreferencePage.allCases, [.browsing, .collection, .prices])
        XCTAssertEqual(Set(SettingsPreferencePage.allCases.map(\.id)).count, 3)
        XCTAssertTrue(SettingsPreferencePage.allCases.allSatisfy {
            !$0.title.isEmpty && !$0.detail.isEmpty && !$0.systemImage.isEmpty
        })
    }

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

    func testScannerRanksExactIdentityAboveReprintsAndKeepsMultipleChoices() {
        let exact = CardScanReference(id: "test-025", name: "Pikachu", localID: "025", setID: "test",
            setName: "Test", officialCount: 198, codes: ["SVI"])
        let reprint = CardScanReference(id: "other-25", name: "Pikachu", localID: "25", setID: "other",
            setName: "Other", officialCount: 102, codes: ["OTHER"])
        let ranked = CardScanRanking.rank([reprint, exact, exact], lines: ["BASIC Pikachu HP 70", "SVI EN 025/198"])
        XCTAssertEqual(ranked.map(\.id), [exact.id, reprint.id])
        XCTAssertGreaterThan(ranked[0].percentage, ranked[1].percentage)
        XCTAssertLessThan(ranked[0].percentage, 100)
        XCTAssertTrue(CardScanRanking.rank([exact], lines: ["Grocery list", "Milk and bread"]).isEmpty)
    }

    func testScannerReadsPrefixedNumbersAndRecognisesCardFrontEvidence() {
        let fractions = CardScanRanking.fractions(in: ["SV64/SV94", "TG13 / TG30"])
        XCTAssertEqual(fractions.map(\.number), ["SV64", "TG13"])
        XCTAssertTrue(CardScanOCR.looksLikeCardFront(["BASIC Pikachu HP70", "025/198"]))
        XCTAssertTrue(CardScanOCR.looksLikeCardFront(["ENERGY", "© Pokémon"]))
        XCTAssertFalse(CardScanOCR.looksLikeCardFront(["Pokémon"]))
        XCTAssertFalse(CardScanOCR.looksLikeCardFront(["Book cover", "ISBN 123456"]))
    }

    func testScannerGuideAllowsSmallOffCentreCardsButRejectsOutsideCards() {
        let guide = CardScanGuide(viewport: CGSize(width: 400, height: 800),
            rectangle: CGRect(x: 50, y: 100, width: 300, height: 420))
        let region = guide.region(in: CGSize(width: 1200, height: 1600))
        XCTAssertGreaterThan(region.minX, 0)
        XCTAssertLessThan(region.maxX, 1)
        let small = CGRect(x: region.minX + 0.01, y: region.minY + 0.01, width: 0.12, height: 0.17)
        XCTAssertTrue(CardScanGuide.contains(small, in: region))
        XCTAssertFalse(CardScanGuide.contains(CGRect(x: 0, y: 0, width: 0.1, height: 0.15), in: region))
    }

    func testScannerCopyrightYearSeparatesOtherwiseIdenticalNumberedCards() {
        let earlier = CardScanReference(id: "old-121", name: "Water Energy", localID: "121", setID: "old",
            setName: "Old", officialCount: 123, codes: [], releaseYear: 2007)
        let later = CardScanReference(id: "new-121", name: "Water Energy", localID: "121", setID: "new",
            setName: "New", officialCount: 123, codes: [], releaseYear: 2010)
        let result = CardScanRanking.rank([earlier, later], lines: ["ENERGY", "121/123", "©2010 Pokémon"])
        XCTAssertEqual(result.first?.id, later.id)
        XCTAssertEqual(CardScanRanking.fractions(in: ["SV89/5V94"]).first?.total, "SV94")
        XCTAssertTrue(CardScanRanking.numbers(in: ["SH6 ★"]).contains("SH6"))
    }

    func testScannerNameOnlyMatchingNormalisesHyphensAndApostrophes() {
        let card = CardScanReference(id: "test-SV64", name: "Lucario-GX", localID: "SV64", setID: "test",
            setName: "Test", officialCount: 94, codes: [])
        XCTAssertEqual(CardScanRanking.rank([card], lines: ["Lucario GX", "HP 210"]).first?.id, card.id)
    }

    func testScannerVisualComparisonSeparatesUnrelatedImagesAndRecognisesIdenticalArtwork() throws {
        let size = CGSize(width: 240, height: 330)
        let query = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.red.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill(); context.fill(CGRect(x: 30, y: 50, width: 180, height: 140))
        }
        let other = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill(); context.fill(CGRect(x: 70, y: 200, width: 80, height: 80))
        }
        let image = try XCTUnwrap(query.cgImage)
        let matches = try CardScanVisualComparison.rerank(
            [.init(id: "wrong", score: 0.96), .init(id: "correct", score: 0.60)], query: image,
            references: [("wrong", try XCTUnwrap(other.cgImage)), ("correct", image)])
        XCTAssertEqual(matches.first?.id, "correct")
        XCTAssertGreaterThan(matches[0].score, matches[1].score)
    }

    func testScannerRanksSavedIOSReplayWithVisualEvidence() throws {
        #if targetEnvironment(simulator)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("artifacts/scanner-benchmark")
        guard let data = try? Data(contentsOf: root.appendingPathComponent("ios-results.json")) else {
            throw XCTSkip("Run the opt-in iOS artwork replay first.")
        }
        let previous = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let references = try JSONDecoder().decode([CardScanReference].self,
            from: Data(contentsOf: root.appendingPathComponent("references.json")))
        let index = CardScanReferenceIndex(references)
        var rows: [[String: Any]] = []
        for row in previous where row["kind"] as? String == "clean" {
            let id = try XCTUnwrap(row["id"] as? String)
            let lines = try XCTUnwrap(row["lines"] as? [String])
            let ranked = try autoreleasepool {
                var ranked = CardScanRanking.rank(index.candidates(lines: lines), lines: lines, limit: 16)
                if CardScanVisualComparison.isUseful(ranked) {
                    let source = try XCTUnwrap(CGImageSourceCreateWithURL(root.appendingPathComponent("images/\(id).webp") as CFURL, nil))
                    let query = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                    var images: [(id: String, image: CGImage)] = []
                    for match in ranked {
                        let url = root.appendingPathComponent("images/\(match.id).webp")
                        if FileManager.default.fileExists(atPath: url.path),
                           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { images.append((match.id, image)) }
                    }
                    ranked = try CardScanVisualComparison.rerank(ranked, query: query, references: images)
                }
                return ranked
            }
            rows.append(["id": id, "split": row["split"] ?? "", "rank": ranked.firstIndex { $0.id == id }.map { $0 + 1 } ?? 0,
                         "candidates": ranked.prefix(5).map { ["id": $0.id, "score": $0.percentage] }])
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
            .write(to: root.appendingPathComponent("ios-final-ranked-results.json"), options: .atomic)
        let top1 = rows.filter { $0["rank"] as? Int == 1 }.count
        let top3 = rows.filter { (1...3).contains($0["rank"] as? Int ?? 0) }.count
        print("Scanner final iOS replay: \(rows.count), top1 \(top1), top3 \(top3)")
        XCTAssertGreaterThanOrEqual(rows.count, 300)
        XCTAssertGreaterThanOrEqual(Double(top1) / Double(rows.count), 0.95)
        #else
        throw XCTSkip("Local artwork replay runs on the simulator.")
        #endif
    }

    func testScannerArtworkReplayBenchmark() async throws {
        #if targetEnvironment(simulator)
        struct Sample: Decodable { let id: String; let image: String?; let split: String? }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("artifacts/scanner-benchmark")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path) else {
            throw XCTSkip("Opt-in replay: run Scripts/prepare_scanner_benchmark.py first.")
        }
        let references = try JSONDecoder().decode([CardScanReference].self,
            from: Data(contentsOf: root.appendingPathComponent("references.json")))
        let index = CardScanReferenceIndex(references)
        let samples = try JSONDecoder().decode([Sample].self,
            from: Data(contentsOf: root.appendingPathComponent("manifest.json"))).filter { $0.image != nil }
        var rows: [[String: Any]] = []
        for (offset, sample) in samples.enumerated() {
            let bytes = try Data(contentsOf: root.appendingPathComponent(sample.image!))
            let source = try XCTUnwrap(UIImage(data: bytes))
            var cases: [(String, UIImage, CardScanGuide?)] = [("clean", source, nil)]
            if offset % 12 == 0 {
                let size = CGSize(width: 1000, height: 1400)
                let x: CGFloat = offset % 24 == 0 ? 130 : 530
                let y: CGFloat = offset % 24 == 0 ? 180 : 740
                let frame = UIGraphicsImageRenderer(size: size).image { context in
                    UIColor.darkGray.setFill(); context.fill(CGRect(origin: .zero, size: size))
                    source.draw(in: CGRect(x: x, y: y, width: 300, height: 413))
                }
                cases.append(("off-centre", frame,
                    CardScanGuide(viewport: size, rectangle: CGRect(x: 80, y: 80, width: 840, height: 1240))))
            }
            for (kind, image, guide) in cases {
                let detected: CardRectangleDetectionResult
                if let guide { detected = await CardRectangleDetector.detect(in: image, guide: guide) }
                else { detected = CardRectangleDetectionResult(cardImage: image, corners: nil) }
                let lines = try await CardTextRecognizer.recognize(detected.cardImage)
                let ranked = CardScanRanking.rank(index.candidates(lines: lines), lines: lines)
                let rank = ranked.firstIndex { $0.id == sample.id }.map { $0 + 1 } ?? 0
                rows.append(["id": sample.id, "split": sample.split ?? "", "kind": kind, "rank": rank,
                             "detected": detected.corners != nil, "lines": lines,
                             "candidates": ranked.map { ["id": $0.id, "score": $0.percentage] }])
            }
            if offset % 20 == 0 {
                print("Scanner iOS replay \(offset + 1)/\(samples.count)")
                try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
                    .write(to: root.appendingPathComponent("ios-results.json"), options: .atomic)
            }
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
            .write(to: root.appendingPathComponent("ios-results.json"), options: .atomic)
        let clean = rows.filter { $0["kind"] as? String == "clean" }
        let top1 = clean.filter { $0["rank"] as? Int == 1 }.count
        let top3 = clean.filter { (1...3).contains($0["rank"] as? Int ?? 0) }.count
        let scenes = rows.filter { $0["kind"] as? String == "off-centre" }
        print("Scanner iOS clean \(clean.count), top1 \(top1), top3 \(top3); scene detections \(scenes.filter { $0["detected"] as? Bool == true }.count)/\(scenes.count)")
        XCTAssertGreaterThanOrEqual(clean.count, 300)
        XCTAssertGreaterThanOrEqual(Double(top3) / Double(clean.count), 0.90)
        XCTAssertGreaterThanOrEqual(Double(scenes.filter { $0["detected"] as? Bool == true }.count) / Double(scenes.count), 0.85)
        #else
        throw XCTSkip("Local artwork replay runs on the simulator.")
        #endif
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

    func testBundledPrivacyManifestDeclaresLocalPreferencesAndCacheMetadata() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        let entries = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let preferences = try XCTUnwrap(entries.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        })
        XCTAssertEqual(preferences["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
        let timestamps = try XCTUnwrap(entries.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryFileTimestamp"
        })
        XCTAssertEqual(timestamps["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])
    }

    func testCurrentReleaseNotesAreUsefulAndUnique() {
        XCTAssertEqual(AppReleaseNotes.current.version, "0.9.64")
        XCTAssertGreaterThanOrEqual(AppReleaseNotes.current.notes.count, 1)
        XCTAssertEqual(
            Set(AppReleaseNotes.current.notes.map(\.id)).count,
            AppReleaseNotes.current.notes.count
        )
        XCTAssertTrue(AppReleaseNotes.current.notes.allSatisfy { !$0.detail.isEmpty })
    }

    func testDashboardPreviewRequiresValidCodeAndExplicitEnablement() {
        XCTAssertFalse(PreviewFeatures.dashboardReleased)
        XCTAssertTrue(PreviewFeatures.acceptsDashboardCode("Dashboard021026"))
        XCTAssertTrue(PreviewFeatures.acceptsDashboardCode(" Dashboard021026\n"))
        XCTAssertFalse(PreviewFeatures.acceptsDashboardCode("dashboard021026"))
        XCTAssertFalse(PreviewFeatures.acceptsDashboardCode(""))
        XCTAssertFalse(PreviewFeatures.dashboardEnabled(unlocked: false, enabled: false))
        XCTAssertFalse(PreviewFeatures.dashboardEnabled(unlocked: false, enabled: true))
        XCTAssertFalse(PreviewFeatures.dashboardEnabled(unlocked: true, enabled: false))
        XCTAssertTrue(PreviewFeatures.dashboardEnabled(unlocked: true, enabled: true))
        XCTAssertTrue(PreviewFeatures.dashboardEnabled(unlocked: false, enabled: false, released: true))
    }

    func testReleaseFeaturesRequireExplicitDistributionChannel() {
        XCTAssertEqual(AppDistributionChannel.resolve(nil), .development)
        XCTAssertEqual(AppDistributionChannel.resolve("invalid"), .development)
        XCTAssertFalse(AppDistributionChannel.development.enablesReleaseFeatures)
        XCTAssertTrue(AppDistributionChannel.resolve("testflight").enablesReleaseFeatures)
        XCTAssertTrue(AppDistributionChannel.resolve("public").enablesReleaseFeatures)
        XCTAssertTrue(AppReleaseNotes.history(channel: .development).isEmpty)
        let current = AppRelease(version: "1.10", headline: "Current", notes: [])
        let previous = AppRelease(version: "1.9", headline: "Previous", notes: [])
        XCTAssertEqual(AppReleaseNotes.history(channel: .testflight, current: current,
            archive: [previous, current]).map(\.version), ["1.10", "1.9"])
    }

    func testTrialPolicyUsesFourteenDaysAndRejectsClockRollback() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let trial = TrialAnchor(startedAt: start, lastSeenAt: start)
        XCTAssertEqual(
            AccessPolicy.status(enforced: false, hasVerifiedLifetime: false, anchor: nil, now: start),
            .earlyAccess
        )
        XCTAssertEqual(
            AccessPolicy.status(enforced: true, hasVerifiedLifetime: false, anchor: nil, now: start),
            .notStarted
        )
        XCTAssertEqual(
            AccessPolicy.status(enforced: true, hasVerifiedLifetime: false, anchor: trial, now: start),
            .trial(daysRemaining: 14)
        )
        let end = start.addingTimeInterval(AccessConfiguration.trialDuration)
        XCTAssertEqual(
            AccessPolicy.status(enforced: true, hasVerifiedLifetime: false, anchor: trial, now: end),
            .expired
        )
        let advanced = AccessPolicy.advancing(trial, to: end)
        XCTAssertEqual(
            AccessPolicy.status(enforced: true, hasVerifiedLifetime: false, anchor: advanced, now: start),
            .expired
        )
        XCTAssertEqual(
            AccessPolicy.status(enforced: true, hasVerifiedLifetime: true, anchor: advanced, now: end),
            .lifetime
        )
    }

    @MainActor
    func testTrialCanStartWithoutStoreConnection() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let storage = MemoryTrialAnchorStore(anchor: nil)
        let access = AccessStore(enforced: true, anchorStore: storage, now: { now })
        try access.startTrial()
        XCTAssertEqual(access.status, .trial(daysRemaining: 14))
        XCTAssertTrue(access.canEdit)
        XCTAssertEqual(storage.anchor?.startedAt, now)
    }

    @MainActor
    func testKeychainTrialAnchorRoundTrips() throws {
        let storage = KeychainTrialAnchorStore(namespace: "unit-test")
        let anchor = TrialAnchor(startedAt: Date(timeIntervalSince1970: 1_000_000),
                                 lastSeenAt: Date(timeIntervalSince1970: 1_000_000))
        try storage.save(anchor)
        XCTAssertEqual(try storage.load(), anchor)
        let advanced = TrialAnchor(startedAt: anchor.startedAt,
                                   lastSeenAt: anchor.lastSeenAt.addingTimeInterval(86_400))
        try storage.save(advanced)
        XCTAssertEqual(try storage.load(), advanced)
    }

    @MainActor
    func testLocalStoreKitConfigurationProvidesLifetimeProduct() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Products", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.locale = Locale(identifier: "en_US")
        session.storefront = "NLD"
        let products = try await Product.products(for: AccessConfiguration.productIDs)
        XCTAssertEqual(products.count, 5)
        let lifetime = try XCTUnwrap(products.first { $0.id == AccessConfiguration.lifetimeProductID })
        XCTAssertEqual(lifetime.type, .nonConsumable)
        XCTAssertTrue(lifetime.displayPrice.contains("€"))
        XCTAssertTrue(lifetime.displayPrice.contains("9.99"))
        for (tier, expectedPrice) in [
            (CoffeeTipTier.espresso, "1.99"),
            (.coffee, "2.99"),
            (.largeCoffee, "4.99"),
            (.coffeeRound, "9.99")
        ] {
            let product = try XCTUnwrap(products.first { $0.id == tier.productID })
            XCTAssertEqual(product.type, .consumable)
            XCTAssertTrue(product.displayPrice.contains("€"), "Displayed: \(product.displayPrice)")
            XCTAssertTrue(product.displayPrice.contains(expectedPrice), "Displayed: \(product.displayPrice)")
        }
        XCTAssertEqual(Set(AccessConfiguration.productIDs).count, 5)
    }

    @MainActor
    func testVerifiedLifetimePurchaseUnlocksExpiredTrial() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Products", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: AccessConfiguration.lifetimeProductID)
        XCTAssertEqual(transaction.productID, AccessConfiguration.lifetimeProductID)

        let start = Date(timeIntervalSince1970: 1_000_000)
        let expired = TrialAnchor(startedAt: start, lastSeenAt: start.addingTimeInterval(AccessConfiguration.trialDuration))
        let access = AccessStore(
            enforced: true,
            anchorStore: MemoryTrialAnchorStore(anchor: expired),
            now: { start }
        )
        await access.start()
        XCTAssertEqual(access.status, .lifetime)
        XCTAssertTrue(access.canEdit)
    }

    @MainActor
    func testLifetimeCheckoutCompletesInLocalStoreKit() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Products", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let access = AccessStore(enforced: true, anchorStore: MemoryTrialAnchorStore(anchor: nil))
        await access.start()
        XCTAssertNotNil(access.lifetimeProduct)
        await access.purchaseLifetime()
        XCTAssertEqual(access.status, .lifetime, access.message ?? "No purchase error")
        XCTAssertTrue(access.canEdit)
    }

    @MainActor
    func testCoffeeTipCanBePurchasedWithoutUnlockingApp() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Products", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let access = AccessStore(enforced: true, anchorStore: MemoryTrialAnchorStore(anchor: nil))
        await access.start()
        XCTAssertEqual(access.tipProducts.count, 4)
        XCTAssertEqual(access.status, .notStarted)
        await access.purchaseTip(.espresso)
        XCTAssertEqual(access.tipMessage, "Thank you for supporting TallyDex!")
        XCTAssertEqual(access.status, .notStarted)
        XCTAssertFalse(access.canEdit)
        await access.purchaseTip(.espresso)
        XCTAssertEqual(access.tipMessage, "Thank you for supporting TallyDex!")
    }

    @MainActor
    func testExpiredTrialBlocksCollectionChangesButKeepsExportAvailable() async throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let expired = TrialAnchor(
            startedAt: start,
            lastSeenAt: start.addingTimeInterval(AccessConfiguration.trialDuration)
        )
        let access = AccessStore(enforced: true, anchorStore: MemoryTrialAnchorStore(anchor: expired), now: { start })
        access.tick()
        let repository = GRDBCollectionRepository(database: try CollectionDatabase.inMemory())
        let collection = CollectionStore(repository: repository, accessStore: access, now: { start })

        do {
            try await collection.setQuantity(1, cardID: "test-001", variant: .normal)
            XCTFail("An expired trial must not edit ownership")
        } catch AccessError.editingRequiresAccess {
            XCTAssertTrue(access.isMembershipPresented)
        }
        let readOnlyExport = try await collection.exportDocument()
        XCTAssertTrue(readOnlyExport.ownership.isEmpty)

        let active = AccessStore(
            enforced: true,
            anchorStore: MemoryTrialAnchorStore(anchor: .init(startedAt: start, lastSeenAt: start)),
            now: { start }
        )
        active.tick()
        let editable = CollectionStore(repository: repository, accessStore: active, now: { start })
        try await editable.setQuantity(1, cardID: "test-001", variant: .normal)
        let editableExport = try await editable.exportDocument()
        XCTAssertEqual(editableExport.ownership.first?.quantity, 1)
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

@MainActor
private final class MemoryTrialAnchorStore: TrialAnchorStoring {
    var anchor: TrialAnchor?

    init(anchor: TrialAnchor?) { self.anchor = anchor }
    func load() throws -> TrialAnchor? { anchor }
    func save(_ anchor: TrialAnchor) throws { self.anchor = anchor }
}
