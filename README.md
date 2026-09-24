# TallyDex

TallyDex is a private, local-first Pokemon card collection tracker for iPhone.

The name combines **tally**—counting what you own or still need—with
**dex**, a compact indexed catalog like a Pokédex. TallyDex is your
collection-counting card index.

## Requirements

- macOS 26.2 or later
- Xcode 27.0
- iOS 27.0 Simulator runtime

## Build

```sh
xcodebuild \
  -project TallyDex.xcodeproj \
  -scheme TallyDex \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -derivedDataPath .build/DerivedData \
  build
```

## Test

```sh
xcodebuild \
  -project TallyDex.xcodeproj \
  -scheme TallyDex \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -derivedDataPath .build/DerivedData \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- \
  test
```

The scheme includes unit tests and an isolated UI reliability suite. To run only
one suite, add `-only-testing:TallyDexTests` or
`-only-testing:TallyDexUITests`. UI fixtures explicitly opt in through launch
arguments, use a separate UUID-scoped database and preference suite, and are
excluded from Release builds. Use a separate release-only DerivedData directory
when packaging an IPA; never package test-run products.
Local StoreKit tests use `Products.storekit`; the simulator build must be
ad-hoc signed so the trial anchor can be saved in Keychain. Purchase gating is
opt-in for Debug with `-AccessGateTesting` and disabled in Release until the
App Store product and launch policy are ready.

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
Artwork defaults to a 400 MB automatic least-recently-used ceiling, configurable
from 100 MB to 2 GB in Settings → Artwork Cache. Older card images are removed
before core series, set, and expansion artwork. Lowering the limit trims immediately.

## Offline sets

Touch and hold a released set and choose **Keep Offline** to download its complete
card metadata, printing variants, grid images, and full-size artwork. TallyDex
shows an estimated size before downloading, progress while it works, and an
Offline badge when the set is complete. Explicit downloads live separately from
the automatic artwork cache, so its cleanup never removes them. Manage
individual downloads in Settings → Offline Sets.

## API and card images

Settings → Advanced configures the first TCGdex API source. It defaults to
`https://tcgdex.tallydex.nl/v2/en/`, accepts an HTTPS origin or the English API
root, and provides a connection check against the series list and an exact card.
Disabling **TCGdex Development API** starts with official TCGdex. Its adjacent
info button explains that the configured endpoint runs the development version
of TCGdex for faster card updates. API metadata requests
fall back to `https://api.tcgdex.net/v2/en/` when the custom source fails. Failed
hosts back off briefly; source-specific ETags prevent cross-provider 304 mistakes.

For uncached card images, the ordered sources are: development API's exact-card image
field, official API's exact-card image field, verified parent-set paths, bundled
thumbnails, Pokémon's official exact-set/collector-number host, then placeholder.
No image CDN path is inferred from an API hostname. Existing cached artwork and
kept-offline downloads are reused without a network lookup. The 842 primary
bundled WebP thumbnails have exact-ID mappings in
`TallyDex/Resources/BundledCardThumbnails/manifest.json`. Its 48 My First Battle
variant files retain their original mappings and do not create new printings or
duplicate card counts. All 887 supplied checksums were validated before import;
these are thumbnail-sized fallbacks, not new high-resolution scans.

## Roadmap order

### Before public release

- [ ] Add a 14-day full-feature trial followed by one permanent lifetime unlock.
  This is deliberately deferred until immediately before public release; current
  development stays focused on bug fixes, reliability, and the learned scanner.
  The trial must never auto-renew or charge automatically. Use Apple's
  non-subscription trial structure and a paid non-consumable In-App Purchase for
  lifetime access. Before the trial starts, clearly show its duration, the
  lifetime price, and what changes when the trial ends. Existing collection data
  must remain readable and exportable after expiry. StoreKit work must cover
  purchase restoration, receipt and DeviceCheck-based trial validation, refunds
  and revocations, offline and pending states, Family Sharing eligibility, and
  sandbox testing. Decide separately whether existing beta users are grandfathered.
  No subscription is planned.

### Next fixes requested — 2026-09-13

- [x] Single loading indicator beside set goal-slot counts. Card-list loading and
  printing-rule preparation now share one spinner until both finish. Implemented
  in v0.9.21.

- [x] Verified 2022–2024 Trick or Trade checklists, each with 30 pumpkin-stamped
  printings. Checklists share canonical original card IDs and exact ownership;
  no duplicated card records or inferred stamp artwork. Later yearly releases
  require verification before being added.
