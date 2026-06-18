# ADR-0001 — Down-cast only `Index*` fields; keep `Data*` as `double`

## Status

Accepted — 2026-06-18. Back-filled from the fix for `ANALYSIS.md` bug B1.

## Context

To shrink the constant tables a generated derivative file carries (relevant for
embedded targets), `prune_adigator_mat` (`embedding/prune_adigator_mat.m`, since
extracted from `adigatorGenDerFile_embedded.m`) down-casts integer-valued,
non-sparse numeric fields to a narrow integer class. The Gator data struct holds two
distinct kinds of field (see [`../DESIGN.md`](../DESIGN.md) §C-3): `Index*`
fields are index vectors, while `Data*` fields are **numeric value constants
printed into arithmetic** (e.g. `cada1f1 = Gator1Data.Data1*x.f;` for `y = A*x`
with an integer-valued `A`).

Down-casting *every* integer-valued field also catches `Data*`. At run time
`uint32 * double` either errors ("Integers can only be combined with integers
of the same class, or with scalar doubles") or, in scalar cases, silently
propagates an integer class and **rounds all subsequent derivative values**.
Integer-valued constant matrices (identities, selection matrices, ±1 stencils)
are extremely common, so this is high-severity.

## Decision

Apply the integer down-cast **only** to fields whose name starts with `Index`
(`startsWith(idxName, "Index")`). Leave `Data*` fields as `double`, bit-identical
to their generated value.

## Consequences

- Constant index tables still shrink; arithmetic constants stay correct.
- `Data*` is the binding contract C-3 in `DESIGN.md`; this ADR is the rationale
  reviewers cite when a future change touches `prune_adigator_mat`.
- The fix has landed: the down-cast is gated on `startsWith(idxName, "Index")`
  in `embedding/prune_adigator_mat.m` and pinned by `tests/unit/UPruneMatTest.m`
  (`CI_PLAN.md` TS-U-04) — `Data*` staying `double` is a hard assertion
  (`dataFieldsStayDouble`), not a `KnownIssue`.
- **Revisit** if a measured size win justifies narrowing `Data*` too — which
  would require emitting an explicit cast back to `double` at every arithmetic
  use site, a much larger change.

## Alternatives considered

- **Down-cast everything, add runtime casts on use.** Rejected — spreads casts
  across every generated arithmetic statement for a marginal size win, and is
  fragile against new statement shapes.
- **Narrow `Index*` to `uint16` when `max(idx) < 65536`.** A *complementary*
  further win (typical embedded sizes fit), not an alternative; tracked as an
  optimization in `ANALYSIS.md` §2.1, not adopted here.
