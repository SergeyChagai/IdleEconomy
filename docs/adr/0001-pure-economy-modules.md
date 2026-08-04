# ADR-0001: Economy modules have no `require`

## Status

Accepted (2026-08-04)

## Context

The parts that matter most here -- remote validation, exponential curves,
offline income -- are exactly where a mistake costs money: either a player
farms an exploit, or the economy breaks on large numbers. Verifying that by
clicking around in Studio is slow and unreliable.

Roblox code is usually tied to the engine from the first line: `game:GetService`,
`script.Parent`, `Instance.new`. Such a module cannot be loaded anywhere but
Studio, which means unit tests require launching the editor.

There is a second obstacle: the two module systems are incompatible. In Roblox
it is `require(script.Parent.Balance)`, in Lune it is `require("./Balance")`.
One file cannot use both.

## Decision

The modules in `src/shared/Economy/` (`Balance`, `Wallet`, `Validate`,
`RateLimiter`, `EconomyConfig`) are written without a single `require` and
without touching the engine. Configuration arrives as a function argument
rather than an import.

The Roblox-aware layer (`EconomyService`, `EconomyController`) requires those
modules the usual way and stays thin.

## Consequences

Positive:

* All of the math and all of the validation runs in Lune from the console in
  half a second without Studio -- 101 tests, with a CI-friendly exit code.
* Security checks are covered by automated tests rather than manual passes.
* Pure functions are trivial to test at the boundaries: NaN, infinity,
  negative values, caps.

Negative:

* The config must be passed as a parameter on every call instead of being
  imported once. Signatures get longer.
* Types are duplicated across files instead of being imported from a shared
  module, because `export type` also requires `require`.

The trade is deliberate: verbose signatures in exchange for the ability to
test security automatically.
