# Collection exports and layout — 0.9.53 (89)

Development/AltStore follow-up to 0.9.52. No TestFlight or App Store upload.

## Collection tab

- The existing value card is first when ownership is present.
- Wishlist is its own native rounded card directly below value, with the saved
  count and a link to the existing wishlist screen.
- Binder Planner and Collector Badges follow, then Pokémon collections and the
  existing owned-card section. Pricing, wishlist storage and ownership are unchanged.

## Missing-card exports

- Pokémon collections now have an Export Missing toolbar action. It includes the
  entire collection match list regardless of search, ownership segments, other
  browsing filters or the folder's default display mode.
- The report applies each source set's Normal/Master/Custom goal, preserves exact
  printing ambiguity and secret-card exclusions, deduplicates canonical card IDs,
  and refuses unavailable set/printing metadata rather than silently omitting it.
- Source set names appear beneath card names in collection PDFs. Image exports
  include the source set code beside the collector number.
- Both export formats omit “Missing from my collection” and “Missing-card
  checklist” headings/footers. Only the title, goal, counts, date and page number
  remain. The original logo is retained.
- PDF thumbnails increased from 26×36 to 44×61 points, with taller rows and
  content-based page breaks. A4 pages normally fit seven rows; printing text and
  multi-set source names wrap without shrinking the thumbnails.
- Exports remain read-only, use the existing artwork pipeline and generate their
  own temporary files. No new artwork is bundled.

## Verification

Evidence is retained in `artifacts/collection-export-followup/`.
All 247 unit tests passed, including multi-set goals, duplicate identities,
missing catalogue metadata, clean PDF text, enlarged image dimensions and
pagination. Real bundled Aquapolis artwork was used to render and visually check
both pages of the updated PDF and the clean image poster.

All eight targeted UI tests passed on iPhone 18 Pro with iOS 27, running hidden.
They cover the value → wishlist → planner layout, collection exports across sets
and while viewing Owned cards, existing set exports, wishlist/search, filters,
bulk-edit undo, dark mode and larger accessibility text. Collection and export
screenshots were visually checked as well.

## Release package

Version 0.9.53, build 89, development channel, minimum iOS 26.0. The unsigned
device archive succeeded. IPA ZIP integrity passed; size is 30,476,815 bytes.
SHA-256: `80300973503ee830bd0b6fd3659183efdec8438bb3995d8313e25edb8c2e0c6d`.

Release-specific evidence is retained in `artifacts/v0.9.53/`. After the version
bump, all 247 unit tests and all 11 targeted iOS 27 UI tests passed. These repeat
the eight follow-up checks and also verify completing setup, skipping setup and
showing update notes exactly once with the new version.

The Release simulator build also succeeded and reports the same version, build,
distribution channel and minimum OS as the device archive. It installed and
launched successfully on iPhone 18 Pro / iOS 27, hidden, displaying the correct
0.9.53 notes without a purchase gate. The final layout screenshot was visually
checked again. Release binaries exclude the reliability fixture markers.

The GitHub asset size/digest and canonical AltStore feed are verified during
publication, after uploading the IPA and before reporting completion.
