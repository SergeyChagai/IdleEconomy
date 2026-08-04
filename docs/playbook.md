# Playbook — review IdleEconomy in ~10 minutes

Short guide for hiring managers and reviewers. Details live in linked docs;
this page is the map.

---

## 1. One-line pitch

Server-owned Roblox idle economy with Lune unit tests, ProfileStore saves,
idempotent Robux receipts, and ADRs tracked in a custom CEM graph (Meronq).

---

## 2. Checklist — is the full stack real?

| Claim | Proof (open this) |
|---|---|
| Luau strict | any file under `src/` starts with `--!strict` |
| Rojo | `default.project.json`, `test.project.json` |
| Wally | `wally.toml` — Knit, TestEZ, ProfileStore |
| Knit services | `src/server/Bootstrap.server.luau`, `src/client/Bootstrap.client.luau` |
| ProfileStore | `src/server/Services/DataService.luau` |
| Marketplace / receipts | `src/server/Services/MonetisationService.luau` |
| Lune console tests | `test.bat` → **153** passed |
| TestEZ Studio | `tests/studio/` + `rojo serve test.project.json` |
| GitHub Actions | `.github/workflows/tests.yml` (green on PRs) |
| CEM / Meronq | ADRs in `docs/adr/` + graph below |

If a row has no file, the claim is incomplete. Today every row has one.

---

## 3. Meronq CEM

**CEM** = Causal Engineering Memory: decisions (ADRs) linked to evidence
(commits / modules), browsable in Meronq Desktop.

![Meronq Desktop — IdleEconomy CEM graph](assets/meronq-cem-graph.png)

What to notice on the screenshot:

- ADR nodes (e.g. mutation check, ProcessReceipt idempotency, pure modules)
- Commit hashes as evidence edges
- Project / Roblox containers holding those decisions
- Heat field = recent activity (ship polish / monetisation work)

This is **own tooling**, not a Roblox product. It sits beside the game code to
keep “why we chose X” queryable after the take-home is submitted.

---

## 4. Suggested reading order

| Min | Open | Ask yourself |
|---|---|---|
| 0–2 | This playbook + README stack table | Is every tool actually used? |
| 2–4 | [ADR-0002](adr/0002-client-sends-intent-not-cost.md) | Would I reject a remote that accepts `cost`? |
| 4–6 | [ADR-0001](adr/0001-pure-economy-modules.md) | Can economy math run outside Studio? |
| 6–8 | [ADR-0006](adr/0006-idempotent-process-receipt.md) | What happens if Roblox retries a receipt? |
| 8–10 | [architecture.md](architecture.md) | Who owns state vs HUD vs DataStore? |

Optional deep dive: [ADR-0005](adr/0005-mutation-check-as-proof.md) (proof that tests can fail).

---

## 5. How to run (reviewer machine)

```bash
# Dependencies (stop any rojo serve first)
wally install

# Console suite — no Studio
test.bat
# Expect: Total: 153 passed, 0 failed

# Gameplay
rojo serve
# Studio → Plugins → Rojo → Connect → Play
```

Engine-bound suite (optional):

```bash
rojo serve test.project.json
# Play → Output: [StudioTests] server/client suite passed
```

---

## 6. What “done” means for this vacancy package

| Item | Status |
|---|---|
| Sprints 1–5 (core → persistence → monetisation → Studio tests) | Closed — [roadmap](roadmap.md) |
| Ship polish (docs, HUD, CI) | Merged to `main` |
| Console CI | Green on GitHub Actions |
| Catalog ids in git | Intentionally `0` until Creator Dashboard paste |
| Live place publish | Out of scope for repo review |

---

## 7. Copy-paste blurb for an application

> IdleEconomy is a Roblox/Luau economy system: Knit services, ProfileStore
> persistence, Marketplace ProcessReceipt with an idempotent PurchaseId ledger,
> and 153 Lune unit tests (+ Studio TestEZ) on GitHub Actions. Architecture
> decisions are ADRs, indexed in Meronq CEM (own tooling). Repo:
> https://github.com/SergeyChagai/IdleEconomy — start at docs/playbook.md.
