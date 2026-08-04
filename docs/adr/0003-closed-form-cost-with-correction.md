# ADR-0003: Closed-form cost with mandatory correction

## Status

Accepted (2026-08-04)

## Context

Level price grows geometrically: `baseCost * costGrowth ^ level`. That gives
two problems:

1. What N consecutive levels cost.
2. How many levels the player can buy with the money they have
   (the "buy max" button).

The naive solution is a loop. On "buy max" N reaches the hundreds, and the
loop runs on every click of every player.

Closed forms exist: the geometric series sum and its inverse through a
logarithm. But the inverse has a well-known flaw -- on large numbers the
logarithm is wrong in the last digit. Off by one here means either a level
the player paid for and did not get, or a balance driven negative.

A separate trap: rounding the price of an individual level "to look nice"
makes the series sum stop matching the sum of individual purchases. A player
who buys 10 levels at once pays a different amount than one who buys them one
at a time, and that is found on day one.

## Decision

Total cost uses the closed form `S = a * (g^n - 1) / (g - 1)`, with the
degenerate `g = 1` case handled separately.

The affordable level count is computed through a logarithm, after which the
result is ALWAYS corrected in both directions: step down while the purchase
is unaffordable, step up while the next level is affordable. The correction
costs one or two steps and removes the entire class of rounding bugs.

Prices are not rounded inside the module. Rounding happens only on display.

## Consequences

Positive:

* "Buy max" runs in constant time regardless of the level count.
* The invariant "what was bought is affordable, one more level is not" is
  checked against seven balances and four starting levels.
* Agreement between the closed form and level-by-level summation is checked
  across 40 combinations with a relative tolerance of 1e-9.

Negative:

* The code is noticeably more complex than a loop and needs comments;
  otherwise the correction looks like redundant insurance and gets
  "optimised" away.
* The formula does not work at `costGrowth = 1`; the degenerate branch is
  always required and is easy to forget when copying the code.
