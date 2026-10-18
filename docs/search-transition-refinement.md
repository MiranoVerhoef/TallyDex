# Set-search transition refinement

Version 0.9.48 (84), development/AltStore channel.

## Cause

The previous search fix conditionally inserted several children into the root
LazyVStack while UIKit was dismissing the search/navigation UI. The independent
layout animations produced temporary overlaps and a second scroll adjustment.
The original UI regression checked the settled layout, not the animation.

## Changes

- Keep the summary as one measured section, with a stable full-width layout.
- Animate its clipped height, opacity and the results container together over
  0.28 seconds rather than inserting/removing separate header children.
- Isolate result-group geometry and resolve filtering without inherited
  per-card movement or fade animations. Use a top content-size scroll anchor.
- Exclude the collapsed section from hit testing and accessibility. Respect
  Reduce Motion by disabling the custom transition.
- Exercise three search/cancel cycles, including no results, and assert that
  the header returns to its original vertical position within four points.

During implementation, simulator recordings were inspected frame by frame to
catch a remaining content snap and per-card staggering, then refine the grouping.
These captures use simulator hardware-keyboard input; physical-device software
keyboard behavior still benefits from confirmation. No collection, printing,
pricing, purchase, API or distribution-channel behavior was changed.

## Release verification

- Full hidden iOS 27.0 run on Xcode 27.1: 227 unit tests and all 16 reliability
  UI checks passed; the opt-in marketing capture was intentionally skipped.
- The repeated search/cancel check passed for matching and empty results, with
  the header returning to the same vertical position after every cancellation.
- Device archive and Release simulator build succeeded. Release 0.9.48 (84)
  installed and launched hidden on iPhone 18 Pro.
- Unsigned IPA passed ZIP integrity checks; the feed's version, build and
  30,264,144-byte asset size match. Minimum iOS remains 26.0.
- TestFlight build 0.9.46 (82) and App Store Connect were not changed.
