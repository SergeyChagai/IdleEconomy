# Architecture

IdleEconomy is a Roblox idle game economy: pure math under test in Lune,
engine-bound services on Knit, persistence via ProfileStore, monetisation
via MarketplaceService.

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│ Client — EconomyController                                   │
│   HUD, intent only (buy N, mine, prestige, shop prompts)     │
└────────────────────────────┬────────────────────────────────┘
                             │ Knit remotes / signals
┌────────────────────────────▼────────────────────────────────┐
│ Server — EconomyService                                      │
│   Sole owner of runtime economy state                        │
│ MonetisationService — ProcessReceipt, gamepass refresh       │
│ DataService — ProfileStore session, ordered release hooks    │
└────────────────────────────┬────────────────────────────────┘
                             │ mutates profile table
┌────────────────────────────▼────────────────────────────────┐
│ Profile (v4) — schema + migrations (pure, Lune-tested)       │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│ shared/Economy — Balance, Wallet, Validate, RateLimiter,     │
│   PurchaseLedger, PurchaseAnalytics, *Config (no require)    │
└─────────────────────────────────────────────────────────────┘
```

## Services

| Service | Owns | Does not |
|---|---|---|
| **DataService** | ProfileStore session, load/migrate, `OnBeforeRelease` | Economy math, remotes |
| **EconomyService** | Coins, levels, prestige, income tick, offline credit | Direct DataStore, ProcessReceipt |
| **MonetisationService** | Receipts, gamepass ownership → entitlements | Wallet math (calls `GrantCoins`) |
| **EconomyController** | HUD + dispatching intent | Prices, affordability (server decides) |

Ordering on leave: `DataService:Release` runs registered `OnBeforeRelease`
callbacks (EconomyService flushes wallet → profile, stamps `lastSeen`) before
ending the session. Do not hang critical flushes on raw `PlayerRemoving`.

## Data

Profile version **4**: coins, levels, prestige, lifetimeEarned, lastSeen,
`processedPurchases`, `ownedPasses`. Migrations are in `Profile.luau` and
tested in Lune. A save from a **newer** build is refused without writing.

## Monetisation

See `docs/monetisation.md` and ADR-0006. PurchaseIds are recorded before
`PurchaseGranted`. Gamepass ids of `0` are ignored.

## Tests

| Suite | How | Covers |
|---|---|---|
| Console | `test.bat` (Lune) | Pure modules + Profile |
| Studio | `rojo serve test.project.json` → Play | EconomyService, EconomyController |
| Both | `test-all.bat` | Console + instructions for Studio |

Production sync uses `default.project.json` (no TestEZ runners).

## ADRs

| ADR | Decision |
|---|---|
| 0001 | Pure economy modules, no `require` |
| 0002 | Client sends intent, not price |
| 0003 | Closed-form cost with correction |
| 0004 | Hand-written Lune runner; TestEZ only for Studio |
| 0005 | Mutation check proves tests can fail |
| 0006 | Idempotent ProcessReceipt + PurchaseId ledger |
