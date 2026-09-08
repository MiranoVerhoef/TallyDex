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

Completed foundations:

1. Native series, set, card, search, collection goals, printings, wishlist, notes,
   My Sets, Hidden sets, custom Collections, backups, and CSV export.
2. TCGdex-backed pricing, exact-printing totals, rolling averages, locally built
   price history, Cardmarket links, cache controls, and offline set pinning.
3. Browser-based mass collection editing, catalogue pre-indexing, performance and
   accessibility hardening, photo-assisted search, and local image caching.
4. Goal-aware progress in Sets, Search, and Collection, note markers, collection
   icons, collapsed owned cards, and lossless switching between collection goals.

Completed in v0.9.3:

1. Live and library scans now use Apple Vision to find the physical card rectangle
   before reading it. TallyDex perspective-corrects that detected region for OCR.
2. After capture, the detected card receives a bright edge outline and moving scan
   line while matching runs. The status changes from finding to matching without a
   separate blocking dialog.
3. The captured still is constrained to exactly the same viewport as the camera
   preview, preventing the image from jumping sideways after the shutter is pressed.
4. Number-only matches are checked against the recognized card name before they
   are accepted, preventing an unrelated card such as Omastar from replacing a
   clearly read Bewear merely because OCR found a similar collector number.

Research and later builds:

1. Make shared cards openable from receiving apps that do not turn a custom
   `tallydex://` URL into a tappable link. Keep this native and local-only by
   investigating a small registered TallyDex card-link attachment with the artwork
   preview; do not reintroduce a hosted web redirect.
2. Expand TCGdex printing support with stable variant IDs, subtype, stamps, foil
   pattern, standard/jumbo size, language availability, and per-variant marketplace
   identifiers. Never infer a printing that TCGdex does not explicitly identify.
3. Store Pokédex IDs so Pokémon-focused Collections can match reliably without
   depending only on names; support cards containing multiple Pokémon IDs.
4. Add Cardmarket low prices and TCGplayer low, mid, high, and direct-low values.
   Treat them as market statistics, never as substitutes for a missing exact
   printing price.
5. Add regulation marks and TCGdex-reported Standard/Expanded legality, with
   refresh dates because tournament legality changes over time.
6. Store and display TCGdex's card-data update timestamp separately from pricing
   timestamps.
7. Show provider-reported Normal, Holo, Reverse, and First Edition set counts,
   clearly labelled as TCGdex totals.
8. Enrich card details and optional filters with HP, type, evolution stage,
   attacks, abilities, weaknesses, resistance, retreat cost, and flavor text.
   Scanner ranking may use this only as supporting evidence.
9. Add optional booster membership and pack artwork where TCGdex supplies it;
   incomplete provider coverage must be shown honestly.
10. Audit missing set/card artwork and bundle lawful local replacements or durable
   placeholders so the catalogue looks complete offline.
11. Add first-run introduction and preference setup, plus Reset Introduction in
   Settings.
12. Research another permitted card/catalogue/price API, including its licence,
   attribution, rate limits, coverage, and whether it can be an optional provider
   without weakening TCGdex correctness.
13. Activate country-specific Cardmarket listings only if permitted official API
   access becomes available; the provider boundary and preferences already exist.
14. After Apple Developer Program enrollment: private iCloud sync, TestFlight, and
   an optional StoreKit Tip Jar.
15. Binder planner.
16. Fully automatic on-device card scanner after the catalogue and collection flows
   are stable. Camera images must stay on device.

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

v0.8.0 reserves the direct Cardmarket listing integration without scraping or
pretending that current aggregate prices are seller listings. Settings now save
an official seller-country choice and EUR or USD display preference, while a
provider boundary is ready to connect once Cardmarket accepts permitted API
access. This release also starts final hardening: local browser sharing stops
whenever TallyDex is no longer active, tab labels respect the user's full
Dynamic Type setting, and backup import plus browser-session generation no
longer rely on forced unwraps.

v0.8.1 makes failures explicit and recoverable. Catalog search now distinguishes
an unavailable service from a genuine zero-result search and offers Try Again;
empty catalog and set screens offer the same recovery path. Cancelled requests
stop immediately, while server-requested retry delays are capped at 30 seconds.
Artwork is decoded before it is cached, and corrupt cached images are removed and
downloaded again automatically. Backup imports are preflighted with a 25 MB safety
limit before their contents are loaded, and foreground activation no longer starts
duplicate artwork work.

v0.9.0 adds photo-assisted card search on device. The Camera tab can capture a
card inside a guide or use an existing photo, reads its visible name and collector
number with Apple Vision on the iPhone, and presents catalog matches for confirmation.
No card is marked automatically. Search now understands collector notation such as
`076/217`, searches cached card metadata, and recognizes “Van Gogh” as the TCGdex
card named Pikachu with Grey Felt Hat. Card details can be shared through a TallyDex
deep link, and touching and holding the full artwork offers Save to Photos and Share.
Printing selection opens a chooser only when more than one relevant printing exists.

v0.9.1 makes scanning feel like a native camera: opening the Camera tab immediately
starts an embedded live preview, with an aligned card guide, a single shutter, and a
round Photos shortcut. Captured-image orientation is preserved for Vision, and OCR
can combine a printed set code and collector number such as `SVE EN 012`, including
language marks that Vision joins to the code. Results appear in a compact card sheet
without the previous confirmation copy. Shared cards include the cached card artwork
and a native `tallydex://` link that opens the exact card in the installed app. This
sharing flow is local and does not depend on a web page or GitHub Pages.

Photos from the library can be dragged and zoomed inside the card guide before
recognition. The smaller shutter stays clear of the guide. Shared artwork is also
attached for receiving apps that do not use the system link preview.
Save Image to Photos converts artwork to PNG and uses a queue-safe PhotoKit
callback, with duplicate save taps disabled while a save is in progress.

The Collection tab now calls custom folders **Collections**, offers ten selectable
icons, and opens with Owned cards collapsed. Collection icons are included in
exports and rollback backups; older backups still import with a default icon.
Progress circles follow the same set goal in Sets, Search, and Collections, so one
of two required printings shows a half circle. An orange dot marks cards with notes,
including after restarting the app. SM95 and SWSH186 retain TCGdex's Normal entry
alongside the existing stamped-printing choices; saved ownership is preserved.

**Settings → Catalogue Speed → Pre-index Complete Catalogue** refreshes the full
lightweight search index. Detailed card records and images continue to load as
needed. **Browser Editor → Allow access while app is minimized** is off by default.
When enabled, the server remains available while iOS permits background execution;
return to TallyDex if iOS suspends it.

Next-version backlog: audit missing artwork and bundle suitable replacements;
add introductory setup with collection preferences and an option to repeat it.

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

Country-specific listings and optional currency conversion are explicitly
reserved for when TallyDex can obtain permitted official Cardmarket API access.
Settings already saves an All Countries or official seller-country preference
plus EUR or USD, so enabling the provider later will not require a data
migration. These choices do not filter or convert TCGdex's current Europe-wide
aggregate.

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
anything is applied, with a drill-down listing every record that will change. Merge is idempotent and keeps newer local conflicts;
Replace requires confirmation. TallyDex saves a local rollback snapshot before
either mode changes collection data.

## License

TallyDex's original source code, interface, documentation, name, and artwork
are proprietary and all rights are reserved. See [LICENSE](LICENSE).

TCGdex data, GRDB.swift, Pokémon card imagery, names, logos, and other
third-party material remain under their own licenses or owners' rights. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
