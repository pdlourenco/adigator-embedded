# ADR-0005 — `DER_LEVELS`: select which derivative levels a wrapper returns

## Status

Accepted — 2026-06-19. First increment of roadmap R7a (issue #21,
generated-code slimming).

## Context

Issue #21 asks for a way to avoid the overhead of always returning the
function value *and every lower-order derivative* from a generated wrapper —
e.g. a Hessian file today always returns `[Hes, Grd, Fun]` even when the caller
only consumes `Hes`. The issue thread (and `docs/ROADMAP.md` R7) split the work
into:

- **R7a** — output-level selection + `_location`/`_size` metadata gating;
- **R7b** — an interprocedural backward field-slice over the assembled file;
- **R7c** — peephole no-op union-copy elimination.

R7a itself has two halves. The **output-level selection** half (which outputs
the wrapper assembles and returns) is a self-contained, low-risk feature and a
correctness boundary for classic mode (which scatters the returned struct at
runtime). The **`_location`/`_size` printer-gating** half requires threading the
embed-mode / `jac_output` knowledge into the *core transform* (the `_ADiGator*`
file is produced by `adigator()` before the wrapper-generation options apply);
the issue thread concluded that R7b's slice removes those same statements anyway,
so in embed mode the printer-gating drops from a prerequisite to an efficiency
option.

The maintainer chose (2026-06-19) to land the **output-level selection** half
first as a standalone PR and fold the metadata-gating into R7b, and to shape the
selector as a **numeric level vector** (their `[2] = Hessian only` suggestion in
#21).

## Decision

Add an `adigatorOptions` field **`DER_LEVELS`**: empty `[]` (default) or a vector
of integers from `{0,1,2}` where `0` = function value, `1` = first derivative
(gradient/Jacobian), `2` = Hessian.

- The **top level** the generator is named for is **always returned** — a file
  named `_Hes`/`_Jac`/`_Grd` must return that derivative. `DER_LEVELS` therefore
  only chooses which *lower-order* outputs accompany it. `[0 1]` for a Hessian
  (no level 2) is rejected; use the gradient/Jacobian generator instead.
- The **default** `[]` returns every level the generator produces, reproducing
  the historical signatures (`[Jac,Fun]`, `[Hes,Grd,Fun]`, `[Grd,Fun]`) **byte
  for byte** — the option is purely additive/opt-in.
- In a `Grd→Hes` chain `DER_LEVELS` applies **only to the final (Hessian) file**;
  the gradient intermediate keeps its full `[Grd,Fun]` signature so the pruned
  artefacts stay re-differentiable (`ANALYSIS.md` B6).
- Validation/resolution lives in one helper, `util/adigatorResolveDerLevels.m`,
  shared by `adigatorGenJacFile` (max level 1) and `adigatorGenHesFile`
  (max level 2). `adigatorOptions` does the type/range check at parse time.

## Consequences

- Callers that only need a subset (`[2]`, `[1 2]`, …) get a wrapper that
  assembles and returns only those outputs — less per-call allocation and
  scatter, and a smaller wrapper.
- No contract change by default: C-1 (output *shapes*) and C-2 (evaluation
  interface) are untouched — each *emitted* output keeps its contracted shape;
  `DER_LEVELS` changes only which outputs are present and the wrapper signature.
  `DESIGN.md` §C-1 records the option as additive.
- The `_location`/`_size` metadata-gating and the dead-value slice remain R7b;
  this ADR does not pre-empt that design.
- *Verified by:* `tests/integration/ILevelSelectTest.m` (`CI_PLAN.md` TS-I-05):
  signature trimming, numeric equality of emitted outputs vs. full generation,
  the gradient intermediate staying `[Grd,Fun]`, the validation guards, and
  composition with the embedded pipeline (mode `l`).

## Alternatives considered

- **String tokens** (`output_levels={'hes'}`), mirroring `jac_output`. Rejected
  in favour of the numeric vector the maintainer suggested in #21 — it reads
  naturally as "derivative orders" and orders/deduplicates trivially.
- **Allow dropping the top level** (a `_Hes` file returning only `Grd`/`Fun`).
  Rejected as nonsensical and wasteful (the second `adigator` pass still runs);
  the lower-order generator is the right tool, and the guard makes the mistake
  explicit.
- **Do the `_location`/`_size` printer-gating in the same PR.** Deferred to R7b
  per the issue-#21 analysis (the slice subsumes it; the core-transform plumbing
  is avoided).
