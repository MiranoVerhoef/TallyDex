# Release 0.9.58 (94)

Adds a dedicated Owned Cards grid with combined name/set/number search, filters, sorting, printing selection and existing bulk editing. The Collection home keeps a single navigation row and owned-card count. Settings gains native pull-down search, including keywords for options inside its pages.

Info buttons use a shared paragraph-based sheet. Help is shorter, the coffee disclaimer and About analytics row are removed, and price panels match the Market averages tile background. The Market averages footer is removed. Export help now accurately states that manual values are included while cached market quotes and history are not; the backup format is unchanged.

## Verification

Hidden iPhone 18 Pro / iOS 27.0 using Xcode 27.2: all **268 unit tests and 14 selected UI checks** passed across the verification runs. The initial broad run passed 281 checks and failed the new Owned Cards test. Its first selector was overridden by the shared bulk-selection identifier. The next run exposed native search remaining active on return from card details, hiding toolbar tools until Close is pressed. The test now follows that flow and passed in `artifacts/v0.9.58/owned-final.xcresult`. No production-code change was needed for these test corrections. The other checks cover Settings search/help, coffee products, price panels and accessibility text, setup and update notes, bulk editing/Undo, and Collection home ordering (`artifacts/v0.9.58/verification.xcresult`).

The device archive and Release simulator build succeeded. Archive checks verified version/build, minimum iOS 26.0, arm64, development distribution, background-fetch configuration and exclusion of reliability fixtures/test purchase configuration. The IPA passed ZIP integrity checks: **30,588,341 bytes**, SHA-256 **`54efe12f5656c2a087a57649e5cc345fbd734b8981df4229ea0b56e252e48ba6`**.

The Release app installed and launched hidden. The 0.9.58 update notes were visually checked in `artifacts/v0.9.58/release-launch.png`.

The camera pass remains separate and follows this release. See `camera-next-pass.md`.
