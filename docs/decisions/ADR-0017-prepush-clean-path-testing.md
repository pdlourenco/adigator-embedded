# ADR-0017 — Pre-push clean-path testing: hook + shared test base class + path-hygiene guard

## Status

Accepted — 2026-06-29

## Context

PR #81 went red on CI **twice**, both caught by the reviewer rather than locally,
both with the same root cause: a new `tests/unit` class was missing its
`TestClassSetup`/`PathFixture` for `embedding/`, so the function it called was
undefined on a clean path. The author's local runs passed because they used a
*dirty* path — an interactive MATLAB session (and an `addpath(genpath(pwd))`
batch run) that already had the source folders on the path. CI uses a clean
path (`matlab-actions/run-tests`, `select-by-folder tests/unit`, no `genpath`,
no `startupadigator`), so it failed.

CLAUDE.md §2 already mandates running tests before pushing; the gap is that
*running them the dirty-path way did not reproduce CI*. `tests/ci_local.m`
already exists as the clean-path local gate, but it is optional and was not
used. The defect is also latent in the suite: each of ~32 test classes
hand-rolls its own path fixture, so a new class can silently forget it (issue
#82).

## Decision

Three coupled changes (issue #82):

1. **Clean-path pre-push hook** — `.githooks/pre-push` runs `tests/ci_prepush.m`
   (lint + unit + integration — the *unit-level* CI PR gate) in a fresh
   `matlab -batch`, so the path is clean. Opt in per clone with `git config
   core.hooksPath .githooks`; skips cleanly when MATLAB is not on `PATH`;
   bypassable only via the explicit `git push --no-verify`. It does **not** run
   CI's coverage ratchet (`ci_coverage`) — coverage instrumentation roughly
   doubles the runtime and a slow hook invites `--no-verify`, so the ratchet
   stays CI-only (run `ci_coverage` manually for coverage-sensitive changes).
   `ci_local` remains the full local gate (adds the Coder-gated system suite).
2. **Shared test base class** — `tests/AdigatorTestCase.m` applies the standard
   source-path `PathFixture` set (root, lib, lib/cadaUtils, util, embedding) in
   `TestClassSetup`. New test classes subclass it instead of hand-rolling the
   fixture (and so cannot forget it). Existing classes keep their own setup;
   migrating them is optional cleanup.
3. **Path-hygiene guard** — `tests/unit/UTestPathHygieneTest.m` asserts every
   `tests/{unit,integration}` class either subclasses `AdigatorTestCase` or
   declares a `TestClassSetup`, so a class with neither is reported **by name in
   the suite itself** (clean-path CI + the hook) rather than as a cryptic
   `Undefined function`.

## Consequences

- A clean-path local invocation (the hook, or `matlab -batch "addpath('tests');
  ci_prepush"`) reproduces CI's lint + unit + integration pass/fail (the
  coverage ratchet runs only in CI); the dirty-path divergence that bit #81 is
  gone for anyone who enables the hook.
- A new test class that forgets its path setup is caught **locally and in CI**
  by the guard, immediately and by name.
- The hook is opt-in (git cannot force `core.hooksPath`) and complements — does
  not replace — the §2 reviewer subagent, which catches design issues a green
  suite will not.
- **Revisit if:** the hook's runtime (cold-start + lint + unit + integration)
  grows enough that `--no-verify` becomes routine — then narrow it to a
  changed-area subset; or if a project-level git config / setup script can make
  `core.hooksPath` automatic on clone.

## Alternatives considered

- **Full-`ci_local` hook (incl. the system/Coder suite).** Rejected for the
  hook: the Coder builds are slow even when licensed, and a slow hook invites
  `--no-verify`. `ci_local` stays the manual full gate; the hook runs the
  faster PR-gate scope.
- **A `genpath`-based hook.** Rejected — it would have passed locally exactly as
  the #81 author's run did and still gone red on CI. The clean path is the whole
  point; a genpath hook defeats it.
- **Guard as a static lint that detects "calls an `embedding/`/`util/`
  function without a fixture."** Rejected as fragile (reliably detecting which
  functions a test references by text is hard) and as redundant with the clean
  path. The "subclass-or-TestClassSetup" proxy is decidable, has no false
  positives on the current suite (all 32 classes already have a setup), and
  catches the actual defect (no setup at all).
- **Migrate all ~32 classes to `AdigatorTestCase` now + require it.** Deferred —
  a large, mechanical, risky diff for this PR. The guard accepts both patterns,
  so migration can happen incrementally; the base class is provided as the
  preferred default for new and touched classes.
