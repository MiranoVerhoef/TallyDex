# Set-search close regression

Development/AltStore version 0.9.49 (85).

## Reproduction

On a physical iPhone, open a set, start searching, then tap the outer X to
close search. The user confirmed that 0.9.48 still moves the header/grid in
multiple steps. Its simulator checks validated the final position using
hardware-keyboard input, not the software-keyboard dismissal animation.

## Implementation

- Replace this screen's navigation-drawer search presentation with a fixed
  search row above the scroll view. Navigation title and toolbar stay present.
- Keep the summary collapsed for an active search, even after submitting or
  clearing text. The outer X clears the query, ends focus and restores the
  summary in one update.
- Retain the measured summary and grouped card-grid transition. Remove the
  content-size scroll anchor that could independently reposition the content.
- Preserve the existing search matching, ownership, pricing and printing rules.
- Give clear and close separate accessibility labels and identifiers.

## Verification requirements

The search regression now requires more than 150 points of keyboard intersecting
the visible screen and a tappable Search key, rather than keyboard existence alone. It
cycles through matching and empty results, checks the fixed search/navigation
geometry, and distinguishes clearing/submitting from closing search. A recording
of the transition must also be inspected; settled-state assertions alone cannot
establish visual smoothness.

## Local results

- The updated app compiled; all 227 unit tests passed.
- Three close cycles and clear/submit checks passed with steady search/navigation
  frames, but the recording showed no visible software keyboard.
- A stronger keyboard gate then correctly failed: the keyboard's intersection
  with the visible app was zero. This run is not a successful software-keyboard
  regression test, despite accessibility reporting a keyboard taller than 150 points.
- Xcode 27.1 on this Mac supplies DeviceHub, not the old Simulator.app. Launching
  DeviceHub hidden did not attach a visible keyboard to the headless device.

## Visible iOS 27 verification

With the user's approval, opened Device Hub and pressed **Switch to compact
window** to show only iPhone 18 Pro (iOS 27.0), without launching Xcode.
Under **Device > Keyboard**, disabled the checked **Simulate Hardware Keyboard**
option for the test. The subsequent run passed the stricter visible-keyboard
intersection and tappable Search-key assertions, all three X-close cycles, and
clear/submit behavior. Search-row and navigation-bar positions stayed fixed.
Restored the original hardware-keyboard setting afterward and left the app open
in the single-device window.

The screen recording visibly includes the software keyboard. A 20 fps contact
sheet of the first close shows one header/grid reveal below the fixed search row,
without the earlier navigation-drawer overlap or second navigation-height move.
This verifies simulator behavior, not yet a physical-device confirmation.

Evidence is in `artifacts/search-close-regression/`: `visible-keyboard-tests.log`,
`visible-keyboard-close.mp4`, `visible-close-frames.jpg`, and `close-preview.mp4`.
All 227 unit tests also passed (`unit-tests.log`). This pre-release verification
was followed by preparation of version 0.9.49 (85) for AltStore/GitHub, not TestFlight.

For future automation, use the actual `DeviceHub` PID for accessibility queries:
on this machine Launch Services returned an NSRunningApplication with PID -1,
even while the real process and its accessible window were running normally.
Do not infer a visible keyboard from accessibility existence or frame height:
check its intersection with the screen and inspect the recording. Hardware-keyboard
simulation was checked during the unsuccessful headless runs.

## Version 0.9.49 release verification

- Full visible iOS 27.0 suite passed: 227 unit tests and 16 reliability UI checks;
  the opt-in marketing screenshot capture was intentionally skipped.
- The build-85 search check passed with a visible, tappable software keyboard.
  Its recording and 20 fps close-transition frames are saved under `artifacts/v0.9.49/`.
- Device archive and Release simulator build both succeeded. Both report version
  0.9.49, build 85, development distribution channel; minimum iOS remains 26.0.
- Unsigned IPA passed ZIP integrity checks. Its 30,267,411-byte size matches the
  new AltStore entry. SHA-256:
  `5ece74837510ac4f068021bb3b6931a3d07e706d8ff7abef435a9ab0a457d08c`.
- TestFlight/App Store configuration and collection/printing/pricing logic are unchanged.
