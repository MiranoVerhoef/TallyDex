# Automatic price updates

## Scope

The on-device queue checks owned cards first, followed by cards in sets explicitly marked **My Sets / Collecting**. Targets come from the cached catalogue/search index, plus canonical card IDs for supplemental Jumbo and Trick or Trade sets. Normal catalogue loading supplies/updates that index; background price tasks do not download the whole catalogue. Duplicate cards across watched sets are checked once.

Foreground catch-up is enabled by default after setup. Background updates are a separate, explicit opt-in in setup or **Settings → Prices & Currency → Automatic Updates**. There is no notification, location, or generic background-permission prompt. System Background App Refresh remains under iOS control.

## Scheduling and limits

- SwiftUI registers the `com.miranoverhoef.TallyDex.prices.refresh` BGAppRefresh handler; Info.plist declares `fetch` and the permitted task identifier.
- On entering the background, or changing the update preferences, one request is scheduled no earlier than six hours later. The handler schedules its successor.
- Foreground batches run on activation, with two-minute pauses between batches while active. A batch has at most 120 serial card requests and a 90-second launch budget; a background batch has at most 60 requests and a 22-second launch budget. iOS expiration cancels the handler and in-flight networking. Requests already in flight may run until cancellation/network timeout; these budgets are not guaranteed completion deadlines.
- A shared coordinator prevents overlapping automatic batches. Oldest attempts within each priority tier run first so later cards can make progress across batches and app launches.
- A successful check suppresses further automatic requests for that card on the same UTC day. Failed requests back off for six hours. Three failures end a batch early and pause automatic batches for 15 minutes. Cards without supplied prices are checked, but no zero/placeholder history is invented.
- Disabling automatic updates also stops eligibility for background updates. Disabling background updates cancels the pending OS request; foreground catch-up can remain on.
- iOS chooses actual execution based on usage, battery, and system settings. Low Power Mode, force-quitting, or disabling system Background App Refresh can prevent it. Simulator tests cannot prove real-device scheduling cadence.

## Data safety

The updater uses the existing configured TCGdex provider (development API with official fallback, or official only). Card IDs are requested directly; collection documents, notes, and photos are not uploaded. There is no TallyDex Assets or scanner-feedback integration.

Automatic writes are a separate price-only repository transaction. They never replace catalogue sets, cards, variants, printings, or ownership. Since the legacy variant reader also unions current-price kinds, automatic current-price writes are restricted to already-cached kinds. Newly observed kinds can be recorded in history but do not create a printing or remap an owned card. Normal explicit detail hydration remains responsible for authoritative printing reconciliation.

History stores one observation per card/printing/market/UTC day of a successful fetch, with the provider's update timestamp retained independently. Rechecking an unchanged provider timestamp on another day therefore adds an observation. Missing days are not backfilled; existing history remains intact and may use the older provider-day convention. EUR and USD are separate. Older source responses cannot overwrite newer current quotes or newer same-day history. Invalid quotes reject the transaction.

Indexed cards without downloaded details can gain history without inserting incomplete card/set caches. Retention and existing history-size limits are applied after batches. Clearing all market data also clears automatic attempt/success markers, making cards eligible again.

## Verification

Unit coverage includes priorities, batching, continuation, daily checks, retry backoff, index/supplemental target selection, independent markets, sparse real observations, unchanged upstream timestamps, metadata/variant safety, stale-response protection, invalid-quote atomicity, opt-out, cancellation, and background-task configuration. UI coverage includes setup explanation, opt-in, persistent Settings controls, and unchanged collection quantities/backups.
