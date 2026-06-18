# ADR-0003 — Minimum supported release is R2022a

## Status

Accepted — 2026-06-18. Back-filled from the embedding-layer feature usage.

## Context

The embedding layer relies on MATLAB features introduced over several releases:

- `arguments` validation blocks — R2019b+;
- `readlines` / `writelines` — R2022a+;
- string arrays used throughout the embedding code.

The binding constraint is `readlines`/`writelines` at R2022a. Supporting older
releases would mean shimming those (and re-validating string usage), for users
who, for an actively developed embedded-codegen fork, are unlikely to be on a
pre-2022 MATLAB.

## Decision

Declare **R2022a the minimum supported release**. Document it in `DESIGN.md`
§Constraints and `CI_PLAN.md`; the release matrix tests against `{R2022a (floor),
latest}`.

## Consequences

- The embedding code may use R2022a features without back-compat shims.
- CI's nightly release matrix pins R2022a as the floor (`CI_PLAN.md` TS-S-03);
  a feature newer than R2022a entering the codebase must either be guarded or
  move the floor (a new ADR).
- **Revisit** if a user base on an older release materializes, or if the floor
  needs to rise for a feature with clear payoff.

## Alternatives considered

- **Shim `readlines`/`writelines` for older releases.** Rejected — ongoing
  maintenance and a second code path to test, for a user population that
  almost certainly isn't on pre-R2022a for embedded codegen work.
- **Track only "latest".** Rejected — a stated, tested floor is what lets
  downstream users know what they can rely on; "latest only" silently breaks
  anyone a release or two behind.
