# ADR-0005: A mutation check as proof that the tests work

## Status

Accepted (2026-08-04)

## Context

The brief asks for "working code plus evidence that it works". A green test
run is not that evidence: a suite that checks nothing is also green.
Assertions like `expect(result).toBeTruthy()` against a function that always
returns a table pass unconditionally.

The problem is sharper here because the runner is hand-written (ADR-0004) and
is not itself covered by tests. A runner bug that counted failures as
successes would be indistinguishable from healthy code.

## Decision

The suite's ability to detect regressions is confirmed by a mutation check: a
meaningful bug is introduced into working code, the run must turn red, and the
bug is then removed.

The check performed: the `minSeconds` threshold -- the reconnect-farming guard
-- was removed from `Balance.offlineEarnings`. Result: exactly one test
failed and the exit code became 1. With the threshold restored: 101 tests,
exit code 0.

The mutation is chosen to strike a specific guard rather than at random: it
verifies both that a test exists and that it checks the right property.

## Consequences

Positive:

* There is reproducible evidence that the tests are able to fail.
* It also confirms the runner returns a non-zero exit code correctly and that
  one failing test is not masked by the rest.
* "Exactly one test failed" demonstrates precision of coverage: the guard is
  checked by one test rather than smeared across many.

Negative:

* The check is manual and one-off. It does not repeat automatically and goes
  stale as the code grows.
* Full mutation testing (Stryker and similar) is not available for Luau, so
  there is nothing to automate this with right now.
* It requires discipline: every new guard needs the check repeated by hand,
  otherwise the practice loses its meaning.
