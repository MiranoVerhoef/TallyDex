# Marketplace price labels and printing identity

## Observed on 2026-10-18

The development TCGdex endpoint's `30th-001` response describes one Normal
printing, ID `15i9grynjbpddvzw7dk089qr7vfcowuo`, with an anniversary stamp.
Its Cardmarket product is 907607 and its TCGplayer product is 716435.
Cardmarket supplies a EUR price under its ordinary trend fields, while
TCGplayer supplies a USD price under `holofoil` for product 716435.

The client previously unioned top-level pricing buckets into the available
variants. This incorrectly created a second Holo slot and split the two prices.
The official API also described one Normal printing, but did not yet supply
the TCGplayer quote when checked. Neither API was modified.

A read-only audit of all 161 development-endpoint cards found one detailed
printing per card and an additional conflicting marketplace finish on 86 cards.
This explains the screenshot's inflated denominator: 161 + 86 = 247 slots.

## Correction

- Identified detailed printings are not expanded from marketplace price buckets.
- Complete identified printing lists supersede stale legacy variant flags, so a
  corrected Normal/Holo type does not leave the old type selectable.
- Legacy responses without identified printings retain existing price-assisted
  variant discovery for compatibility.
- An exact TCGplayer product ID may resolve a different marketplace finish name
  only when there is one matching priced bucket. Ambiguous products stay unpriced.
- Top-level fallback prices cannot introduce variants outside the resolved list.
- Reverse Holo Cardmarket quotes retain their foil-specific prices and averages.
- Printing-detail cache version 2 triggers a one-time refresh of cached exact
  records when loading a set or card, without requiring a manual refresh.
- Existing atomic catalogue replacement removes obsolete current variant/price
  rows. Historical price observations are retained.
- A broad check against an obsolete standard finish is mapped to the sole
  identified standard printing, with a versioned automatic backup. Multiple
  printing choices remain untouched; stamped/jumbo ownership is not folded into
  regular ownership. Existing quantities merge using the existing conservative
  maximum rule, rather than duplicating a check.
- A stable printing ID whose kind changes updates its ownership classification
  without changing the saved quantity. Replaced IDs retain the existing
  unambiguous reconciliation rules.

## Set search

The large set artwork, progress and owned-value summary are hidden while search
is presented or the query is nonempty. Closing search restores the summary;
ownership filters and the matching card grid remain available while searching.

The AltStore build uses the development distribution channel, as before; the
already-uploaded TestFlight 0.9.46 (82) archive is not changed.

## Release verification

- 227 unit tests passed on iOS 27.0 using Xcode 27.1.
- All 15 existing reliability UI checks passed. The new set-search check passed
  separately after correcting its offscreen-set/search-drawer navigation.
- One opt-in marketing capture test was skipped, as intended.
- The search capture confirms that artwork, progress and values are removed
  while searching. The automation capture uses hardware-keyboard input and does
  not display the software keyboard.
- Device archive and Release simulator builds succeeded; Release 0.9.47 (83)
  installed and launched hidden with the correct What's New screen.
- The unsigned AltStore IPA passed ZIP integrity checks and uses the development
  channel, bundle `com.miranoverhoef.TallyDex`, and minimum iOS 26.0.
