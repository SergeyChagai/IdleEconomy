# ADR-0004: A hand-written test runner instead of an off-the-shelf one

## Status

Accepted (2026-08-04)

## Context

Tests have to run in Lune from the console, without Roblox Studio (see
ADR-0001). The existing Luau frameworks -- TestEZ and jest-lua -- are built to
execute inside Roblox: they walk an instance hierarchy, look up `ModuleScript`
objects in the tree, and need the engine.

Adapting them to Lune is possible, but it means either another dependency plus
a compatibility shim, or a fork.

## Decision

A dedicated runner lives in `tests/lib/TestRunner.luau` -- roughly forty lines
of logic: `describe`, `it`, `expect` with a set of matchers (`toBe`,
`toEqual`, `toBeCloseTo`, `toBeGreaterThan`, `toBeLessThan`, `toBeTruthy`,
`toBeFalsy`, `toBeNil`, `toThrow`).

The runner has no dependencies and knows about neither Roblox nor Lune --
except for the entry point `tests/run.luau`, which uses `@lune/process` for
the exit code.

## Consequences

Positive:

* Zero dependencies: nothing to break on an upgrade and nothing to install
  when cloning the project.
* A 0/1 exit code is CI-ready without any wrapper.
* Full control over output format and error messages.

Negative:

* None of the conveniences of a mature framework: `beforeEach`/`afterEach`,
  mocks, name filtering, parallel execution, coverage measurement.
* The runner itself is not covered by tests. If it broke in a way that
  counted failures as successes, nothing would catch it automatically. The
  partial safeguard is the mutation check (ADR-0005).
* As the suite grows the limitations will start to show, and the runner will
  have to be either extended or replaced with TestEZ.

Update (Sprint 5): TestEZ was added for the **engine-bound** layer only
(`tests/studio/`, `test.project.json`). The console suite for pure modules
still uses this runner -- the two stacks are intentional, not a migration.
