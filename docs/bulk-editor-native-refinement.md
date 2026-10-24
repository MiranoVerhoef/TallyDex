# Native bulk editor — 0.9.51 (87)

Development/AltStore release. TestFlight and App Store Connect are unchanged.

## Interface

- Selection uses lightweight checkmarks without whole-tile borders or blue fills.
- A floating system-glass bar replaces the tab bar during selection. Its count
  opens Select all / Deselect all; Set opens the printing picker and Done leaves
  selection without editing ownership. Tabs return after leaving selection.
- Search list rows use leading selection checkmarks and no navigation chevrons
  while editing. Ordinary taps outside selection still open card details.
- The native grouped printing sheet uses checkmark rows, eligible-card counts,
  owned/missing actions and optional information rather than several switches
  and a permanent explanatory paragraph. It supports medium and large detents.
- Accessibility text sizes use a full-height sheet, vertically stacked counts,
  and a two-row selection bar. Checkmark decorations are hidden from VoiceOver;
  each control exposes its actual selected state. Dark mode uses system colours.
- Saving disables picker controls. Loading errors no longer retain a spinner.

## Preserved behaviour

The ownership planner, repository transaction, exact-printing handling, safety
backup and conflict-safe Undo are unchanged. Removing ownership still requires
confirmation. Printing availability is never inferred from marketplace prices.
No catalogue, pricing, purchase, API or distribution-channel policy was changed.

## Verification

Before versioning, 237 unit tests and six distinct UI regressions passed on
iPhone 18 Pro / iOS 27. UI coverage includes sets, Search list/grid, Pokémon
collections, individual selection, filtered select-all, quantity preservation,
removal confirmation, cancellation, Undo, optional help, dark mode and the largest
accessibility text size. iOS 27's popover confirmation can cancel via an outside
tap rather than a Cancel button; the test covers that native presentation.

Release-specific build and test evidence is retained in `artifacts/v0.9.51/`.

## Device package

- Device archive: version 0.9.51, build 87, development channel, minimum iOS 26.0.
- Unsigned IPA: 30,345,773 bytes; ZIP integrity validation passed.
- SHA-256: `7a123d38f22d210d68befaf0472b741ab9c26bff83daa77f1e8ae3ce927e80a3`.

## Release checks

- All 237 unit tests passed for 0.9.51 (87) on the established iOS 27 simulator.
- The full fresh-simulator UI run passed 21 checks and skipped the opt-in
  marketing capture. Its coffee-tip check failed because local StoreKit did not
  supply the tip products; the app displayed its intended unavailable state.
  That same check passed separately on the established simulator. A second fresh
  run reproduced the missing local StoreKit products and is not counted as a pass.
- All 22 distinct UI checks are therefore verified across the two simulators,
  including the strict onscreen software-keyboard search regression. The fresh
  simulator run is not described as an entirely passing suite.
- Device archive and Release simulator build succeeded. The Release app installed
  and launched hidden on iPhone 18 Pro / iOS 27 with the normal introduction,
  development channel and no forced purchase gate.
- No photo-feedback service, Assets API, TestFlight upload or public-release
  feature activation is included.
