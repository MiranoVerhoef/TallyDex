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
