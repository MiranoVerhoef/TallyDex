# Printing price statistics

The card's **Your collection** rows and **Choose printings** sheet display compact, separate marketplace summaries. Cardmarket shows **Avg** and **Low**; TCGplayer shows **Market** and **Low** because its `midPrice` is not an average. Each summary explicitly shows the currency supplied by the API. Both-market mode keeps EUR and USD on separate rows; narrow layouts can stack the metrics.

## Mapping

| Provider data | Display/use |
| --- | --- |
| Cardmarket `avg` / `avg-holo` | Avg, retained independently of the primary quote |
| Cardmarket `low` / `low-holo` | Low from the same selected printing price bucket |
| Cardmarket `trend` / `trend-holo` | Existing valuation/history basis; explicitly labelled Trend when Avg is missing |
| TCGplayer `marketPrice` / `lowPrice` | Market / Low for the selected printing/product |
| Provider `unit` | Currency label and number formatting; no conversion or mixing |

Detailed printings can contain their own standard price bucket even when the card is Holo. The existing primary-quote bucket selects the average, low and rolling averages too; these metrics are not borrowed from another bucket. General foil data remains omitted when it cannot be mapped unambiguously to a printing. Missing/nonpositive/nonfinite metrics are unavailable, not zero. An info marker explains price meanings, native currencies and the fact that Low is not a guaranteed checkout price or a Dutch-seller/shipping calculation. Existing manual-estimate controls are retained.

## Storage and compatibility

`CatalogPriceQuote` adds optional `averagePrice` and `lowPrice` fields. Older encoded data decodes without them. Catalogue migration v10 adds nullable columns to `catalogPrice`; collection/ownership tables are unchanged. Normal hydration and automatic/background price-only writes retain the new fields. Collection totals, price-history samples and rankings still use the existing quote amount (trend/market), not Avg or Low.

Individual card details refresh their legacy metric cache once, including when other metadata is still fresh. A versioned check marker also records a successful response when the upstream metrics are legitimately missing, avoiding repeated fetches. Routine set/automatic refreshes mark the same check when fetching new card data.

## Verification scope

Unit coverage includes provider decoding, consistent detailed-printing buckets, native units, backwards-compatible quote decoding, metric validation, nullable storage, ordinary/background write round trips, unchanged primary history/printing kinds, and one-time legacy cache hydration. Isolated UI fixtures provide different Avg/trend/low and EUR/USD values; the UI check verifies both-market labels, values, the info marker and unchanged ownership/backups. No new release or version bump is part of this implementation request.

At the start of verification, Xcode had updated to 27.2 while the installed CoreSimulator service remained at 1174.9.2 instead of the required 1174.21.0. The first concrete-device test build was rejected before compilation. A targeted service restart did not complete Xcode's component installation. No simulator was erased or reset; actual iOS test execution requires the first-launch setup to complete.

On 2 November 2026, the **Release simulator build succeeded** using a generic destination, and the **app, unit-test and UI-test targets built successfully** for the arm64 simulator. A nullable-column test initially used the wrong GRDB property name; it was corrected to `isNotNull`, and the final test build succeeded. Neither result is a claim that tests executed: concrete iOS 27 device testing and visual QA remain pending until the updated simulator components are installed. Build logs are `/tmp/tallydex-market-metrics-release.log` and `/tmp/tallydex-market-metrics-test-build-final.log`. The user selected hidden verification. These changes have not been version-bumped, committed or published.

## Completed verification after Xcode setup

After the user completed Xcode setup, testing resumed on iPhone 18 Pro / iOS 27.0 with Xcode 27.2, hidden. The final pricing run passed **268 unit tests and both new pricing UI checks**, with no failures, skips or runtime warnings (`artifacts/printing-market-statistics/FinalPricing.xcresult`). Six additional UI regression checks passed earlier: automatic-update preferences, bulk ownership/Undo, card paging, unsaved-note protection, collection home ordering, and existing marketplace/help settings. This is **eight distinct UI checks** in total. The pre-existing card-notes keyboard frame warning appeared in that broader regression run, as in the preceding published release; it did not fail the test.

