# TallyDex

TallyDex is a private, local-first Pokemon card collection tracker for iPhone.

The name combines **tally**—counting what you own or still need—with
**dex**, a compact indexed catalog like a Pokédex. TallyDex is your
collection-counting card index.

## Requirements

- macOS 26.2 or later
- Xcode 26.6
- iOS 26.5 Simulator runtime

## Build

```sh
xcodebuild \
  -project TallyDex.xcodeproj \
  -scheme TallyDex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/DerivedData \
  build
```

## Test

```sh
xcodebuild \
  -project TallyDex.xcodeproj \
  -scheme TallyDex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/DerivedData \
  test
```

## Development releases

Each GitHub development release includes an unsigned IPA that a sideloading app
can sign for your device. FlareStore, AltStore, SideStore, and other compatible
apps can use this source URL:

```text
https://raw.githubusercontent.com/MiranoVerhoef/TallyDex/main/altstore-source.json
```

## Collection values

TallyDex caches Cardmarket EUR and TCGplayer USD market prices supplied by
TCGdex. You can choose the preferred source in Settings. Values are calculated
per exact printing and quantity; unpriced variants are reported separately
instead of being estimated from another printing. Current prices refresh every
18 hours and one snapshot per source day is retained locally for future price
history views. Card details provide exact per-printing price-history charts with
7-day, 30-day, 90-day, and All ranges, plus current, change, low, and high
statistics. Cardmarket and TCGplayer histories remain separate and retain their
native EUR or USD currency. History is retained for one year by default. The
Forever option has a configurable approximate history limit of 50 MB, 100 MB,
250 MB, 500 MB, or 1 GB; time-based modes retain a 250,000-point safety ceiling.
Settings shows price-data usage and can clear history alone or all cached market data.
Card details reuse fresh 18-hour data, and the complete search index uses TCGdex
ETags so an unchanged refresh does not download its multi-megabyte response again.
Artwork has a 400 MB automatic least-recently-used ceiling, with older card images
removed before core series, set, and expansion artwork.

## Offline sets

Touch and hold a released set and choose **Keep Offline** to download its complete
card metadata, printing variants, grid images, and full-size artwork. TallyDex
shows an estimated size before downloading, progress while it works, and an
Offline badge when the set is complete. Explicit downloads live separately from
the automatic artwork cache, so its 400 MB cleanup never removes them. Manage
individual downloads in Settings → Offline Sets.

## Roadmap order

1. Offline set pinning — completed in v0.5.4
2. Performance and accessibility hardening — completed in v0.6.0
3. Remove the 100-result ceiling from stamped-variant searches — completed in v0.6.2
4. Browser-based mass collection editing — completed in v0.7.0
5. Direct Cardmarket listing preferences, including country and currency
6. Final real-device, accessibility, performance, and v1.0 hardening
7. Apple services after Developer Program enrollment: iCloud sync, TestFlight, and an optional StoreKit Tip Jar
8. Binder planner
9. Fully on-device card scanner — last

v0.6.0 indexes owned cards and their printings for fast collection lookups and
calculates every card’s goal progress in a single pass per set. Card grids,
completion controls, market averages, and price-history summaries now adapt to
Accessibility text sizes, and frequently used collection controls meet a 44-point
minimum touch target.

v0.6.1 adds variant-aware catalog search. Searches such as **Lucario staff**,
**Lucario prerelease**, or **SM95 staff** first find matching cards in the local
complete index, then download only missing TCGdex detail records and filter the
results by their actual printing metadata. A card, set, or collector number is
required with the stamp term so TallyDex never presents a partial catalog-wide
result as complete.

v0.6.2 removes the ordinary 100-result ceiling when a search includes a
Prerelease or Staff term, allowing Pokémon with unusually many printings to be
checked completely. Ordinary catalog searches keep their responsive 100-result
limit. Variant searches matching more than 500 cards ask for a more precise
Pokémon, set, or collector number before downloading details.

v0.7.0 adds a local browser editor for faster collection entry on a computer.
Open **Settings → Browser Editor**, start sharing, then enter the displayed local
address and six-digit pairing code on a computer connected to the same network.
The responsive editor can load a complete set or search the catalog, filter All,
Owned, or Missing cards, change exact printing ownership and quantities, and
edit wishlist and personal notes. Changes save directly to the iPhone, and
TallyDex creates an automatic rollback backup before each sharing session.
Sharing runs only while explicitly active, uses a new local session and CSRF
token each time, locks out repeated incorrect pairing attempts, and sends
no-store browser headers. Stop sharing when finished.

v0.7.2 adds persistent browser layout controls for two through six cards per
row (or an automatic layout) and Compact, Comfortable, or Spacious spacing.
Every card tile now has the same height, including cards with different numbers
of known printings. Each card also opens a computer-friendly Cardmarket panel
with its exact printing price, TCGdex 1-day, 7-day, and 30-day rolling averages,
locally recorded 7/30/90-day or all-time history, range summaries, and the exact
Cardmarket product link. Wishlist and notes remain in their own focused dialog.

The set chooser is searchable, grouped by series, and filterable into Main
sets, Promos & subsets, and Other collections.

Apple services remain last because they require Apple Developer Program and App
Store Connect setup. TCGdex supplies Cardmarket 1-day, 7-day, and 30-day average
values, but not 30 individual daily price points; TallyDex therefore builds its
truthful price-history timeline locally instead of inventing backdated samples.
The supplied rolling averages are shown separately for each exact Cardmarket
printing and are saved with the current price for offline use. Cards cached by
an older build refresh once when opened so their averages are not hidden behind
an otherwise-fresh price cache. Pulling down in card details forces an immediate
refresh of that card without refreshing its entire set, after an explicit
confirmation that explains what will and will not change.

When TCGdex supplies Cardmarket's product identifier, card details include an
**Open on Cardmarket** button that opens the matching marketplace product page.

Country-specific listings and optional currency conversion remain planned for
a later direct marketplace integration. Settings already lets you save an All
Countries or country-specific Cardmarket listing preference so that choice is
ready when seller-level listing support is added; it does not alter TCGdex's
current Europe-wide aggregate.

## Reporting catalog data

TallyDex uses TCGdex as its single source for card, set, and printing data.
Missing or incorrect cards can be reported from **Settings → Missing or
Incorrect Card**, which links to the TallyDex GitHub issue tracker. Reports
should include the set name and code, card name and collector number, the
missing or incorrect data, and a reliable source or clear photo.

## Portable collection backups

**Settings → Export & Import** creates a versioned `.pokecollection` JSON
backup or a human-readable CSV export. Full backups preserve owned quantities
and printings, set goals and visibility, custom folders, wishlist, and notes.
Imports show additions, changes, conflicts, skipped records, and removals before
anything is applied. Merge is idempotent and keeps newer local conflicts;
Replace requires confirmation. TallyDex saves a local rollback snapshot before
either mode changes collection data.

## License

TallyDex's original source code, interface, documentation, name, and artwork
are proprietary and all rights are reserved. See [LICENSE](LICENSE).

TCGdex data, GRDB.swift, Pokémon card imagery, names, logos, and other
third-party material remain under their own licenses or owners' rights. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
