# Card detail swiping — 0.9.54 (90)

Development/AltStore follow-up to 0.9.53. No TestFlight or App Store upload.

- Swipe left for the next card and right for the previous card. The sequence is
  a snapshot of the visible originating list, including its search, filters and
  sort. It does not wrap at either end or invent neighbours for standalone links.
- Set grids, Search list/grid, Pokémon collections, Wishlist, owned-card lists,
  top-priced cards, Trick or Trade, Jumbo and binder plans supply their ordering.
  Binder browsing spans its pages; repeated pockets for one card are deduplicated.
- Paging replaces the card inside the same navigation destination, so Back still
  returns to the original list. Each page has its own quantities, metadata,
  notes, image/share state and scroll position. Only opened cards load details;
  the feature does not download all neighbouring cards in advance.
- Horizontal swipes require at least 60 points and a 1.75-to-1 horizontal/vertical
  ratio. The first 28 points at the left edge remain reserved for system Back.
  A native directional pan cancels underlying link/button taps when a horizontal
  drag starts; vertical scrolling and pull-to-refresh retain their behaviour.
  The public navigation-controller content-pop recognizer waits for the card
  gesture. Its separate edge-pop recognizer is unchanged, including at list bounds.
- Paging is disabled while editing notes or saving quantities/metadata. Unsaved
  notes prompt Save and Continue, Discard Changes or Cancel. A failed save stays
  on the original card. Refresh and note prompts share one confirmation presenter.
  iOS 27 may render these as a popover: tapping outside is its native Cancel action.
- Transitions use a brief directional push, or a fade for Reduce Motion.
  VoiceOver offers the available Previous card / Next card actions without
  adding visible buttons or help text.
- Ownership, goal, pricing-source, catalogue and scanner rules are unchanged.

## Verification

Evidence is retained in `artifacts/card-detail-swiping/`. On the final source,
all 251 unit tests passed (`back-priority-unit.xcresult`) and all five paging UI
checks passed (`back-priority-ui.xcresult`), hidden on iPhone 18 Pro / iOS 27.
These cover set ordering, both directions, first/last bounds, one-level Back,
vertical scrolling, pull-to-refresh, native edge Back, filtered Search, single-card
Wishlist and collection sorting. Notes checks cover Cancel, Save and Continue,
Discard Changes, persistence after returning and no leakage to a neighbouring card.
Existing quantities and backup counts remain unchanged.

Earlier regression checks also passed for bulk ownership/Undo, collection
ownership segments/combined search and unowned Wishlist entries. Intermediate UI
runs are retained, not presented as all-green: initial tests needed offscreen set
scrolling, actual Search sort order and iOS 27 popover dismissal without a visible
Cancel row. The final runs additionally verify the fixed content-Back conflict.

The pre-release Release simulator build succeeded, installed and launched without
opening the Simulator window. The paging/scroll screenshot and Release launch
were visually checked. That build was 0.9.53 (89), development channel;
no IPA, commit, GitHub release, AltStore feed or TestFlight upload was made during
that feature implementation. Release-specific verification follows below.

## Release package

Version 0.9.54 (90), development channel, minimum iOS 26.0. The unsigned device
archive succeeded and IPA ZIP integrity passed. Size: 30,494,224 bytes.
SHA-256: `b2d1e83820032fac975d0801d61fe1d5cce71da8b3bd274663106c5af5b0d1e0`.

Release evidence is retained in `artifacts/v0.9.54/`. All 251 unit tests and all
11 targeted UI tests passed on iPhone 18 Pro / iOS 27, hidden. This repeats the
five paging checks and additionally verifies bulk ownership/Undo, collection
segments/combined search, unowned Wishlist entries, completing/skipping setup,
and update notes appearing exactly once for 0.9.54.

The Release simulator build succeeded and matches the device archive's version,
build, channel and minimum OS. It installed and launched successfully, showing
the correct short 0.9.54 update notes without a purchase gate. Release launch
and the paged card screenshot were visually checked. Reliability fixture markers
are absent from the Release binary. Simulator windows remained closed.

The uploaded GitHub asset size/digest and canonical AltStore feed are verified
during publication, after uploading the IPA and before reporting completion.
