# ADR-0007 — Randomized / Monte-Carlo V&V: non-gating, tolerance-free oracles, fixture-promoting

## Status

Accepted — 2026-06-21. Issue [#38](https://github.com/pdlourenco/adigator-embedded/issues/38).
Lands as roadmap R9 and `docs/CI_PLAN.md` REQ-T-09 / TS-S-04.

## Context

The existing test estate (`docs/CI_PLAN.md`) is **example- and fixture-driven**:
`IShapeMatrixTest`, `IEmbedModesTest`, `IRevGradTest` exercise only the
shape/op combinations someone wrote down. The bug analysis (`docs/ANALYSIS.md`
B7–B10) showed the failures lived precisely in the *combinations* nobody
enumerated — degenerate shapes, density-dependent branches, mode interactions.
Issue #38 asks for a Monte-Carlo battery that randomizes function bodies,
shapes, sizes and parameters to attack those untested combinations, *run
locally per release rather than as a CI gate*.

A randomized AD test stands or falls on three choices: the **oracle** (a random
function has no known derivative), whether it **gates** (random seeds are
non-deterministic), and whether failures become **durable** (a red seed is
worthless if it cannot be replayed). This ADR fixes those three; the staged
build-out is in `docs/ROADMAP.md` R9.

## Decision

1. **A new opt-in capability under `tests/montecarlo/`**, driven by
   `mcCampaign(nIters, seed, generators, oracles, budget, report)`. It is
   **never a required PR check**. A single fixed-seed, fixed-iteration
   `MCSmokeTest` provides per-merge drift detection. It lives under
   `tests/montecarlo/` — *not* under `tests/{unit,integration,system}/` — so
   neither the PR gate (`.github/workflows/ci.yml`, which selects only
   `tests/unit` + `tests/integration`) nor the local `ci_local` folder sweep
   (`tests/{unit,integration,system}`) runs it; the extended (per-merge)
   workflow selects `tests/montecarlo` explicitly. The unbounded campaign is a
   local / release-checklist run. The TS-S-04 ID marks its *validation-level*
   role in the V-model, not a `tests/system/` location.

2. **Tolerance-free oracles are the backbone; finite differences are
   secondary.** In priority order:
   - **cross-mode exact equality** — `embed_mode` `'c'`/`'l'`/`'i'` must be
     bit-identical (REQ-T-04 invariant, already asserted on fixtures in
     `IEmbedModesTest`);
   - **known-derivative-by-construction** — generators that emit functions
     whose exact Jacobian/Hessian is known (affine → `J = A`, quadratic →
     `H = Q`, elementwise from the trusted rule table);
   - **sparsity superset** — `find(|J|>0) ⊆ find(JacobianStructure)`
     (REQ-T-03), needs only a random eval point.

   Forward-vs-reverse gradient equality (reusing `IRevGradTest`/`fdgrad`) and
   Hessian symmetry are added as the gradient/second-order checks. Central
   finite differences (`fdjac`/`fdhess`) are a **secondary** sanity net with a
   conditioning guard that rejects ill-posed sample points — never the primary
   oracle.

3. **Every failing seed is reduced and promoted.** On failure the driver
   delta-debugs the case to a minimal reproducer (`mcShrink`) and writes it as
   a deterministic `matlab.unittest` case under
   `tests/montecarlo/regressions/` (`mcPromote`). This is the mechanism that
   turns a non-deterministic fuzzer into permanent deterministic coverage; it
   is in the first build phase, not deferred.

4. **No new runtime/test dependency for the core phases.** Generators,
   oracles, shrinker and reporter are plain MATLAB. The differential-vs-upstream
   and Symbolic-Toolbox oracles (which *would* add a dependency) are deferred to
   an optional later phase and stay skip-clean.

The phased build (A: enablers + affine/quadratic/shape-fuzz + the three
tolerance-free oracles + shrink/promote + smoke; B: rule-table generator,
forward-reverse / symmetry oracles, negative/hygiene fuzzing, coverage; C:
typed expression-tree synthesis with domain-aware sampling; D optional:
differential-vs-upstream) is tracked in `docs/ROADMAP.md` R9.

## Consequences

- A regression in any of the tolerance-free invariants is found across the
  *combination space*, not just the enumerated fixtures, without FD tolerance
  tuning or singularity bookkeeping.
- The deterministic suite grows automatically from real discoveries
  (`tests/montecarlo/regressions/`), so a campaign finding is captured even
  though the campaign itself never gates.
- The PR gate's cost and flake profile are unchanged (the fuzzer is out of it);
  drift is caught per-merge by the fixed-seed smoke only.
- **Revisit** if: (a) a property-based framework lands in MATLAB and is worth
  the dependency over the hand-rolled driver; (b) the smoke proves flaky even
  at a fixed seed (then drop it from per-merge to local-only); or (c) the
  differential-vs-upstream oracle (Phase D) is wanted, which re-opens the
  pinned-dependency question deferred here.

## Alternatives considered

- **Finite differences as the primary oracle.** Rejected. For random functions
  you cannot hand-pick points away from singularities; FD then needs
  per-case tolerance tuning and produces ill-conditioning false positives. The
  cross-mode and known-derivative oracles are exact and free of all of that;
  FD is kept only as a secondary cross-check.
- **Make the campaign a required PR check.** Rejected, and the issue itself
  asks for "not necessarily on the CI". A required green/red gate on a
  random-seed fuzzer is flake by construction. The fixed-seed smoke gives the
  per-merge drift signal without that.
- **Positive-fuzz unsupported constructs** (`while`, data-dependent branches).
  Rejected as positive tests — the tool only supports unrolled / static-trip
  rolled loops. They are generated only as *negative* tests (Phase B) asserting
  a clean error plus the REQ-T-07 hygiene invariants.
- **Adopt a property-based-testing framework / Symbolic-Toolbox oracle now.**
  Rejected for the core phases: a new dependency for machinery a ~200-line
  driver covers, and Symbolic licensing/weight. Kept as an optional Phase-D
  spot-oracle.
- **Fuzz without shrink/promote.** Rejected: an un-minimized random failure is
  hard to act on and evaporates with the seed; the shrink→promote loop is the
  part that earns the capability its keep, so it ships in Phase A.
