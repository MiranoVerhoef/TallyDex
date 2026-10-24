# Bulk ownership editor — 0.9.50 (86)

## Scope and interaction

- Sets, Search list/grid, and Pokémon collection grids share one editor.
- A half-second hold selects the first card; subsequent taps toggle selection
  instead of navigating or toggling individual ownership. VoiceOver exposes a
  “Select multiple cards” action. Ordinary taps outside selection still navigate.
- Selection options include all currently filtered results and deselect all.
  Changing a filter removes hidden cards from the selection. Cancel changes no ownership.
- Set opens a printing sheet. It loads metadata for every selected card before
  allowing a write; cancelling or a metadata failure cannot partially update ownership.
- Printing rows show eligible cards. Multiple finish types can be selected.
  “All available printings” explicitly includes special/stamped printings.
- Mark owned preserves existing quantities, adding one only where missing.
  Mark missing requires confirmation and removes only chosen available printings.

## Data safety

`BulkOwnershipPlanner` uses actual identified printings when present, not pricing
labels or stale variant flags. Legacy cards without printing IDs use their
available variant kinds. Ambiguous exact printings are skipped unless “All
available printings” is explicitly chosen. Existing broad ownership is not silently
duplicated as exact ownership. Duplicate card IDs are processed once.
Unresolved saved IDs or obsolete standard finishes cannot create additional copies;
they are left unchanged for the existing individual-card reconciliation workflow.

`GRDBCollectionRepository.applyBulkOwnership` reads current ownership, creates a
safety backup and applies all quantity changes in one database transaction.
Failures roll back every quantity and the backup insertion. It never writes
catalogue metadata, goals, notes, prices, folders or binder plans.

Undo restores only affected identities, preserving unrelated later edits. It
checks every affected record's quantity, variant and stored update timestamp
before writing; conflicts reject the complete Undo. An additional backup is saved
before Undo. No full-backup replacement is used for the inline Undo action.

Bulk edits use the existing lifetime/trial editing gate. Catalogue refresh,
printing reconciliation, pricing and purchase implementation are unchanged.

## Regression coverage

- Actual printings override stale Normal/Holo flags.
- Unavailable types are skipped; broad and exact quantities are preserved.
- Ambiguous printings require explicit All; duplicate selections do not double-write.
- Targeted Undo preserves unrelated edits and refuses conflicts, including a later
  write with the same quantity but a different timestamp.
- Mark missing and Undo restore both broad and exact quantities.
- An injected SQL failure on a later card rolls back earlier changes and the backup.
- UI exercises selection, select-all, ownership and Undo in all three entry points,
  both Search layouts, filtered-set selection, destructive confirmation, cancellation
  and normal navigation after leaving selection mode.

The user requested hidden iOS 27 verification and an AltStore release. TestFlight
and App Store publishing are not part of this release.

The final 237-test unit run passed on the established iPhone 18 Pro simulator.
The earlier fresh-simulator run returned no local StoreKit products and failed
purchase-fixture checks; it is not counted as a passing run. Purchase source and
configuration were not changed. UI tests run separately on a new, temporary
iPhone 18 Pro (iOS 27.0), including the software-keyboard visibility regression.
After the upstream-ID safety guard, all four bulk UI checks are repeated against
the final app alongside the broader regression run. Final release evidence is in
`artifacts/v0.9.50/`; the earlier unguarded package is retained only as a preflight
artifact in `artifacts/bulk-ownership/` and must not be uploaded.

## Release verification

- 237 unit tests passed, including ten new bulk-ownership safety regressions.
- All 20 reliability UI checks passed; the opt-in marketing capture was skipped.
- All four bulk UI checks passed again after the upstream-ID guard. The final
  selection-marker polish was then checked with another collection edit/Undo
  cycle and all 237 unit tests. Its screenshots are in `final-preview/`.
- The final device archive reports 0.9.50 (86), development channel, minimum iOS
  26.0. The unsigned IPA passes ZIP integrity validation and is 30,329,114 bytes.
- Final IPA SHA-256:
  `0656f71c055c67ed288f99574ac85208d2d35f710ceab128d3d64d4506b1eb9a`.
- Only the top-level `artifacts/v0.9.50/TallyDex-v0.9.50.ipa` is the release asset.
  Earlier preflight packages/archives are retained separately for diagnostics.
