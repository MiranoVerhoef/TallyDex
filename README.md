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

Completed in v0.9.4:

1. Camera mode can be switched directly between Auto and Manual on the Camera
   screen. Auto tracks the card boundary in live frames and captures only after
   the complete outline remains stable; the shutter remains available in both modes.
2. Rectangle detection now rejects small inner and partial contours, favours the
   largest credible card-shaped region, and accepts moderate camera angles for
   perspective correction.
3. OCR matching tolerates small spelling damage across a complete card title and
   ranks the full local catalogue name, fixing scans such as Pikachu with Grey Felt
   Hat without weakening the unrelated-name safeguard.
4. Added a registered `.tallydexcard` document for passing an exact card locally
   through Files or AirDrop. Messaging apps do not consistently open custom file
   types or custom URL schemes, so this is not treated as a universal-link replacement.

Camera follow-up: live automatic capture remains experimental and Manual is the
default while catalogue, collection, and metadata work continues. Regular sharing
is being split into one clean card-image share and a separate TallyDex document
export so messaging apps never receive two unrelated-looking attachments.

Completed in v0.9.5:

1. TallyDex now stores TCGdex's exact detailed printing records internally when
   the provider supplies them: stable printing ID, type and subtype, stamps, foil
   pattern, standard/jumbo size, language availability, and Cardmarket,
   TCGplayer, or CardTrader product IDs. Card details keep the simple collector-
   facing Printings list such as Normal and Reverse Holo.
2. Existing installations perform a one-time per-card metadata refresh, and exact
   printing records are cached locally in a dedicated database table. An older or
   incomplete response cannot erase already cached detailed records.
3. Cards without provider-supplied detailed printings keep their honest broad
   printing fallback. TallyDex does not invent exact printings, and existing
   ownership remains grouped by broad printing type until it can be migrated
   without losing quantities or backup compatibility.
4. Card sharing now explicitly offers either one clean image or one TallyDex card
   document, preventing messaging apps from displaying two separate attachments.

Completed in v0.9.6:

1. Card details are collector-facing again: **Printings:** followed by simple rows
   such as Normal and Reverse Holo. Detailed provider identifiers remain cached
   internally and no longer clutter the card screen.
2. A Collection can use any currently matching card as its cover image or keep one
   of the existing symbols. The selected card cover is preserved in rollback
   backups, JSON import/export, and readable CSV export.
3. The missing-artwork roadmap now explicitly includes a one-time download tool
   with an estimate, Wi-Fi guidance, progress, cancellation, and cache-limit safety.

Completed in v0.9.7:

1. Ownership can now be stored against the exact TCGdex printing ID while the
   everyday interface keeps collector-friendly names such as Normal and Reverse Holo.
2. Existing broad ownership is migrated only when there is exactly one matching
   provider printing. Ambiguous or unavailable matches remain as honest broad
   fallback records, so TallyDex never guesses which printing is owned.
3. A one-time rollback backup is created before exact migration. JSON backups now
   use schema version 2, preserve exact and fallback ownership together, and still
   import schema-version-1 backups.
4. Master and Custom progress count exact provider printings where available. One
   old unspecified check can satisfy one printing slot, never falsely complete all
   similar printings.

Completed in v0.9.8:

1. Missing card art is repaired only through exact, verified identities. TCGdex
   gallery and vault subsets use their confirmed parent asset paths; no set or
   collector number is guessed.
2. Riolu GG26 in Crown Zenith Galarian Gallery now loads from the existing TCGdex
   asset. Numeric MEP promos—including Riolu 010 and Mega Lucario ex 012/033—use
   their matching official Pokémon card asset when TCGdex omits the image field.
3. Recovered images use the same bounded local cache as normal artwork. They load
   on demand when a set, search result, or card is viewed; there is no full-library
   bulk download.
4. Broken universal TCGdex symbol links are repaired to the verified English asset
   path. Failed detail artwork falls back to its usable thumbnail, and a real
   placeholder replaces endless loading when no exact source exists.

Completed in v0.9.9:

1. The exact artwork fallback now applies automatically to every TCGdex card whose
   image field is missing, using the same set ID and collector number on Pokémon's
   official asset service.
2. Verified aliases cover legacy and subset IDs whose official asset directory is
   different, including SM35, SM75, Galarian Gallery, McDonald's collections, and
   early Trainer Kits. Numeric collector numbers are normalized without changing
   alphanumeric promo numbers such as SM192.
3. A live audit of all 1,717 current TCGdex image omissions found 716 exact working
   assets. This includes Lucario & Melmetal GX SM192 and Lucario GX 122 from
   Forbidden Light. The remaining cards keep the TallyDex placeholder rather than
   receiving an uncertain or nearby image.
4. The automatic resolver uses TCGdex and Pokémon's official asset host only. It
   does not depend on GitHub or the deprecated community Pokémon TCG API.

Completed in v0.9.14:

1. First launch now presents a four-page introduction to browsing, scanning,
   collection tracking, and price preferences. The setup includes live choices for
   the starting Sets view, set organization, appearance, default collection goal,
   and exact copy counts.
2. Every future app version can present its own What’s New sheet once after update.
   Release notes are stored by version, and a completed version is not shown again.
3. Settings → Help & Updates keeps the current What’s New notes available and adds
   Reset Introduction so setup can be replayed without resetting collection data.