- [x] Group McDonald's releases inside their corresponding main series/era,
  alongside the regular expansions, rather than a separate top-level McDonald's
  listing. Use [Pokellector's set catalogue](https://www.pokellector.com/sets) as the
  browsing reference: XY collections under XY, 2017–2019 collections under Sun &
  Moon, 25th Anniversary/Match Battle under Sword & Shield, and Match Battle 2023/
  Dragon Discovery under Scarlet & Violet. Each release remains its own set with
  unchanged IDs, ownership, goals, and backups; this is grouping, not merging cards
  into an unrelated expansion or changing Master completion requirements.
- [x] Add available supplemental Energy sets under the appropriate series/era.
  v0.9.22 verified the existing SVE (24) and MEE (8) coverage while preserving
  exact identities and avoiding duplicate collection totals. The supplemental
  read-only Energy overview was removed in v0.9.23; actual Energy sets stay intact.
  Older unnumbered designs absent from TCGdex are provider-dependent and are not
  an active manual-catalogue task.
- [x] TCGdex development API channel at `tcgdex.tallydex.nl`, configurable and checkable
  in Advanced settings, with official-provider fallback and bundled thumbnails.

Keep these catalogue fixes clean in the UI. Verify coverage and exact mappings
before implementation; Pokellector is an organization reference, not a new runtime
API or permission to copy its card artwork.

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

Completed in v0.9.17:

1. New Collections now use a searchable catalogue-backed Pokémon picker instead
   of an unchecked name field, preventing spelling mistakes.
2. Pokémon card labels and forms are grouped into one species rule. Choosing
   Lucario includes Lucario-GX, Lucario V, Lucario ex, Mega Lucario, Lucario C/GL,
   and tag-team cards containing Lucario, while excluding Trainer cards such as
   Lucario Spirit Link.
3. Existing free-text Collection rules retain their original behavior. Species
   selections survive automatic backups and portable JSON/CSV exports.

Completed in v0.9.18:

1. Collections can contain one or two catalogue-selected Pokémon. Cards featuring
   either species are included, and a card matching both is counted only once.
   The second selection is optional, replaceable, and removable from one compact
   collection editor; Printings and card-page preferences are unchanged.
2. Species rules now save a verified Pokédex ID where available. Matching uses
   cached card IDs, including cards with multiple Pokémon IDs, and falls back to
   canonical species names only when the necessary ID metadata is absent. Trainer
   and Energy cards are excluded. IDs are never assigned by guessing tag-team order.
3. Older one-Pokémon rules can resolve IDs from cached metadata, while original
   free-text rules retain substring matching. Database migration v12 and portable
   backup schema 4 preserve both Pokémon selections and their IDs through edits,
   automatic backups, merge imports, and replacement restores.
4. Updated What’s New notes explain two-Pokémon collections and ID-based matching.

Completed in v0.9.16:

1. Completing the introduction on a fresh install now uses an explicit completion
   transition instead of re-evaluating setup during sheet dismissal. Onboarding
   appears once, and the current build’s What’s New sheet no longer follows it;
   later app updates still present their notes once.

Completed in v0.9.15:

1. The optional rich Card details block now starts collapsed, keeping card pages
   compact while leaving artwork, identity, Printings, prices, personal notes, and
   collection controls unchanged.
2. Settings → Card Pages can make that block expanded by default. Each card page
   can still be expanded or collapsed independently.

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

### Actually remaining — audited 2026-09-17

1. Keep bug fixes and reliability first. Every development build should add a
   regression test where practical and pass the iOS 27 unit, UI, release-build,
   and requested visual/hidden simulator checks before it is published.
2. Finish the learned camera detector. Scan Lab, its reviewed-data goals, export,
   integrity checks, and Create ML training tool are complete. The remaining work
   is to collect and review the real dataset, train and measure the model, integrate
   the accepted Core ML model into TallyDex, and validate automatic capture on a
   physical iPhone across glare, sleeves, top loaders, angles, and hard negatives.
3. Immediately before public release, implement the 14-day trial and lifetime
   unlock, choose whether existing beta users receive lifetime access, test
   purchase restore/refund/revocation/offline behavior, add App Store privacy and
   product metadata, and complete a TestFlight release pass. App Store Connect
   product setup and real sandbox purchases require Apple Developer enrollment.

### Requested next features — 2026-09-23

- Added a compact dashboard above Sets with collection-wide distinct-card and
  physical-copy counts, My Sets goal completion, collection value, and an
  expandable top-10 priced-card ranking.
- Add TallyDex-exclusive collector badges earned from verifiable collection
  milestones; define the badge catalogue and thresholds before implementation.
- Collection Manager now has search within the loaded set, independent controls
  to hide/show Details and Market actions, and paired-browser import/export
  with preview and rollback protection.
- Let users choose a binder background color when creating or editing a binder;
  preserve that choice in backups and imports.
- Make the camera guide a loose scan focus area so a card need not line up exactly
  with its border; verify how candidate selection works before changing capture.
- Set the intended one-time lifetime unlock price to €9.99. The local StoreKit
  configuration can test this now; the real price still needs App Store Connect.

Optional later enhancements, not current blockers:

- Expand PriceCharting matching to additional product-name conventions as real
  exports become available. Unmatched rows remain visible in the import preview
  and are never guessed or added automatically.
- Add provider-supplied Cardmarket low and TCGplayer low/mid/high/direct-low market
  statistics if exact-printing data is available.
- Add provider-reported Normal, Holo, Reverse, and First Edition set totals.
- Expand Collection filters beyond the implemented ownership, type, era, set,
  rarity, release-year, and sort controls to HP, evolution, regulation, legality,
  attacks, and abilities where metadata exists.
- Add booster membership and pack artwork where provider coverage is sufficient.
- Activate country-specific Cardmarket listings only if permitted official API
  access becomes available.
- After enrollment, consider private iCloud sync and—only with an independently
  controlled HTTPS domain—universal card links with rich previews.

No active app work is needed for Energy coverage, ordinary TCGdex catalogue and
artwork additions, or missing-art provider gaps. TallyDex already refreshes the
provider catalogue and uses its verified fallback chain; unavailable identities
remain honest placeholders until upstream data changes. Regulation marks,
Standard/Expanded legality with the provider update date, Collection filters, and
Binder Planner are already implemented.

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
Open **Settings → Collection Manager**, start sharing, then enter the displayed local
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
needed. **Collection Manager → Allow access while app is minimized** is off by default.
When enabled, the server remains available while iOS permits background execution;
return to TallyDex if iOS suspends it.

Pokédex-ID species matching is already implemented. The active camera backlog is
the reviewed Scan Lab dataset, trained detector integration, and physical-iPhone
validation. Missing-art gaps are provider-dependent and are not an active manual
catalogue project.

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

Completed in v0.9.19:

- Configurable custom TCGdex API, defaulting to `tcgdex.tallydex.nl`, with an
  Advanced connection check and automatic official-provider fallback.
- Exact-ID artwork routing through both APIs, verified parent paths, bundled
  thumbnails, Pokémon's official asset host, and finally a placeholder.
- 842 primary thumbnails and 48 separately mapped variant files from the supplied
  handoff; all 887 SHA-256 checksums validated before bundling.
- Source-scoped catalogue ETags and automatic artwork caches; explicitly kept
  offline API images use exact-card keys so changing hosts preserves availability.
- Updated What's New notes; card-details preferences and printings stay unchanged.

Completed in v0.9.20:

- Bundled matching logos for Scarlet & Violet Energy (`sve`) and Black Star
  Promos (`svp`) where the API omits its artwork links.
- Artwork Cache has a persisted 100 MB–2 GB limit picker, with 400 MB unchanged
  as the default. Changes take effect immediately without restarting; offline
  downloads and bundled resources are excluded from automatic cleanup.
- Advanced settings use the TCGdex Development API label and a small info button explaining
  its development-version TCGdex service and faster card updates.
- Updated What's New notes; collection data and card-detail preferences unchanged.

Completed in v0.9.21:

- McDonald's releases appear inside their matching eras in both catalogue layouts
  and All/My Sets/Hidden scopes. Grouping is presentation-only: provider series IDs,
  set/card identities, ownership, goals, offline keys, and backups do not change.
- Supplemental releases use their release dates to join the existing set order.
  Unknown future releases or missing parent eras stay in their provider group;
  the top-level McDonald's group disappears only when all its sets were moved.
- One spinner beside goal-slot counts covers card loading and printing-rule
  preparation together. Updated What's New notes explain both changes.

Completed in v0.9.22:

- Trick or Trade 2022 under Sword & Shield, and 2023/2024 under Scarlet & Violet.
  Thirty exact parent-card IDs per release are cross-checked with the English API
  index. Pumpkin-stamp ownership is stored once on the canonical card, shared
  between checklist and card details. Normal copies are not changed by checklist
  checks, and old broad ownership never automatically checks a pumpkin stamp.
- Known provider printing IDs stay intact; curated printing IDs remain stable
  where the API omits a stamp. Provider printings not represented by a checklist
  entry stay visible. Curated stamps have a separate printing kind so regular
  parent-card prices are not presented as prices for them. Original Master goals
  can now include verified pumpkin printings; existing quantities are not migrated.
- Images in checklists are clearly labelled as original artwork that may not
  picture the stamp. Checklists do not offer independent offline pinning; keep
  original sets offline for their shared metadata and artwork.
- Energy overviews reuse cards already represented by TCGdex, including numbered
  expansion Energies and the existing SVE/MEE sets. These read-only views do not
  create cards, ownership, goals, or new expansion completion requirements.
- Settings → Advanced → Missing Artwork Report records up to 1,000 observed
  failures, with exact card IDs, last-check time, search, sharing, and cancellable
  rechecks. Network errors may be temporary. Successful fallback loads clear a
  card; an empty report does not establish complete catalogue artwork coverage.
  Explicit rechecks bypass remembered missing-image results without deleting art.

Completed in v0.9.23:

- Removes the supplemental Energy overview presentation rows and screen, without
  touching the real Energy sets, card identities, ownership, or goals.
- Replaces the sprawling Settings form with a compact menu. Appearance & Browsing
  contains theme, set scope/layout, and the card-details default. Collection
  Preferences contains goal/copy tracking and Custom defaults. Prices & Currency
  contains the marketplace choice and collapsed future listing preferences.
- Storage, backups, export/import, and local Collection Manager remain directly
  accessible. Catalogue Index is under Advanced; privacy/sync status and a
  confirmed Replay Introduction action are under About. Existing storage keys
  and saved choices are unchanged. What's New explains the reorganization.
- Bundles Trick or Trade 2022–2024 and My First Battle logos, plus the original
  Yellow A mark. Hidden Fates Shiny Vault uses its parent Hidden Fates logo with
  a native Shiny Vault label (not a claimed standalone official logo). These six
  assets are at most 420 × 160 pixels and under 20 KB each, with transparency.
  Set IDs, cards, and goals remain unchanged.

Completed in v0.9.24:

- Verified with 173 unit tests and six end-to-end UI tests.
- Keeps the existing UI and preference keys unchanged.
- Adds isolated end-to-end checks for completing/skipping setup, update notes
  appearing once, restore-preview cancellation, confirmed restore/replace,
  rollback, merge conflict handling, and preferences surviving relaunch/restore.
- Exercises exact normal and Trick or Trade ownership through a file-backed
  database restart, merge, replace, and rollback; one- and two-Pokémon collections
  continue to reference the same canonical card instead of duplicating ownership.
- Defensively deduplicates repeated canonical ownership references in value
  summaries. Distinct variants remain separate, and unpriced stamped cards never
  borrow an unstamped card's price.

Completed in v0.9.25:

- Verified with 179 unit tests and eight end-to-end UI tests.
- One toolbar button opens a compact collection Filter sheet. Type, era, exact
  set, rarity, ownership, release year, and sort order live together rather than
  adding controls to the card grid or Settings.
- Apply accepts a draft; Cancel or swipe dismissal discards it. Reset restores
  the collection's initial All/Owned view and newest-release sort. Browsing
  choices last for this visit only and are not saved into species rules/backups.
- Filtered results say how many of the collection's cards are shown. Ownership,
  completion, percentage, and value summaries continue to describe the whole
  collection. Empty results offer Clear filters, including clearing the search.
- Type and rarity use available cached provider metadata, never names or inferred
  attributes. Missing fields remain visible with All types/All rarities. Options
  come from the collection's matching cards; dual-type cards can match either
  type. Era/set filtering uses provider IDs, not potentially repeated names.
- Selecting an era narrows the set choices and clears an incompatible selected
  set. Existing one-/two-Pokémon species matching, exact-printing checkmarks,
  settings, card-detail collapse defaults, and collection membership are unchanged.

Completed in v0.9.26:

- Replaces TCGdex's empty Miscellaneous “Jumbo cards” shell with era-level
  “Jumbo Promos” checklists. Mega Evolution, Scarlet & Violet, Sword & Shield,
  and every older era with verified jumbo metadata get their own row.
- Uses 145 canonical card records and 152 exact oversized printings from the
  live English TCGdex data. Cards with two distinct jumbo products keep two
  independently trackable entries rather than being collapsed by card number.
- The era checklist and original card detail share the same provider printing
  identity. Checking or removing a jumbo in either view immediately applies to
  both, while regular-size ownership remains separate.
- Adds Jumbo as a first-class printing type for custom goals, filters, exact
  ownership, backups, and marketplace identifiers. A compact generated badge
  keeps the set list visually consistent without adding another bundled image.
- Updates the one-time What’s New sheet for version 0.9.26.
- Verified with 183 unit tests and eight end-to-end UI tests on the iPhone 18 Pro
  iOS 27.0 simulator.

Completed in v0.9.27:

- Adds Binder Planner as a prominent entry at the top of Collection. Plans can
  use an existing one- or two-Pokémon collection or any catalogue set without
  changing ownership or the source collection.
- Generates clean physical pages for 9-pocket and 12-pocket binders. Missing
  cards can remain visible as planned spaces or be hidden for an owned-only
  layout, with page navigation and owned/missing status on every pocket.
- Follows each set's current Normal, Master, or Custom goal. Master and Custom
  plans create separate pockets for exact printings when provider metadata is
  available; legacy broad ownership fills one compatible pocket rather than
  incorrectly filling every printing.
- Saves multiple editable plans locally on the device. Plans can be renamed or
  deleted and are deliberately separate from collection ownership.
- Jumbo Promos rows now reuse the same bundled or remote logo as the matching
  normal promo set for their era, keeping those rows consistent with the set list.
- Updates the one-time What’s New sheet for version 0.9.27.
- Verified with 186 unit tests and nine end-to-end UI tests on the iPhone 18 Pro
  iOS 27.0 simulator.

Completed in v0.9.28:

- Adds per-plan ordering by set release, newest release, Pokémon name, or Pokédex number.
- Preserves Set release order for existing plans and supports changes through long-press → Edit.
- Removes the duplicate add button from Binder Planner.
- Verified with 187 unit tests and nine end-to-end UI tests on the iPhone 18 Pro iOS 27.0 simulator.

Completed in v0.9.29:

- Matches the current 4-, 9-, 12-, 12-pocket XL, and 16-pocket XXL Vault X binder formats and capacities.
- Corrects 12-pocket pages to a four-column by three-row layout and reports when a plan needs multiple binders.
- Migrates existing binder plans into collection storage so backups, restore previews, and portable exports include them.
- Verified with 190 unit tests and nine end-to-end UI tests on the iPhone 18 Pro iOS 27.0 simulator.

Completed in v0.9.30:

- Integrates the optional TallyDex Assets API as the first card artwork and metadata resolver.
- Merges locally supplied overlay cards and sets into the catalogue while preserving TCGdex fallbacks.
- Adds a clear Advanced setting and service check; disabling it stops requests to api.tallydex.nl.
- Uses returned immutable image URLs directly and caches resolver and overlay responses with ETags.
- Verified with 193 unit tests and nine end-to-end UI tests on the iPhone 18 Pro iOS 27.0 simulator.

Completed in v0.9.31:

- Keeps 30th Celebration and its Classic Collection inside Mega Evolution instead of creating a new catalogue group.
- Leaves future overlay sets out of browsing until their placement is verified.
- Simplifies the TallyDex Assets service result to Connected without exposing library counts.
- Verified with 193 unit tests and ten end-to-end UI tests on the iPhone 18 Pro iOS 27.0 simulator.

Completed in v0.9.32:

- Removes the TallyDex Assets API integration and restores the v0.9.29 TCGdex and bundled artwork flow.
- Removes its Advanced setting, service check, resolver, overlay catalogue merging, and related network requests.
- Keeps the separate repository security hardening and all collection data migrations intact.
- Verified with 190 unit tests and nine end-to-end UI tests on the iPhone 18 Pro iOS 27.0 simulator.

Completed in v0.9.33:

- Adds the collection ownership circle directly to camera matches, including long-press printing selection.
- Uses the verified 30th Celebration logo for both released 30th sets instead of the placeholder.
- Verified with 191 unit tests and nine end-to-end UI tests on the iPhone 18 Pro iOS 27.0 simulator.

Completed in v0.9.34:

- Reconciles saved ownership when TCGdex replaces provisional printing identities or corrects a card's variant, with a one-time rollback backup before migration.
- Replaces obsolete cached variants and current prices authoritatively while preventing older fallback responses from overwriting newer corrected card data.
- Groups collector number and card facts in the collapsible Card details section, then keeps Your collection and Cardmarket access near the top of the card page.
- Adds regression coverage for the supplied before/after 30th Celebration failure pattern and verifies backup, import, restore, and rollback flows on iOS 27.

Completed in v0.9.35:

- Removes card-detail scroll snapping for normal, continuous scrolling.
- Imports PriceCharting collection CSV with exact set, card, and printing matching, a review preview, and rollback backup; unmatched or graded rows are skipped.
- Exports saved PriceCharting product IDs back to CSV with current quantities, or a text list for cards without IDs. Product mappings are preserved in full backups.
- Bundles compact B, G, and R Mew thumbnails for 30th Celebration.

Completed in v0.9.36:

- Prepares a 14-day trial and one-time lifetime unlock with local StoreKit testing; beta access remains unlocked.
- Keeps collection viewing and backup export available after trial expiry, while editing waits for a verified purchase.

Completed in v0.9.37:

- Adds an optional coffee tip page with four consumable choices (€1.99, €2.99, €4.99, €9.99).
- Prepares a €4.99 lifetime launch price for local StoreKit testing; beta access remains unlocked.

Completed in v0.9.38:

- Adds a collection-wide dashboard above Sets with distinct cards, copies, My Sets goal progress, estimated value, and the top 10 priced cards.
- Renames Browser Editor to Collection Manager, adds in-set card search and independent Details/Market visibility controls.
- Supports paired-browser full backup and PriceCharting CSV import/export, with import preview and rollback backup.
- Changes the local StoreKit lifetime access test price to €9.99; beta access remains unlocked.

Completed in v0.9.39:

- Moves the collection dashboard to the top of Sets and presents collection value and top-priced cards in a focused hero card.
- Keeps distinct cards, copies, and My Sets progress directly beneath it, and avoids showing a false €0 value when exact prices are unavailable.

Completed in v0.9.40:

- Replaces the stacked dashboard cards with a compact, edge-to-edge Sets header containing value, artwork, collection counts, and a top-priced-card shortcut.
- Removes the excess top spacing and keeps Sets browsing directly beneath the header.

Supplemental cover sources:

- Trick or Trade logos: the respective [2022](https://www.pokellector.com/Trick-or-Trade-Collection/),
  [2023](https://www.pokellector.com/Trick-or-Trade-2023-Collection/), and
  [2024](https://www.pokellector.com/Trick-or-Trade-2024-Collection/) set headers.
- [My First Battle logo](https://bulbapedia.bulbagarden.net/wiki/File:My_First_Battle_logo.png)
  (file provenance identifies the official Pokémon My First Battle site).
- [Hidden Fates parent logo](https://assets.tcgdex.net/en/sm/sm115/logo.png),
  using the existing verified parent expansion, not a third-party custom logo.
- [Yellow A symbol](https://bulbapedia.bulbagarden.net/wiki/Yellow_A_Alternate_cards_%28TCG%29).

Coverage references (metadata only; no artwork copied):

- [Pokellector 2022](https://www.pokellector.com/Trick-or-Trade-Collection/),
  [2023](https://www.pokellector.com/Trick-or-Trade-2023-Collection/),
  [2024](https://www.pokellector.com/Trick-or-Trade-2024-Collection/).
- Bulbapedia [2022](https://bulbapedia.bulbagarden.net/wiki/Trick_or_Trade_2022_(TCG)),
  [2023](https://bulbapedia.bulbagarden.net/wiki/Trick_or_Trade_2023_(TCG)),
  [2024](https://bulbapedia.bulbagarden.net/wiki/Trick_or_Trade_2024_(TCG)).
- Pokémon's [2024 product release](https://www.pokemon.com/us/pokemon-tcg/product-gallery/trick-or-trade-booster-bundle-2024)
  establishes August 30, rather than the later date shown by the browsing reference.
- [TallyDex SVE API](https://tcgdex.tallydex.nl/v2/en/sets/sve) and
  [MEE API](https://tcgdex.tallydex.nl/v2/en/sets/mee): 24 and 16 exact Energy IDs on the development API as of September 22, 2026. The official API still has 8 MEE cards; the additional development records currently lack TCGdex-hosted images.

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
