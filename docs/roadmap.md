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

- [ ] Profile schema with a version number
- [ ] Key migration between schema versions
- [ ] Load and save through ProfileStore
- [ ] Autosave on a timer and on player exit
- [ ] Credit offline income on join via Balance.offlineEarnings
- [ ] Migration tests: old versions, corrupt data, missing keys
- [ ] Tests: a repeated load does not double the offline payout

Sprint 3 status: in progress

## Sprint 4 — Monetisation

Goal: Robux purchases are credited exactly once

- [ ] Idempotent ProcessReceipt with PurchaseId history
- [ ] Gamepasses: income multiplier and extended offline cap
- [ ] Dev products: currency bundles
- [ ] Purchase analytics
- [ ] Idempotency tests: replay, race, restart between attempts

Sprint 4 status: planned

## Sprint 5 — Server-layer tests

Goal: close the last blind spot in coverage

- [ ] TestEZ inside Studio
- [ ] EconomyService tests against real instances
- [ ] EconomyController tests
- [ ] Run both suites with a single command

Sprint 5 status: planned
