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
history views.

When TCGdex supplies Cardmarket's product identifier, card details include an
**Open on Cardmarket** button that opens the matching marketplace product page.

Country-specific listings and optional currency conversion remain planned for
a later direct marketplace integration. Settings already lets you save an All
Countries or country-specific Cardmarket listing preference so that choice is
ready when seller-level listing support is added; it does not alter TCGdex's
current Europe-wide aggregate.

## License

TallyDex's original source code, interface, documentation, name, and artwork
are proprietary and all rights are reserved. See [LICENSE](LICENSE).

TCGdex data, GRDB.swift, Pokémon card imagery, names, logos, and other
third-party material remain under their own licenses or owners' rights. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
