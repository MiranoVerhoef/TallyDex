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