4. Setup now includes a truthful EUR or USD price preference: EUR selects native
   Cardmarket data and USD selects native TCGplayer data. TallyDex does not silently
   convert one marketplace’s values into the other currency.
5. Detailed card responses now preserve Pokédex IDs, HP, types, evolution, attacks,
   abilities, weakness, resistance, retreat cost, regulation mark, legality, rules
   text, flavor text, and TCGdex’s card-data timestamp. Card pages group these into
   compact facts and readable mechanic cards, and omit unavailable fields.

Completed in v0.9.13:

1. Restoring an automatic collection backup now opens a full impact preview before
   confirmation, matching file-import restores with additions, changes, unchanged
   records, removals, and an exact change list. The current collection is still
   saved first so every restore remains reversible.
2. Browser Editor cards now size naturally per grid row instead of stretching every
   card to the tallest item in the complete result set. Compact six-column layouts
   use responsive artwork, two-line titles, concise Details and Market actions, and
   hover text for full names without clipping words.
3. Card tiles use lighter borders, responsive spacing, and compact action icons while
   keeping controls aligned and cards in each row a consistent height.

Completed in v0.9.12:

1. Cache verification is now invisible when every requested image is already on
   the device. **Downloading and caching images** appears only when TallyDex has
   real missing artwork to fetch.
2. Thirty-five user-supplied WebP logos are bundled directly in the IPA for
   McDonald's collections, promo sets, Trainer/Galarian Galleries, and other
   missing set artwork. Bundled logos work offline and override an absent or
   broken provider logo; the native McDonald's year badge remains the fallback.
3. The app does not scrape a third-party site or depend on one at runtime.
   Additional artwork can be bundled through the same exact set-ID mapping.

Completed in v0.9.11:

1. Scarlet & Violet series and set logos load from TCGdex's WebP assets instead
   of assuming every extensionless logo has a PNG copy. Existing complete image
   URLs and PNG expansion symbols remain unchanged.
2. McDonald's Collection has a small bundled native badge on the series screen.
   TCGdex does not provide a generic series logo, so the badge has no remote image
   dependency and does not reuse a year-specific campaign graphic.
3. TallyDex checks announced and recently released sets once per hour while the app
   launches or returns to the foreground. Exact provider IDs or exact normalized
   names can replace an announcement with its real cover and cards; near matches
   are rejected, and unmatched announcements remain visible after release day.
4. Opening a Collection now warms and compresses its grid artwork with the same
   visible **Downloading and caching images** progress and fingerprinting used by
   set pages.

Completed in v0.9.10:

1. The first visit to a released set now warms every grid image into the automatic
   cache and shows live **Downloading and caching images** progress. A catalogue
   fingerprint prevents repeat downloads, while newly added cards automatically
   trigger another warm-up.
2. Card images are resized and JPEG-compressed on the device before storage when
   the optimized copy is smaller. Grid thumbnails use a 480-pixel ceiling and full
   artwork uses a 1,600-pixel ceiling with higher quality.
3. Existing uncompressed automatic artwork is replaced by the new optimized cache
   on upgrade. Offline-set downloads remain separate and are never silently removed.
4. Clearing thumbnail or all automatic artwork also resets set warm-up records, so
   the next set visit repopulates the cleared cache.

Research and later builds:

1. Use the stored Pokédex IDs for reliable Pokémon-focused Collection rules without
   depending only on names; support cards containing multiple Pokémon IDs.
2. Add Cardmarket low prices and TCGplayer low, mid, high, and direct-low values.
   Treat them as market statistics, never as substitutes for a missing exact
   printing price.
3. Add regulation marks and TCGdex-reported Standard/Expanded legality, with
   refresh dates because tournament legality changes over time.
4. Show provider-reported Normal, Holo, Reverse, and First Edition set counts,
   clearly labelled as TCGdex totals.
5. Add optional filters for the stored HP, type, evolution, regulation, legality,
   attacks, abilities, and other rich card fields. Scanner ranking may use this
   only as supporting evidence.
6. Add optional booster membership and pack artwork where TCGdex supplies it;
   incomplete provider coverage must be shown honestly.
7. Continue the missing-art audit for the remaining 1,001 genuine provider gaps. Add a
   fallback only where set, collector number, source permission, and image identity
   can all be verified; otherwise keep the honest TallyDex placeholder.
8. Research another permitted card/catalogue/price API, including its licence,
   attribution, rate limits, coverage, and whether it can be an optional provider
   without weakening TCGdex correctness.
9. Activate country-specific Cardmarket listings only if permitted official API
   access becomes available; the provider boundary and preferences already exist.
10. After Apple Developer Program enrollment: private iCloud sync, TestFlight, an
    optional StoreKit Tip Jar, and—only with an independently controlled HTTPS
    domain—true universal card links with rich previews.
11. Binder planner.
12. Finish automatic live card scanning after the remaining catalogue and
    collection work: improve live-frame OCR, confidence ranking, glare handling,
    top-loader detection, and real-device validation. Promote Auto from Beta to the
    default camera mode once it reliably identifies a varied real-card test set and
    falls back to confirmation instead of presenting low-confidence false matches.

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

Next-version backlog: use stored Pokédex IDs in Pokémon-focused Collection rules,
then continue the verified missing-art audit.

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
