# Economy and Progression — Roblox / Luau

An idle-game economy system: currencies, exponential cost curves, prestige,
offline income. The server owns all state and every remote is validated.

The core is covered by console unit tests that run without Roblox Studio.
GitHub Actions runs the same suite on every push and pull request
(`.github/workflows/tests.yml`).

```bash
test.bat
```

Exit code `0` — green, `1` — failures, `127` — runtime not found.

Requires [Lune](https://github.com/lune-org/lune/releases), a standalone Luau
runtime. The script looks for it on `PATH`, or at `LUNE_PATH`.

Studio-bound services (`EconomyService`, `EconomyController`) are covered by
TestEZ under `tests/studio/`. Serve the test project and Play:

```bash
rojo serve test.project.json
```

`test-all.bat` runs the console suite and prints the Studio steps.

Dependencies are managed by [Wally](https://wally.run):

```bash
wally install
```

> **Stop `rojo serve` before running `wally install`.** Wally rewrites the
> whole `Packages/` tree at once, and Rojo's incremental file watcher does not
> survive it: in practice it has both silently half-synced the tree and
> crashed outright on a path that vanished mid-watch. Restart `rojo serve`
> afterwards.

---

## Docs

| | |
|---|---|
| [Architecture](docs/architecture.md) | Layers, services, data model, ADRs |
| [Monetisation setup](docs/monetisation.md) | Creator Dashboard ids + test-place checklist |
| [Roadmap](docs/roadmap.md) | Sprint status |
| [ADRs](docs/adr/) | Decisions (pure modules, ProcessReceipt, …) |

## Architecture

See [docs/architecture.md](docs/architecture.md) for the current service map.
Short tree:

```
src/
  shared/Economy/          pure modules -- no require, no engine
  server/Services/         Economy, Data, Monetisation (Knit)
  client/Controllers/      EconomyController HUD (intent only)

tests/
  *.spec.luau              Lune console suite (test.bat / CI)
  studio/                  TestEZ under test.project.json
```

### Why the modules in `shared/Economy` have no `require`

This is the central architectural decision of the project (ADR-0001). The pure
modules pull in neither the engine nor each other -- the config arrives as an
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

## What is deliberately unfinished

**Live catalog ids.** `MonetisationConfig` ships with zeros. Paste Creator
Dashboard ids and verify on a test place — see
[docs/monetisation.md](docs/monetisation.md).

**Studio TestEZ in CI.** Console suite is on GitHub Actions. Engine-bound
specs still need `rojo serve test.project.json` + Play locally
(`test-all.bat`).

---

## Note on language

Source, comments and documentation are in English on purpose. Beyond the
usual reasons, `cmd.exe` reads `.bat` files in the OEM codepage, so non-ASCII
text in a batch file gets mangled and can break parsing outright -- which is
exactly what happened to an earlier version of `test.bat`.
