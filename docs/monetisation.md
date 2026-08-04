# Monetisation setup

Catalog lives in `src/shared/Economy/MonetisationConfig.luau`. Every
`id` / `productId` of `0` means **not configured** — the service ignores it
and never grants from a zero id.

Roblox does not let this repo mint live catalog ids. You create them once in
Creator Dashboard, paste the numbers into the config, then verify on a
**test place**.

## 1. Create the catalog

In [Creator Dashboard](https://create.roblox.com/) → your experience →
**Monetization**:

| Config key | Type | Suggested name | Effect in game |
|---|---|---|---|
| `Vip` | Game Pass | VIP | ×2 income, full-rate offline window |
| `CoinsSmall` | Developer Product | Coins Small | +5 000 coins |
| `CoinsMedium` | Developer Product | Coins Medium | +30 000 coins |
| `CoinsLarge` | Developer Product | Coins Large | +150 000 coins |

Copy each numeric id into `MonetisationConfig.luau` (replace the `0`s).

After editing, Rojo will sync; **Stop → Play** so Knit reloads the module.

## 2. Test place checklist

Use a dedicated test place (not the live title):

1. Publish the place (`File → Publish to Roblox As…`).
2. `Game Settings → Security → Enable Studio Access to API Services`.
3. Confirm Output on Play:
   - `[DataService] Studio detected: using the mock DataStore` — mock is fine
     for ProcessReceipt wiring checks; for **real** DataStore persistence of
     PurchaseIds, flip to a real-store test place (see DataService comments).
   - No `[Monetisation] catalog incomplete` warning (ids are filled).
4. In the HUD **Shop** panel:
   - Buy VIP → income multiplier / offline boost apply after refresh/rejoin.
   - Buy a coin pack once → coins rise; buy again (or force a receipt retry)
     → coins do **not** double for the same PurchaseId.
5. Output should show `[Monetisation] receipt_granted …` then
   `receipt_duplicate` on a replay.

## 3. Safety

- Never commit live production place secrets; ids themselves are public.
- Keep `STUDIO_USES_REAL_DATASTORE` (if present) **false** on the live place.
- Zero ids in git are intentional until you paste real ones — CI and clones
  stay safe.
