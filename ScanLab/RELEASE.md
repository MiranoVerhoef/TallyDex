# TallyDex Scan Lab 0.1.0 (build 1)

A separate install, not a replacement or update for TallyDex. iOS 26.0+. Unsigned IPA; use your usual sideloading/signing tool.

Automatic stable capture, tracked outline suggestions, pose/appearance-change rearming, manual capture, review with editable bounding boxes, recoverable exclusions, nine real-photo goals (180 examples), training-only generated extras, and reviewed-only dataset ZIP export. All app data stays local unless you choose to share an export.

Start with 30 varied clear card fronts, then 30 hard negatives (phones, books, boxes, other TCGs, empty scenes). Review labels and outlines. Continue through sleeves, lighting, angles, backgrounds, backs, and separate unseen validation/test sessions. Generated photos do not advance real goals.

This collects training examples; it does NOT include a trained Pokémon classifier yet. After collection, export your ZIP, audit the labels/splits, train on your Mac, then evaluate on real iPhone video before integrating into TallyDex. See README.md for guided usage and Tools/train.swift for checks/training.

Verification: 8 core tests + 2 iPhone simulator tests + 1 UI test passed. Static analysis passed. Create ML successfully loaded exported positives and empty-annotation negatives. IPA ZIP integrity and arm64 identity checked; no XCTest/test fixtures/AppleDouble files in the release package. Physical-camera focus/orientation/auto-capture remain to be tested on a real iPhone.

IPA: TallyDexScanLab-v0.1.0.ipa

Size: 20,368,770 bytes

SHA-256: e4558411bb5ca85d700d0ada64e0ccf071d11a635ce6b69ff409b55a9b48a30b
