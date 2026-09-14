# TallyDex Scan Lab 0.1.0

Separate, local-only iPhone training-data collector. Bundle ID: `com.miranoverhoef.TallyDexScanLab`. It does not read or change your TallyDex collection. Requires iOS 26.0 or newer. The IPA is unsigned and needs your usual sideloading/signing tool.

## Start here

1. Open **Clear fronts → Start automatic capture**. Put ONE Pokémon card in view with all four corners visible, then pause for about a second. The phone saves a full-frame photo with a suggested outline.
2. Change the angle or replace the card. Slight outline jitter does not save duplicates. **New card** starts a fresh capture batch and rearms detection; use it when replacing a card the detector cannot distinguish from the previous one.
3. Tap **Review**. Choose front, back, or no Pokémon card. Drag the two handles to tightly enclose the ACTUAL card, not its sleeve/top loader. **Approve** keeps the annotation; **Exclude** leaves the original on your phone but omits it from training.
4. Complete the goals below using different physical cards, layouts, rooms, and backgrounds. A manual shutter handles cases the detector misses.
5. Optional: **Generate extras** creates 10–200 perspective/lighting/blur variants per batch from the existing compressed bundled artwork. Approved TRAINING negative scenes may become backgrounds. These never count toward real-photo goals and never enter validation/test.
6. **Export ZIP** → Save to Files / share to your Mac. Only approved, non-excluded examples are exported. Nothing is uploaded automatically.

Automatic capture is ON by default. It locks onto a nearby existing rectangle, requires stable geometry for 0.8 seconds, and suppresses unchanged poses. A sustained absence, substantially different pose, or stable change in the card's appearance rearms it. This helps detect a replacement card in the same position; lighting changes can qualify too, so it does not prove unique card identity. Negative-scene mode uses visual-change/stability checks rather than requiring a rectangle. Auto capture pauses at 60 pending photos or on a save failure, and stops while the app is inactive. Review the queue before continuing.

This first lab still uses Vision rectangle proposals, NOT a trained Pokémon classifier. It can propose wrong objects. Human review is deliberately required so those errors do not become ground truth. Tracking does not prove a new physical card or semantic identity.

## Guided starter goals

| Goal | Reviewed real photos |
| --- | ---: |
| Clear fronts, varied eras/layouts | 30 |
| Sleeves and top loaders | 20 |
| Glare and different lighting | 15 |
| Tilted/rotated/near/far views | 20 |
| Busy backgrounds | 20 |
| Hard negatives: phones/books/boxes/other TCGs/empty scenes | 30 |
| Pokémon card backs | 10 |
| Separate validation session: 10 fronts, 2 backs, 3 negatives | 15 |
| Separate unseen test session: 14 fronts, 3 backs, 3 negatives | 20 |

**180 is a starter target, not a claim that the model will be good enough.** Aim for different examples rather than repeatedly photographing the same pose. Validation/test have a capture-type menu so you can collect both classes and background scenes. They count all approved real examples, not generated photos.

Keep ALL views of the same physical card and scene in ONE split. For validation/test, deliberately use different cards and locations. Capture-batch IDs and SHA hashes detect some leakage, but cannot recognize two different photos of the same card. Manually audit this before training. Do not augment validation/test.

Use one card per image. Exclude partially hidden/cut-off cards, multiple cards, or unrecognizable cards. A background example MUST contain no Pokémon card anywhere. Other trading cards are useful hard negatives. Outlines are axis-aligned enclosing boxes, including for perspective views; this trains an object detector, not a four-corner estimator.

## Local storage and export

Photos: Documents/ScanLab/images/*.jpg. Metadata: Documents/ScanLab/samples.json, written atomically. Excluding is recoverable in **Browse all samples**. Loading errors lock writes rather than overwriting a broken dataset. Uninstalling the app removes its sandbox; export before uninstalling.

Camera JPEGs have a maximum long edge of 1440 px, quality 0.8. Generated images are 960×1280; the bundled source art remains the original small WebP files, not upscaled resources. Export streams JPEG entries one at a time on a background task into a standard uncompressed ZIP (JPEGs are already compressed).

The ZIP has training/, validation/, test/; each has annotations.json and images/. Create ML boxes use upright-image pixel **center x/y, width/height**, origin top-left. Labels: pokemon_card_front, pokemon_card_back. Negatives have an empty annotations array. manifest.json records source, split, batch, goal, and synthetic artwork provenance. No pending/excluded images are exported.

Bundled artwork remains copyrighted by its owners. Use this private dataset for development; no additional redistribution rights are implied.

## Train later on your Mac

Unzip your exported dataset into a new folder. With Xcode installed:

```sh
swift ScanLab/Tools/train.swift /absolute/path/to/unzipped-dataset --check
swift ScanLab/Tools/train.swift /absolute/path/to/unzipped-dataset /absolute/path/to/NEW-CardDetector.mlmodel
```

The first command performs integrity checks and verifies Create ML can read the annotation layout; it does not train or write a model. Training requires real fronts, backs, and negatives in EVERY split. It uses transfer learning, the explicit validation split, and evaluates the untouched test split. It also reports false detections on test negative scenes at confidence 0.70. It refuses existing output paths. Training duration varies; 2,000 iterations is a starting configuration, not a tuned optimum.

No trained model is included in this app. Exact Pokémon/card ID matching is a separate task. Next: collect/export, audit labels and split leakage, train, measure misses and false positives by goal, then test speed and stable tracking on real iPhone video before adding Core ML to TallyDex.

References: [Apple object-detector dataset format](https://developer.apple.com/documentation/createml/building-an-object-detector-data-source), [MLObjectDetector](https://developer.apple.com/documentation/createml/mlobjectdetector).

## Developer verification

```sh
swift test --package-path ScanLab
xcodebuild -project ScanLab/ScanLab.xcodeproj -scheme ScanLab -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .build/scanlab-debug test CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES
xcodebuild -project ScanLab/ScanLab.xcodeproj -scheme ScanLab -configuration Release -destination 'generic/platform=iOS' -derivedDataPath .build/scanlab-release build CODE_SIGNING_ALLOWED=NO
```

Keep release DerivedData separate from test/analyze builds, which inject XCTest frameworks. Real camera focus, orientation, exposure, and automatic capture need a physical iPhone test; simulator tests do not establish those.
