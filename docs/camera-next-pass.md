# Camera improvement pass

The user authorised both builds, hidden, on 2 November 2026: release the text/UI cleanup first, then implement and release camera improvements separately. Benchmark a few hundred TCGdex cards in a simulated environment. Camera implementation and training had not started when this plan was recorded.

## Requested behaviour

- Recognise a complete Pokémon card anywhere within the blue guide without requiring its edges to match the guide. Detect the actual corners and crop/straighten the card automatically. Preserve automatic capture after a short stable interval.
- Restore multiple candidates, ordered from most likely to least likely, with understandable percentage scores. Let the user choose the correct card or rescan. Never update ownership based on a guess.
- Perform a reproducible recognition sweep using artwork from official TCGdex and the configured TCGdex development mirror. Do not introduce the removed TallyDex Assets API or scanner submissions.

## Current implementation to revisit

`FeatureViews.swift` uses Vision rectangle detection, frame stability, OCR, collector/set identifiers and fuzzy name matching. Ambiguous matches are currently suppressed by `CardScanMatchPolicy`, requiring a rescan. Existing name-similarity scores are heuristic scores, not calibrated identification probabilities. No Core ML scanner inference was found in the main app.

`ScanLab/Tools/train.swift` trains a front/back card detector from reviewed annotated data. That detector locates a card; identifying the exact card needs a separate recognition/evaluation path. Existing dataset integrity rules keep generated samples in training and reserve real camera samples for validation/test.

## Evaluation and implementation

1. Build a resumable, bounded download/cache workflow for labelled TCGdex artwork. Record card IDs, image availability and failures. Exercise the actual crop/OCR/matching pipeline; filenames and known test IDs must not feed recognition.
2. Benchmark clean images across eras, card layouts, promos, special numbering, similar names and reused artwork. Add realistic scale, rotation, perspective and background variations for training and robustness checks. Keep variants of the same card/artwork grouped to avoid leakage into evaluation.
3. Keep a separate held-out evaluation set and use available real ScanLab photos for camera validation. Target perfect recognition on the defined clean-image benchmark, but report measured top-1/top-3 accuracy, rejection rates, false positives and individual failures. API artwork alone cannot establish real-camera accuracy.
4. Improve candidate retrieval and ranking using available identity and image evidence. Percentage probability claims require held-out calibration. Until calibrated, label heuristic percentages as match scores. Do not inflate weak candidates or force a result when none is credible.
5. Map the visible blue guide to capture coordinates, accounting for orientation and aspect-fill cropping. Allow varied card sizes and positions within it. Prefer a complete card in the guide, reject unrelated rectangles, and handle multiple visible cards deliberately. Verify that live detection and full-resolution capture crop the same card.
6. Reuse the native result list, thumbnails and collection controls. Rank candidates visibly, keep rescan available and require user selection for ambiguity.

## Verification

Test clean front images, reused artwork, unreadable numbers, non-card backgrounds, two-card scenes, portrait/landscape orientation, different distances, corner positions, capture stability and crop alignment. Simulator/image replay can test recognition; actual camera positioning and capture timing also require a physical iPhone. The user selected hidden verification for both builds.

## Implementation in 0.9.59

The cleanup shipped separately as 0.9.58 (94). The camera pass is implemented as 0.9.59 (95): regional OCR, ranked choices with match scores, bounded artwork comparison, guide-coordinate mapping and card-front checks before automatic capture. A reproducible 336-card / 21-set artwork replay and 28 off-centre scenes exercise the shared recognition and crop code. See [camera-0.9.59.md](camera-0.9.59.md) for measured results, final verification and limitations.

This pass improves the existing Vision pipeline. It does not train a custom detector or upload scan photos. The supplied ScanLab archive was unavailable at its earlier path. Reviewed real-camera training, physical-device capture timing, glare/sleeves and broader multiple-card/orientation checks remain follow-up work. The simulated benchmark must not be presented as universal real-camera accuracy.
