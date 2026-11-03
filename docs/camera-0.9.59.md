# Camera matching — 0.9.59 (95)

This camera release follows the separately published 0.9.58 cleanup. Both were authorised for hidden iOS 27 verification.

## Behaviour

- Results show up to five ranked choices with match percentages. These are similarity scores, not calibrated probabilities. Selection and ownership changes remain explicit user actions.
- OCR reads the complete card plus enlarged title and collector-number regions. Matching combines names, set codes, numeric and prefixed collector marks, denominator and copyright-year evidence. Name-only matching normalises punctuation, including Lucario GX / Lucario-GX.
- Ambiguous matches are compared against at most 16 reference images using the existing artwork cache. Vision feature prints are combined with a small CPU image descriptor. Missing/unusable model output falls back to the descriptor. Only identical decoded artwork gets an exact-reference boost; a similar-looking thumbnail cannot establish a particular reprint.
- The visible guide is mapped into capture coordinates with the same aspect-fill transform as the preview. Smaller, off-centre complete cards are eligible; detected corners define the perspective-corrected crop. If detection fails, a camera capture is cropped to the guide before OCR. Library images keep their separate alignment flow.
- Automatic capture waits for stability and card-front text evidence. Unrelated rectangles are not immediately shown as recognised cards. Manual capture remains available, and Auto remains experimental.
- The results sheet receives an explicit current snapshot of matches and scores, avoiding an empty first presentation caused by unobserved sheet-only state.

Scans are processed on device. Only ordinary reference-artwork downloads use the configured TCGdex/cache pipeline; no scan photos or corrections are uploaded. The removed TallyDex Assets API is not used.

## Reproducible artwork replay

`Scripts/prepare_scanner_benchmark.py` downloaded **336 images across 21 sets**, from Base Set through Mega Evolution, with a **23,771-card reference index**. All selected downloads succeeded. Generated files stay under ignored `artifacts/scanner-benchmark/`; artwork is not committed to Git. A SHA-256 check found no identical downloaded image crossing the 216/120 card-ID splits.

The original full-image OCR configuration was replayed with a strict single-candidate fraction/name baseline: **270/336 exact single matches, 34 ambiguous**. This local baseline does not reproduce every lookup-order or networking detail of the previously published app. Enlarged region reads improved that same strict baseline to **286/336**.

The actual iOS app OCR and rectangle-crop code then processed **336 clean images and 28 off-centre scenes**. All **28/28 scenes were detected**, and that intermediate text-only ranking returned **321/336 first matches and 330/336 top-three** for clean images and **25/28 first matches, 26/28 top-three** for the scenes (`artifacts/camera-pass/replay.xcresult`). Its recorded OCR is reused to evaluate later ranking changes without rerunning identical OCR requests. Input filenames/expected IDs are used for loading and evaluation, never as recognition evidence.

`Scripts/scanner_benchmark.swift` compiles with the same `ScannerRecognition.swift` used by the app. It supports the original OCR and `--enhanced --visual` replays. The opt-in iOS tests in `TallyDexSmokeTests` exercise the native image pipeline and rerank the saved iOS observations. Normal test runs can exclude these local-data benchmarks; without the downloaded data they explicitly skip.

The card-ID splits are diagnostic regression groups. Some failures were inspected during engineering, so the final figures are not an independent blinded accuracy study. Images are clean API artwork and deterministic simulated scenes, not handheld-camera validation. In the clean replay, candidate artwork can be identical to the input and therefore receive the exact-reference boost. The benchmark exercises shared OCR/ranking against a local index, not the app's complete catalogue-query/network/cache flow. A universal 100% recognition claim is not warranted. Similar reprints, unreadable collector marks, glare, sleeves and physical capture timing still need real-iPhone validation.

## Model and test notes

This release improves Apple's existing on-device Vision pipeline; it does not claim to train a new custom Core ML detector. The earlier ScanLab archive was not available at its supplied path. Reviewed real-camera detector training remains a separate task.

The simulator initially rejected Vision's default compute context. Explicit simulator CPU configuration allows execution; zero/non-discriminative feature output is handled conservatively alongside the CPU descriptor. A negative-image test checks that unrelated artwork is separated from identical artwork. The camera UI fixture is Debug-only, explicitly opted in and excluded from Release. It checks ranked values, explanation copy and unchanged ownership/backups.

## Final verification — 3 November 2026

The final cached-observation replay ranked **336/336 clean reference images first**, including 216/216 development and 120/120 diagnostic holdout cards. Both top-one and top-three were 100% on this defined replay. This result includes comparison against identical reference artwork where available; the limitations above apply. The earlier independent macOS OCR replay reached 335/336. The off-centre figures above remain the measured text-only results and are not replaced by the clean-image figure.

Hidden iPhone 18 Pro / iOS 27.0 verification with Xcode 27.2 passed **275 checks: 274 unit/benchmark tests and one camera UI test**, with zero failures, skips or recorded runtime warnings (`artifacts/camera-pass/publish-verification.xcresult`). The final run includes punctuation normalisation, image separation, guide geometry, copyright-year disambiguation, ranked ordering and the 336-card replay. The earlier raw OCR/crop benchmark is in `replay.xcresult`; it was not redundantly rerun. Four existing regression UI checks for Owned Cards, Settings search, update notes and bulk Undo also passed during this camera pass (`artifacts/v0.9.59/verification.xcresult`).

The final device archive and Release simulator build succeeded. Package checks verified arm64, version 0.9.59 / build 95, minimum iOS 26.0, development distribution and the existing background-fetch configuration. Test fixtures, local StoreKit configuration and provisioning profiles are absent from the sideload package. ZIP integrity and the packaged executable's equality with the final archive were verified.

IPA: **30,614,187 bytes**. SHA-256: **`7c03ae49c45b858846ead9df70d7df1f32fa0947c1ae9e03a3bd181f339ac187`**.

The final Release simulator app installed and launched hidden. Its 0.9.59 update notes were visually checked in `artifacts/v0.9.59/release-launch.png`.