The unit fixture for detailed printings initially used `variantsDetailed` instead of the API's `variants_detailed`; it was corrected and all 268 unit tests rerun successfully. The large-text pricing test opens the card through the app's existing deep link so it checks the price layout independently of native search/set navigation. A transient simulator runtime lookup error required refreshing the service and booting the existing device; no simulator data was erased or reset.

Screenshot inspection caught a truncated marketplace/currency label at the largest accessibility text size. The label now wraps without vertical compression, and the test checks its wrapped height as well as the visibility/bounds of Avg, Low and both amounts. Final light/both-market and dark/largest-text screenshots were visually checked under `FinalLightScreens/` and `FinalDarkScreens/`. These use sample prices from the isolated fixture, not live valuations.

The final Release simulator build also succeeded (`artifacts/printing-market-statistics/release-build-final.log`). No version bump, commit, AltStore publication or TestFlight upload was performed for this implementation.

## Pricing layout refinement

Following visual feedback, pricing is now a full-width inset comparison panel instead of stacked text competing with the ownership button. Each printing has its own semibold title/ownership header, with the comparison below. Marketplaces/currencies occupy a source column, and Avg/Market and Low values align in separate columns. Both-market mode uses a subtle divider; large accessibility text switches to a stacked, wrapping layout. Selected ownership circles use the app accent colour. The section's info marker is trailing-aligned, and manual estimates use a quieter footer row. Redundant missing-price guidance was removed; no pricing, ownership, quantity or refresh logic changed for this refinement.

Each source/reference/low cell has a semantic accessibility label and value, including its marketplace and currency. Initial row-container assertions revealed that SwiftUI Grid exposes cells separately, so accessibility and tests now target the actual semantic cells instead of assuming a row-wide container.

Hidden iPhone 18 Pro / iOS 27.0 verification with Xcode 27.2: **268 unit tests and three focused pricing UI checks passed together**, without failures or runtime warnings (`artifacts/pricing-layout-refinement/FinalPricing.xcresult`). These check both-market values/currencies, ownership controls above the panel, dark/largest-text readability, and full-width pricing below multiple-copy controls. Two additional regression checks—bulk editing/Undo and unsaved-note/card navigation—passed in the broader run. The same known card-notes keyboard frame warning was observed in that broader run.

The Release simulator build succeeded (`artifacts/pricing-layout-refinement/release-build-final.log`). The final light/both-market and dark/largest-text screenshots in `FinalLightScreens/` and `FinalDarkScreens/`, plus the multiple-copy screenshot in `CopyScreens/`, were visually inspected. Screenshot values are isolated test fixtures, not live card valuations. This refinement was local and unpublished at this stage; the subsequently requested release is recorded below.

## Release 0.9.56 (92)

The user approved the refined layout and requested an AltStore release with hidden verification. The release candidate passed **268 unit tests and 11 UI checks** on iPhone 18 Pro / iOS 27.0 using Xcode 27.2: **279 passed, zero failures or skips** (`artifacts/v0.9.56/verification.xcresult`). Coverage includes pricing/currencies, dark mode and largest text, multiple-copy layout, bulk editing/Undo, card navigation and unsaved notes, marketplace/settings controls, automatic pricing preferences, first setup and update notes. The existing notes-keyboard frame warning remained in the regression run; it did not fail the test and predates this change.

The device archive and Release simulator build both succeeded. Archive checks confirmed version/build, arm64, minimum iOS 26.0, development distribution, retained background-fetch configuration, and exclusion of reliability fixtures and test purchase configuration. The IPA passed ZIP integrity checks: **30,570,438 bytes**, SHA-256 **`565ff60a9f3ccc289aac597527c3288bbda420d80a64f65aa53b27b137fce949`**. The AltStore feed adds the new version while preserving all existing entries. No TestFlight upload or public purchase gating is part of this release.

The Release app installed and launched on the existing simulator without opening its window or erasing data. The captured launch screen (`artifacts/v0.9.56/release-launch.png`) was visually checked and shows the correct 0.9.56 update notes. Simulator logs also contain Apple CoreAnimation/PointerUI diagnostics; these are not a claim of an entirely warning-free runtime.
