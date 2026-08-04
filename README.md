# Economy and Progression — Roblox / Luau

An idle-game economy system: currencies, exponential cost curves, prestige,
offline income. The server owns all state and every remote is validated.

The core is covered by **101 unit tests** that run from the console without
Roblox Studio.

```bash
test.bat
```

Exit code `0` — green, `1` — failures, `127` — runtime not found. CI-ready.

Requires [Lune](https://github.com/lune-org/lune/releases), a standalone Luau
runtime. The script looks for it on `PATH`, or at `LUNE_PATH`.

Dependencies are managed by [Wally](https://wally.run):

```bash
wally install
```

---

## Architecture

```
src/
  shared/Economy/          pure modules -- no require, no engine
    EconomyConfig.luau       curves and balance constants
    Balance.luau             math: prices, income, prestige, offline
    Wallet.luau              OOP wallet class with validation
    Validate.luau            remote input validation
    RateLimiter.luau         token bucket against autoclickers

  server/
    Bootstrap.server.luau    Knit service registration
    Services/
      EconomyService.luau    state owner, server API

  client/
    Bootstrap.client.luau    Knit controller registration
    Controllers/
      EconomyController.luau UI, dispatches intent

tests/
  lib/TestRunner.luau        dependency-free describe/it/expect runner
  Balance.spec.luau          38 tests
  Wallet.spec.luau           25 tests
  Validate.spec.luau         27 tests
  RateLimiter.spec.luau      11 tests
  run.luau                   Lune entry point
```

### Why the modules in `shared/Economy` have no `require`

This is the central architectural decision of the project. The pure modules
pull in neither the engine nor each other -- the config arrives as an
argument. That is what lets one and the same file load in Roblox and in
**Lune**, which in turn means all of the math and all of the validation is
tested from the console in half a second, without launching Studio.

The cost: the config has to be passed as a parameter instead of imported
once. The benefit: security checks are covered by automated tests rather than
by clicking through the game.

---

## Separation of responsibility

| | Server | Client |
|---|---|---|
| State | owns it | receives a snapshot |
| Purchase price | computes it | not involved |
| Affordability check | decides | dims a button for looks |
| What crosses the wire | the result | **the intent** |

The client never sends a price or a reward -- only "buy N levels of Pickaxe".
The server works out the cost. A remote that accepts `cost` is the most common
hole in take-home tasks.

---

## What the tests actually cover

The tests were written around bugs that break production, not for coverage:

**Formula drifting from level-by-level purchases.** The total price uses the
closed-form geometric series rather than a loop. A test compares it against
summing one level at a time across 40 combinations: buying 10 levels at once
must cost exactly what buying them one by one costs.

**Off-by-one in `maxAffordableLevels`.** The inverse formula uses a logarithm,
which is wrong in the last digit on large numbers. The test checks the
property: what was bought is affordable, one more level is not.

**Reconnect farming.** Leaving and rejoining every few seconds must not grant
offline income. The `minSeconds` threshold has its own test.

**Clock drift.** A negative time difference must yield zero, not a negative
payout.

**Wallet atomicity.** When funds are short the balance does not change at all;
a failed exchange rolls the deduction back.

**Hostile client.** `nil`, tables, NaN, `math.huge`, fractional values,
negative counts, a 100,000-character string, an attempt to reach `__index` --
all rejected. Worth calling out: `math.huge % 1` yields NaN, so the fractional
check does not catch infinity and a dedicated one is required.

**Autoclickers.** The token bucket allows a short burst but throttles any
sustained rate above the allowance.

### The tests can fail

A green run proves nothing if the tests check nothing. Mutation check:
removing the `minSeconds` threshold from `Balance.offlineEarnings` makes
exactly one test fail and turns the build red (exit 1).

---

## Stack

| | |
|---|---|
| Luau | `--!strict`, typed modules |
| Rojo 7.7.0 | file sync into Studio |
| Wally 0.3.2 | dependency management |
| Knit 1.7.0 | service/controller |
| Lune 0.10.5 | console test runs |

## Running in Studio

```bash
rojo serve
```

Then in Studio: the `PLUGINS` tab → `Rojo` → `Connect` → `Play`.

---

## What is deliberately missing

**Persistence.** `EconomyService:KnitStart` builds state from scratch; the
places for profile load and save are marked in code. ProfileStore, key
migration and backups are a separate system of comparable size.

**Monetisation.** `Balance.offlineEarnings` already takes a gamepass flag and
applies it to both the cap and the rate, but `MarketplaceService`,
`ProcessReceipt` and purchase idempotency are not implemented.

**Server-layer tests.** The pure modules are covered. `EconomyService` and
`EconomyController` need the engine -- that calls for TestEZ inside Studio.

---

## Note on language

Source, comments and documentation are in English on purpose. Beyond the
usual reasons, `cmd.exe` reads `.bat` files in the OEM codepage, so non-ASCII
text in a batch file gets mangled and can break parsing outright -- which is
exactly what happened to an earlier version of `test.bat`.
