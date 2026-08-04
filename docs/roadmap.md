# Roadmap

Project: an economy and progression system for Roblox (Luau + Rojo + Knit).
Closed sprints record what was actually done, not what was planned.

## Sprint 1 — Economy core

Goal: pure economy math covered by tests that run without Studio

- [x] Balance: exponential prices, income, prestige, offline earnings
- [x] Closed-form series with correction against rounding error
- [x] Wallet: OOP class with validation and atomic operations
- [x] Modules with no require -- load in both Roblox and Lune
- [x] describe/it/expect runner with no external dependencies
- [x] Console run with a CI-friendly exit code

Sprint 1 status: closed

## Sprint 2 — Server layer and remote hardening

Goal: the server owns state, all client input is validated

- [x] Validate: types, ranges, integrality, identifier length
- [x] EconomyService on Knit -- the single owner of state
- [x] The client sends intent, the server computes the cost
- [x] EconomyController: interface and intent dispatch
- [x] Manual click mining as the starting income source
- [x] RateLimiter: token bucket against autoclickers
- [x] Mutation check: confirmed the tests are able to fail

Sprint 2 status: closed

## Sprint 3 — Persistence

Goal: player progress survives a server restart and offline income is credited

- [x] Profile schema with a version number
- [x] Key migration between schema versions
- [x] Migration tests: old versions, corrupt data, missing keys
- [x] Refuse to downgrade a save written by a newer build
- [x] ProfileStore as a Wally server-dependency (lm-loleris/profilestore)
- [x] Load and save through ProfileStore
- [x] Autosave, plus an ordered flush before the session is released
- [x] Credit offline income on join via Balance.offlineEarnings
- [x] Offline window guard: a consumed window is never paid twice
- [x] Tests: a repeated load does not double the offline payout

Sprint 3 status: closed

Not covered by tests: DataService and the persistence wiring inside
EconomyService need the engine. They are Sprint 5 material (TestEZ in Studio).

## Sprint 4 — Monetisation

Goal: Robux purchases are credited exactly once

- [x] Idempotent ProcessReceipt with PurchaseId history
- [x] Gamepasses: income multiplier and extended offline cap
- [x] Dev products: currency bundles
- [x] Purchase analytics
- [x] Idempotency tests: replay, race, restart between attempts

Sprint 4 status: closed

Catalog ids in `MonetisationConfig` are placeholders (`0`). Replace them with
Creator Dashboard ids before publishing. A zero id is ignored at runtime.

## Sprint 5 — Server-layer tests

Goal: close the last blind spot in coverage

- [x] TestEZ inside Studio
- [x] EconomyService tests against real instances
- [x] EconomyController tests
- [x] Run both suites with a single command

Sprint 5 status: closed

Console suite: `test.bat` (Lune). Studio suite: `rojo serve test.project.json`
then Play. Both: `test-all.bat`.
