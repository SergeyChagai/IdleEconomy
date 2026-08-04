# ADR-0006: Idempotent ProcessReceipt with a PurchaseId ledger

## Status

Accepted (2026-08-04)

## Context

Roblox may deliver the same developer-product receipt more than once: network
retry, server restart between grant and acknowledgement, or a player hopping
servers mid-purchase. Crediting coins on every delivery doubles (or worse)
what the player paid for.

Gamepasses are different — ownership is queried with
`UserOwnsGamePassAsync` — but product grants are one-shot and must survive
exactly those retries.

The grant also has to land in the same ProfileStore session that autosaves
the player. A side DataStore just for PurchaseIds would race the profile and
split the source of truth.

## Decision

1. Keep a bounded list of processed PurchaseIds on the profile
   (`processedPurchases`, Profile v4).
2. Pure helper `PurchaseLedger` (no engine) records / detects duplicates and
   is unit-tested in Lune — including replay-after-reload.
3. `MonetisationService` owns `MarketplaceService.ProcessReceipt`:
   - duplicate id → `PurchaseGranted`, no grant;
   - profile not ready → `NotProcessedYet`;
   - stamp id, then `EconomyService:GrantCoins`; on grant failure, roll the
     stamp back and return `NotProcessedYet`.
4. Catalog ids live in `MonetisationConfig`. `0` means unconfigured and never
   matches a live product.

## Consequences

Positive:

* Retries cannot double-pay.
* Ledger logic is tested without Studio.
* One save document holds economy + purchase history.

Negative:

* History is capped (`purchaseHistoryLimit`); an ancient PurchaseId could in
  theory fall off and be replayed. The window is sized for Roblox retry
  lifetimes, not infinite retention.
* Rolling back the stamp on grant failure re-opens a narrow race if two
  receipts for the same id were processed concurrently on one server — rare
  in practice for a single player session.
