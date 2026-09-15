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
        expectState(["normal=7;stamp=2", "owned=1", "backups=1"])
        tap(app.tabBars.buttons["Collection"])
        tap(button("Filter fixture"))
        expectVisible(4)
    }

    private func expectVisible(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["\(count) of 4 cards"].waitForExistence(timeout: 10), file: file, line: line)
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
        expectState(["normal=7;stamp=2", "owned=1", "backups=1"])
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
        expectState(["normal=7;stamp=2", "owned=1", "backups=1"])
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
        tap(app.buttons["Cancel"])
        tap(savedPlan)
        XCTAssertTrue(app.staticTexts["Side 1 of 1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "slots owned")).firstMatch.exists)
        expectState(["normal=7;stamp=2", "owned=1", "backups=1"])
    }

    func testCompletingSetupDoesNotRepeatOrShowWhatsNew() {
        launch("fresh")
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 10))
        for _ in 0..<3 { tap(app.buttons["Continue"]) }
        tap(app.buttons["Start Collecting"])
        expectState(["intro=true", "seen=0.9.29"])
        XCTAssertFalse(app.buttons["Skip"].exists)
        XCTAssertFalse(app.staticTexts["What’s New in TallyDex"].exists)
        app.terminate()
        app.launch()
        expectState(["intro=true", "seen=0.9.29"])
        XCTAssertFalse(app.buttons["Continue"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)
    }

    func testSkippingSetupIsAlsoPersisted() {
        launch("fresh")
        tap(app.buttons["Skip"])
        expectState(["intro=true", "seen=0.9.29"])
        app.terminate()
        app.launch()
        expectState(["intro=true", "seen=0.9.29"])
        XCTAssertFalse(app.buttons["Skip"].exists)
        XCTAssertFalse(app.buttons["Continue"].exists)
    }

    func testUpdateNotesAppearOnceWithoutRepeatingSetup() {
        launch("update")
        XCTAssertTrue(app.staticTexts["What’s New in TallyDex"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Skip"].exists)
        tap(app.buttons["Continue"])
        expectState(["intro=true", "seen=0.9.29"])
        app.terminate()
        app.launch()
        expectState(["intro=true", "seen=0.9.29"])
        XCTAssertFalse(app.buttons["Continue"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)
    }

    func testRestoreCancelConfirmRollbackAndPreferencePersistence() {
        launch("restore")
        expectState(["normal=7;stamp=2", "owned=1", "backups=1"])
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
        tap(button("Price source"))
        tap(button("TCGplayer (USD)"))
        if app.navigationBars["Price source"].exists { back() }
        back()
        tap(button("Collection Backups"))
        tap(button("Reliability baseline"))
        XCTAssertTrue(app.navigationBars["Restore Preview"].waitForExistence(timeout: 10))
        tap(app.navigationBars.buttons["Cancel"])
        expectState(["normal=7;stamp=2", "backups=1"])
        tap(button("Reliability baseline"))
        tap(app.buttons["restore.apply"])
        confirm("Restore Collection")
        expectState(["normal=3;stamp=4", "owned=1", "backups=2"])
        tap(button("Before restoring: Reliability baseline"))
        tap(app.buttons["restore.apply"])
        confirm("Restore Collection")
        expectState(["normal=7;stamp=2", "owned=1", "backups=3"])
        app.terminate()
        app.launch()
        expectState(["normal=7;stamp=2", "backups=3"])
        settings()
        tap(button("Appearance & Browsing"))
        XCTAssertEqual(app.switches["Expand card details by default"].value as? String, "1")
        back()
        tap(button("Collection Preferences"))
        XCTAssertEqual(app.switches["Track multiple copies"].value as? String, "1")
        back()
        tap(button("Prices & Currency"))
        let priceSource = button("Price source")
        XCTAssertTrue((priceSource.label + (priceSource.value as? String ?? "")).contains("TCGplayer")
                      || priceSource.staticTexts["TCGplayer (USD)"].exists,
                      "Unexpected price source: \(priceSource.debugDescription)")
    }

    func testMergePreservesNewerPrintingQuantitiesAndAddsOnlyNewIdentity() {
        launch("merge")
        XCTAssertTrue(app.navigationBars["Import Preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Conflicts kept on this iPhone"].exists)
        tap(app.buttons["import.apply"])
        expectState(["normal=7;stamp=2", "incoming=2", "owned=2", "backups=2"])
        app.terminate()
        app.launch()
        expectState(["normal=7;stamp=2", "incoming=2", "backups=2"])
    }

    func testReplaceRequiresConfirmationAndCanBeRolledBack() {
        launch("replace")
        XCTAssertTrue(app.navigationBars["Import Preview"].waitForExistence(timeout: 10))
        tap(app.buttons["Replace"])
        tap(app.buttons["import.apply"])
        confirm("Replace Collection")
        expectState(["normal=3;stamp=4", "incoming=2", "owned=2", "backups=2"])
        settings()
        tap(button("Collection Backups"))
        tap(button("Before replace import"))
        tap(app.buttons["restore.apply"])
        confirm("Restore Collection")
        expectState(["normal=7;stamp=2", "incoming=0", "owned=1", "backups=3"])
    }
}
