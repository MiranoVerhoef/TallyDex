import XCTest

final class ReliabilityUITests: XCTestCase {
    private var app: XCUIApplication!
    private let testID = UUID().uuidString

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ReliabilityUITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["TALLYDEX_UI_TEST_ID"] = testID
    }

    override func tearDownWithError() throws { app.terminate() }

    private func launch(_ scenario: String) {
        app.launchEnvironment["TALLYDEX_UI_TEST_SCENARIO"] = scenario
        app.launch()
    }

    private func button(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
        for _ in 0..<8 {
            if element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, file: file, line: line)
        element.tap()
    }

    private func expectState(_ pieces: [String], file: StaticString = #filePath, line: UInt = #line) {
        let state = app.otherElements["reliability.state"].staticTexts.firstMatch
        let predicate = NSPredicate { _, _ in
            guard state.exists else { return false }
            let value = state.label
            return pieces.allSatisfy(value.contains) && value.contains("error=none")
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 10)
        if result != .completed {
            print(app.debugDescription)
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(result, .completed, "Expected \(pieces); actual: \(state.exists ? state.label : "missing probe")",
                       file: file, line: line)
    }

    private func settings() { tap(app.tabBars.buttons["Settings"]) }
    private func back() { tap(app.navigationBars.buttons.firstMatch) }

    private func capturePurchaseScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureAppStoreScreenshots() throws {
        guard ProcessInfo.processInfo.environment["TALLYDEX_CAPTURE_STORE_SCREENSHOTS"] == "1" else {
            throw XCTSkip("Opt-in live catalogue capture, not a reliability test")
        }
        launch("screenshots")
        let state = app.otherElements["reliability.state"].staticTexts.firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            state.exists && state.label.contains("owned=9") && state.label.contains("error=none")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 180), .completed)
        capturePurchaseScreen("01-Browse-series")
        tap(app.tabBars.buttons["Collection"])
        XCTAssertTrue(button("Pikachu").waitForExistence(timeout: 30))
        capturePurchaseScreen("02-Your-collection")
        tap(button("Binder Planner"))
        tap(button("Base Set Binder"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Side 1 of")).firstMatch.waitForExistence(timeout: 60))
        // Wait for on-demand artwork requests without changing the displayed UI.
        let artwork = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Charizard,")).firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [artwork], timeout: 30), .completed)
        Thread.sleep(forTimeInterval: 3)
        capturePurchaseScreen("03-Binder-planning")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Charizard,")).firstMatch)
        XCTAssertTrue(app.navigationBars["Charizard"].waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 3)
        capturePurchaseScreen("04-Card-artwork")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.51)))
        capturePurchaseScreen("05-Track-printings")
        tap(app.tabBars.buttons["Settings"])
        tap(button("Export & Import"))
        XCTAssertTrue(app.navigationBars["Export & Import"].waitForExistence(timeout: 10))
        capturePurchaseScreen("06-Export-and-import")
    }

    private func confirm(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", label))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            buttons.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed { print(app.debugDescription) }
        XCTAssertEqual(result, .completed, "Missing confirmation: \(label)", file: file, line: line)
        buttons.allElementsBoundByIndex.first { $0.isHittable }?.tap()
    }

    private func turnOn(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let control = app.switches[label]
        XCTAssertTrue(control.waitForExistence(timeout: 10), file: file, line: line)
        if control.value as? String != "1" {
            // SwiftUI exposes the entire labelled row as a Switch. Activate its
            // trailing native control rather than the non-interactive label.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func openFilterCollection() {
        launch("filters")
        expectState(["normal=7;stamp=2", "owned=1", "backups=2"])
        tap(app.tabBars.buttons["Collection"])
        tap(button("Filter fixture"))
        expectVisible(4)
    }

    private func expectVisible(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["\(count) of 4 cards"].waitForExistence(timeout: 10), file: file, line: line)
    }

    func testSetSearchHidesSummaryAndRestoresItWhenCancelled() {
        launch("filters")
        expectState(["owned=1", "error=none"])
        tap(app.tabBars.buttons["Sets"])
        tap(button("Sword & Shield"))
        let expansion = button("Fusion Strike")
        for _ in 0..<12 {
            if expansion.exists { break }
            app.swipeUp()
        }
        if !expansion.exists { print(app.debugDescription) }
        tap(expansion)
        let summary = app.staticTexts["set.summary.progress"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        let search = app.searchFields.firstMatch
        for _ in 0..<3 {
            if search.exists { break }
            app.swipeDown()
        }
        if !search.exists {
            print(app.debugDescription)
            capturePurchaseScreen("Set search control triage")
        }
        let restingSummaryY = summary.frame.minY
        for query in ["16", "no-matching-card", "16"] {
            tap(search)
            XCTAssertFalse(summary.exists)
            search.typeText(query)
            XCTAssertTrue(app.staticTexts[query == "16" ? "1 cards" : "0 cards"].waitForExistence(timeout: 10))
            XCTAssertFalse(summary.exists)
            capturePurchaseScreen("Set search with compact results")
            let cancel = app.buttons["Cancel"].exists ? app.buttons["Cancel"] : app.buttons["Close"]
            tap(cancel)
            XCTAssertTrue(summary.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["3 cards"].waitForExistence(timeout: 10))
            XCTAssertEqual(summary.frame.minY, restingSummaryY, accuracy: 4,
                "Cancelling search should restore the same header position")
            capturePurchaseScreen("Set summary after cancelling search")
        }
        expectState(["owned=1", "error=none"])
    }

    func testSetsDashboardShowsCollectionWideCounts() {
        launch("filters")
        expectState(["owned=1", "error=none"])
        enableDashboardPreview()
        tap(app.tabBars.buttons["Sets"])
        XCTAssertTrue(app.staticTexts["Collection value"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Distinct"].exists)
        XCTAssertTrue(app.staticTexts["Copies"].exists)
        XCTAssertTrue(app.staticTexts["Sets"].exists)
        let snapshot = XCTAttachment(screenshot: app.screenshot())
        snapshot.name = "Integrated dashboard header"
        snapshot.lifetime = .keepAlways
        add(snapshot)
    }

    private func openPreviewFeatures() {
        settings()
        let advanced = button("Advanced")
        for _ in 0..<8 {
            if advanced.exists && advanced.isHittable { break }
            app.swipeUp()
        }
        tap(advanced)
        tap(app.buttons["settings.previewFeatures"])
    }

    private func enableDashboardPreview() {
        openPreviewFeatures()
        let code = app.secureTextFields["preview.code"]
        tap(code)
        code.typeText("Dashboard021026")
        tap(app.buttons["preview.unlock"])
    }

    func testDashboardPreviewIsHiddenByDefaultAndCodeChoicePersists() {
        launch("filters")
        XCTAssertFalse(app.staticTexts["Collection value"].exists)
        openPreviewFeatures()
        let code = app.secureTextFields["preview.code"]
        tap(code)
        code.typeText("wrong-code")
        tap(app.buttons["preview.unlock"])
        XCTAssertTrue(app.staticTexts["Code not recognized."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["preview.dashboard"].exists)
        tap(code)
        code.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "Dashboard021026")
        tap(app.buttons["preview.unlock"])
        XCTAssertTrue(app.switches["preview.dashboard"].waitForExistence(timeout: 5))
        tap(app.tabBars.buttons["Sets"])
        XCTAssertTrue(app.staticTexts["Collection value"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Collection value"].waitForExistence(timeout: 5))
        openPreviewFeatures()
        let toggle = app.switches["preview.dashboard"]
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        tap(app.tabBars.buttons["Sets"])
        XCTAssertFalse(app.staticTexts["Collection value"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Sets"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Collection value"].exists)
        expectState(["owned=1", "error=none"])
    }

    private func chooseFilter(_ label: String, option: String) {
        tap(app.buttons[label])
        tap(app.buttons[option])
        if app.navigationBars[label].exists { back() }
    }

    func testCollectionFilterApplyCancelIntersectionAndEmptyResetLeaveOwnershipUntouched() {
        openFilterCollection()
        tap(app.buttons["collection.filters.open"])
        chooseFilter("Type", option: "Grass")
        tap(app.buttons["collection.filters.apply"])
        expectVisible(2)
        XCTAssertTrue(app.staticTexts["25% owned"].exists)
        tap(app.buttons["collection.filters.open"])
        chooseFilter("Type", option: "Psychic")
        tap(app.buttons["collection.filters.cancel"])
        expectVisible(2)
        tap(app.buttons["collection.filters.open"])
        chooseFilter("Era", option: "Scarlet & Violet")
        tap(app.buttons["collection.filters.apply"])
        expectVisible(1)
        tap(app.buttons["collection.filters.open"])
        chooseFilter("Rarity", option: "Common")
        tap(app.buttons["collection.filters.apply"])
        XCTAssertTrue(app.staticTexts["No Cards for These Filters"].waitForExistence(timeout: 10))
        tap(app.buttons["collection.filters.clear"])
        expectVisible(4)
        back()
        expectState(["normal=7;stamp=2", "owned=1", "backups=2"])
    }

    func testCollectionEraClearsIncompatibleExactSetAndSheetResetCanBeCancelled() {
        openFilterCollection()
        tap(app.buttons["collection.filters.open"])
        chooseFilter("Set", option: "Fusion Strike (swsh8)")
        tap(app.buttons["collection.filters.apply"])
        expectVisible(3) // Includes the card with unavailable type and rarity.
        tap(app.buttons["collection.filters.open"])
        chooseFilter("Era", option: "Scarlet & Violet")
        tap(app.buttons["collection.filters.apply"])
        expectVisible(1)
        tap(app.buttons["collection.filters.open"])
        tap(app.buttons["collection.filters.reset"])
        tap(app.buttons["collection.filters.cancel"])
        expectVisible(1)
        tap(app.buttons["collection.filters.open"])
        tap(app.buttons["collection.filters.reset"])
        tap(app.buttons["collection.filters.apply"])
        expectVisible(4)
        back()
        expectState(["normal=7;stamp=2", "owned=1", "backups=2"])
    }

    func testBinderPlannerCreatesAndOpensLocalPlan() {
        launch("filters")
        tap(app.tabBars.buttons["Collection"])
        tap(button("Binder Planner"))
        XCTAssertTrue(app.navigationBars["Binder Planner"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["New plan"].exists)
        tap(button("Create binder plan"))
        XCTAssertTrue(app.navigationBars["New Binder Plan"].waitForExistence(timeout: 10))
        tap(button("Card order"))
        tap(app.buttons["Release year · newest first"])
        if app.navigationBars["Card order"].exists { back() }
        tap(button("Background color"))
        tap(app.buttons["Blue"])
        if app.navigationBars["Background color"].exists { back() }
        let name = app.textFields["Name (optional)"]
        tap(name)
        name.typeText("Test Binder")
        tap(app.buttons["Save"])
        let savedPlan = button("Test Binder")
        XCTAssertTrue(savedPlan.waitForExistence(timeout: 10))
        XCTAssertTrue(savedPlan.label.contains("Release year · newest first"))
        savedPlan.press(forDuration: 1)
        tap(app.buttons["Edit"])
        XCTAssertTrue(app.navigationBars["Edit Binder Plan"].waitForExistence(timeout: 10))
        XCTAssertTrue(button("Card order").label.contains("Release year · newest first"))
        XCTAssertEqual(button("Background color").value as? String, "Blue")
        tap(app.buttons["Cancel"])
        tap(savedPlan)
        XCTAssertTrue(app.staticTexts["Side 1 of 1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "slots owned")).firstMatch.exists)
        expectState(["normal=7;stamp=2", "owned=1", "backups=2"])
    }

    func testCollectorBadgesCountExistingCollectionAndKeepOwnershipUnchanged() {
        launch("filters")
        tap(app.tabBars.buttons["Collection"])
        tap(button("Collector Badges"))
        XCTAssertTrue(app.navigationBars["Collector Badges"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["First Find"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Earned ")).firstMatch.exists)
        expectState(["normal=7;stamp=2", "owned=1", "backups=2"])
    }

    func testCompletingSetupDoesNotRepeatOrShowWhatsNew() {
        launch("fresh")
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 10))
        for _ in 0..<3 { tap(app.buttons["Continue"]) }
        XCTAssertFalse(app.staticTexts["Help improve scanning"].exists)
        tap(app.buttons["Start Collecting"])
        expectState(["intro=true", "seen=0.9.48"])
        XCTAssertFalse(app.buttons["Skip"].exists)
        XCTAssertFalse(app.staticTexts["What’s New in TallyDex"].exists)
        app.terminate()
        app.launch()
        expectState(["intro=true", "seen=0.9.48"])
        XCTAssertFalse(app.buttons["Continue"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)
    }

    func testSkippingSetupIsAlsoPersisted() {
        launch("fresh")
        tap(app.buttons["Skip"])
        expectState(["intro=true", "seen=0.9.48"])
        app.terminate()
        app.launch()
        expectState(["intro=true", "seen=0.9.48"])
        XCTAssertFalse(app.buttons["Skip"].exists)
        XCTAssertFalse(app.buttons["Continue"].exists)
    }

    func testUpdateNotesAppearOnceWithoutRepeatingSetup() {
        launch("update")
        XCTAssertTrue(app.staticTexts["What’s New in TallyDex"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Skip"].exists)
        tap(app.buttons["Continue"])
        expectState(["intro=true", "seen=0.9.48"])
        app.terminate()
        app.launch()
        expectState(["intro=true", "seen=0.9.48"])
        XCTAssertFalse(app.buttons["Continue"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)
    }

    func testLocalStoreKitTrialStartsWithoutChangingCollection() {
        app.launchArguments.append("-AccessGateTesting")
        launch("filters")
        let startTrial = app.buttons["Start 14-Day Trial"]
        XCTAssertTrue(startTrial.waitForExistence(timeout: 20))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: startTrial)
        XCTAssertEqual(
            XCTWaiter.wait(for: [enabled], timeout: 15), .completed,
            "The local StoreKit lifetime product should be available"
        )
        capturePurchaseScreen("Lifetime-access-review")
        tap(startTrial)
        expectState(["normal=7;stamp=2", "owned=1", "backups=2"])
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: startTrial
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        settings()
        for _ in 0..<5 {
            if button("Lifetime Access").exists { break }
            app.swipeUp()
        }
        tap(button("Lifetime Access"))
        let trialStatus = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "14 days left"))
            .firstMatch
        XCTAssertTrue(trialStatus.waitForExistence(timeout: 10))
    }

    func testOptionalCoffeeTipsAppearWithoutAccessGate() {
        launch("filters")
        settings()
        let tipJar = button("Buy Me a Coffee")
        for _ in 0..<6 {
            if tipJar.exists { break }
            app.swipeUp()
        }
        tap(tipJar)
        for tier in ["espresso", "regular", "large", "round"] {
            XCTAssertTrue(app.buttons["tip.\(tier)"].waitForExistence(timeout: 10))
        }
        let loadedTips = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: app.buttons["tip.round"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [loadedTips], timeout: 15), .completed)
        capturePurchaseScreen("Coffee-tips-review")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Tips are optional")
        ).firstMatch.exists)
    }

    func testSettingsHelpAndActiveMarketplaceOptionsRemainAvailable() {
        launch("restore")
        settings()
        XCTAssertFalse(button("Scanner Feedback").exists)
        tap(button("Prices & Currency"))
        XCTAssertFalse(app.buttons["Future Cardmarket Listings"].exists)
        XCTAssertFalse(app.staticTexts["Future Cardmarket Listings"].exists)
        tap(app.buttons["About Prices"])
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Currencies are never mixed")
        ).firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["Done"])
        tap(button("Show prices from"))
        XCTAssertTrue(button("Cardmarket").waitForExistence(timeout: 5))
        XCTAssertTrue(button("TCGplayer").exists)
        XCTAssertTrue(button("Both").exists)
        back()
        back()
        tap(button("Appearance & Browsing"))
        XCTAssertTrue(app.switches["Expand card details by default"].exists)
        tap(app.buttons["About Sets"])
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Series First")
        ).firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["Done"])
        XCTAssertTrue(app.switches["Expand card details by default"].exists)
    }

    func testRestoreCancelConfirmRollbackAndPreferencePersistence() {
        launch("restore")
        expectState(["normal=7;stamp=2", "owned=1", "backups=2"])
        settings()
        tap(button("Appearance & Browsing"))
        turnOn("Expand card details by default")
        XCTAssertEqual(app.switches["Expand card details by default"].value as? String, "1")
        back()
        tap(button("Collection Preferences"))
        turnOn("Track multiple copies")
        XCTAssertEqual(app.switches["Track multiple copies"].value as? String, "1")
        back()
        tap(button("Prices & Currency"))
        tap(button("Use for collection value"))
        tap(button("TCGplayer (USD)"))
        if app.navigationBars["Use for collection value"].exists { back() }
        back()
        tap(button("Collection Backups"))
        tap(button("Reliability baseline"))
        XCTAssertTrue(app.navigationBars["Restore Preview"].waitForExistence(timeout: 10))
        tap(app.navigationBars.buttons["Cancel"])
        expectState(["normal=7;stamp=2", "backups=2"])
        tap(button("Reliability baseline"))
        tap(app.buttons["restore.apply"])
        confirm("Restore Collection")
        expectState(["normal=3;stamp=4", "owned=1", "backups=3"])
        tap(button("Before restoring: Reliability baseline"))
        tap(app.buttons["restore.apply"])
        confirm("Restore Collection")
        expectState(["normal=7;stamp=2", "owned=1", "backups=4"])
        app.terminate()
        app.launch()
        expectState(["normal=7;stamp=2", "backups=4"])
        settings()
        tap(button("Appearance & Browsing"))
        XCTAssertEqual(app.switches["Expand card details by default"].value as? String, "1")
        back()
        tap(button("Collection Preferences"))
        XCTAssertEqual(app.switches["Track multiple copies"].value as? String, "1")
        back()
        tap(button("Prices & Currency"))
        let priceSource = button("Use for collection value")
        XCTAssertTrue((priceSource.label + (priceSource.value as? String ?? "")).contains("TCGplayer")
                      || priceSource.staticTexts["TCGplayer (USD)"].exists,
                      "Unexpected price source: \(priceSource.debugDescription)")
    }

    func testMergePreservesNewerPrintingQuantitiesAndAddsOnlyNewIdentity() {
        launch("merge")
        XCTAssertTrue(app.navigationBars["Import Preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Conflicts kept on this iPhone"].exists)
        tap(app.buttons["import.apply"])
        expectState(["normal=7;stamp=2", "incoming=2", "owned=2", "backups=3"])
        app.terminate()
        app.launch()
        expectState(["normal=7;stamp=2", "incoming=2", "backups=3"])
    }

    func testReplaceRequiresConfirmationAndCanBeRolledBack() {
        launch("replace")
        XCTAssertTrue(app.navigationBars["Import Preview"].waitForExistence(timeout: 10))
        tap(app.buttons["Replace"])
        tap(app.buttons["import.apply"])
        confirm("Replace Collection")
        expectState(["normal=3;stamp=4", "incoming=2", "owned=2", "backups=3"])
        settings()
        tap(button("Collection Backups"))
        tap(button("Before replace import"))
        tap(app.buttons["restore.apply"])
        confirm("Restore Collection")
        expectState(["normal=7;stamp=2", "incoming=0", "owned=1", "backups=4"])
    }
}
