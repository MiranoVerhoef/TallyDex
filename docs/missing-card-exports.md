# Missing-card checklists — 0.9.52 (88)

Development/AltStore release. No TestFlight or App Store upload.

## Export Missing

- Open a set's share/actions menu and choose **Export Missing**. Keep offline /
  Remove offline download remains available in that same menu; information is
  still a separate toolbar action.
- Choose Images or PDF, preview the first page, then share using the system sheet.
- Images contain up to nine cards per page. Short final pages crop to their row
  count. The original logo, navy tiles and minimal footer follow the approved
  example; no trading tagline is included.
- PDF exports are A4 checklists with thumbnails, collector numbers, checkboxes
  and full missing-printing labels. Long variant lists receive separate rows;
  page breaks depend on content height. Images summarize unusually long lists
  and direct the reader to the PDF for full detail.
- Missing counts use the existing collection progress calculator for the entire
  set and current Normal/Master/Custom goal, independent of search or filters.
  Duplicate physical copies do not satisfy extra printing slots. Custom secret
  exclusions are respected.
- Unspecified broad ownership and stale exact provider IDs are not assigned to
  invented exact printings. Exports label uncertainty. Missing printing metadata
  blocks Master/Custom export instead of silently assuming Normal.
- Exports are read-only snapshots. They never change ownership, reconcile IDs,
  create backups, adjust prices, or change the goal. Thumbnail loading uses the
  existing artwork chain with at most four concurrent requests; missing artwork
  has an identified placeholder. Export assets are generated, not bundled.
- Generated files remain available while sharing and are cleaned up afterwards
  from their own UUID-scoped temporary directory only.

## Collection browsing

- Pokémon collections expose native All/Owned/Missing segments backed by the
  existing browsing filters. Folder defaults and species rules are unchanged.
- Collection → Wishlist lists every wishlisted card, including unowned cards.
  Entries open ordinary card details. Wishlist search supports name plus number;
  unavailable catalogue entries are reported without deleting saved metadata.
- Collection and wishlist search bars explicitly remain available in the native
  navigation drawer instead of relying on automatic placement.
- Name-and-number searches match terms across fields in sets, Pokémon
  collections, wishlist, Jumbo and Trick or Trade lists. Global catalogue search
  only treats a first term as a set code when that code actually exists. This
  fixes queries such as Lucario 64 while retaining SVE 012. Prefixed numbers,
  reversed term order, # prefixes and zero-padding are covered. SQL wildcard
  characters are escaped rather than treated as broad search patterns.

## Package

- Device archive and Release simulator build: 0.9.52 (88), development channel,
  minimum iOS 26.0. No purchase enforcement or public features are activated.
- Unsigned IPA: 30,463,994 bytes. ZIP integrity passed.
- SHA-256: `59c51e65b58935d10565b5020f741747bd807020f6d3ec9e61ab90ecf85208e2`.
- No pricing, ownership write, scanner, API-source, or account policy changes.

## Verification

Release evidence is retained in `artifacts/v0.9.52/`. All 244 unit tests passed
on iOS 27 after the final app-source changes. Export tests cover normal goals,
exact printings, broad/stale-ID ambiguity, custom exclusions, missing metadata,
PNG dimensions, multiple pages and PDF text identities. Actual app-generated PDF
pages and PNGs were rendered and visually reviewed; the two-page test PDF is
approximately 61 KB, with the original logo downsampled for export.

All 25 distinct reliability UI checks were verified across the established and
fresh iPhone 18 Pro / iOS 27 simulators, hidden. Coverage includes both export
previews and real PNG/PDF system share sheets, search-independent missing counts,
unowned wishlist cards, collection ownership segments, combined search, bulk
ownership/Undo, accessibility text sizes, restore/rollback, setup persistence,
update notes, pricing settings and the strict onscreen software-keyboard test.

The initial full fresh-simulator UI run is not claimed as an all-green suite.
Two older post-Undo checks tapped a lower card partly behind the result banner;
scrolling the tile fully into view fixed the test hit target and both reruns
passed without app ownership changes. Three setup checks still expected 0.9.51;
they were updated to 0.9.52 and all passed. Fresh local StoreKit did not supply
coffee products; the same coffee check passed on the established simulator.
Individual results and corrected reruns are retained alongside the full log.

The Release simulator app installed and launched successfully, displaying the
0.9.52 update notes without a forced purchase gate. Device Hub remained hidden.
The GitHub asset and canonical AltStore feed are verified during publication,
after the IPA has been uploaded and before reporting completion.
