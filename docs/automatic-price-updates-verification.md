# Automatic price updates — verification

The feature-implementation pass was verified locally on 1 November 2026, using iPhone 18 Pro / iOS 27.0. Simulator remained hidden; neither Xcode nor the Simulator device hub was opened. No version bump, IPA publication, git push, or AltStore feed change was made during that initial pass. The subsequent requested release is covered below.

## Results

- Final Debug build and test run: **263 unit tests + 2 new UI tests passed**, zero failures, zero runtime warnings in that final run.
- Seven additional UI regression checks passed in the preceding broader run: card paging/back navigation, unsaved note protection, collection home ordering, setup completion, setup skipping, one-time update notes, and existing marketplace/settings controls.
- The first broader run exposed a test interaction problem: tapping the centre of a labelled Form switch did not activate its trailing native control. The test now uses the existing native-switch helper and passes, including preference persistence after relaunch.
- Final **Release simulator build succeeded** and was installed/launched hidden.
- Setup and Settings screenshots were exported and visually checked: no clipped controls, extra setup page, or misplaced help text.
- Existing ownership quantities and backup counts remain unchanged in the UI checks. Repository tests verify that automatic price writes cannot replace card metadata or add printing kinds.

Evidence: `artifacts/automatic-price-updates/FinalVerification.xcresult`, `Verification.xcresult`, `SettingsScreens/`, `SetupScreens/`, and `ReleaseLaunch.png`.

## Known baseline warning

The broader regression run emitted one `Invalid frame dimension (negative or non-finite)` SwiftUI warning when focusing the existing card-notes keyboard. The same warning is present in the published 0.9.54 release's `artifacts/v0.9.54/ui-tests.log` at the same test interaction. The note-save/navigation test passes; no keyboard behavior was changed for this feature. This should not be described as a warning-free whole-app run.

## Device-only follow-up

Enable **Settings → Prices & Currency → Automatic Updates → Allow background updates** on a physical iPhone, leave iOS Background App Refresh enabled, and compare the last-check timestamp/history over ordinary usage. Actual scheduling cadence, suspension/lock behavior and battery impact cannot be established from Simulator tests. iOS decides when to grant background runtime; no daily guarantee is made.

## AltStore release 0.9.55 (91)

The user requested publication and selected hidden testing for this release. All **263 unit tests and 11 targeted UI checks passed** together on iPhone 18 Pro / iOS 27.0. The same pre-existing card-notes keyboard warning described above was recorded; there were no test failures. Setup completion/skipping and one-time update notes were rechecked for 0.9.55, alongside automatic-update preferences, collection editing/Undo, ownership filtering/search, collection layout, marketplace controls and card paging/unsaved notes.

The unsigned device archive and Release simulator build both succeeded with version **0.9.55**, build **91**, development channel and minimum iOS **26.0**. The new background task identifier and `fetch` mode are present. Test fixture markers, StoreKit test resources and provisioning profiles are absent from the device package. The IPA passed ZIP integrity checks.

The Release simulator app was installed and launched hidden. Its short 0.9.55 update screen was visually checked in `artifacts/v0.9.55/release-launch-ready.png`; the app remained running without a launch crash.

- IPA: `artifacts/v0.9.55/TallyDex-v0.9.55.ipa`
- Size: **30,544,663 bytes**
- SHA-256: `795cdc3b09b8407f2bdc25ca921d0d8a4116047496941292be8184d55793d266`
- Release evidence: `artifacts/v0.9.55/verification.xcresult`, archive/build logs and the Release launch screenshot.

The release uses the existing GitHub/AltStore workflow, not TestFlight or App Store Connect. The uploaded asset digest/size and canonical live feed are checked during publication before completion is reported. Existing feed versions and unrelated website/App Store drafts are preserved.
