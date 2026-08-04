# ADR-0002: The client sends intent, not a price

## Status

Accepted (2026-08-04)

## Context

A Roblox client is hostile by default: an exploiter calls remotes directly
with arbitrary arguments, bypassing the interface entirely. Anything the
client sends is data of unknown origin, not the result of pressing a button.

A common mistake in take-home tasks is a remote shaped like
`BuyUpgrade(upgradeId, cost)` or `AddCoins(amount)`. It is convenient: the
price was already computed for display, so why compute it twice. But such a
remote means the attacker sets the purchase price.

## Decision

Remotes accept INTENT only: `BuyUpgrade(upgradeId, count)`. Price, reward and
outcome are computed exclusively by the server from its own config.

Every argument goes through `Validate` before use: type, range, integrality,
key existence. The existence check runs strictly after the type check --
indexing a table with an arbitrary client-supplied value is not acceptable.

The local affordability check on the client stays, but only to highlight a
button. Nothing depends on it; the server re-checks.

## Consequences

Positive:

* Forging a price is impossible: the client takes no part in computing it.
* Validation lives in a pure module and is covered by 27 tests written from
  the attacker's seat.
* The `MAX_BATCH` cap protects the server rather than the balance: a call with
  `count = 1e9` would hang every player on the server, not just one.

Negative:

* The price is computed twice -- on the client for the UI and on the server
  for the deduction. Formula duplication is avoided because both use the same
  `Balance` module, but there are still two calls.
* Every action costs a round trip to the server; there is no instant
  feedback. Acceptable for an idle game; a shooter would need prediction.
