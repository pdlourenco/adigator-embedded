# Roadmap

Agreed development roadmap, driven by the two design issues:

- [#6](https://github.com/pdlourenco/adigator-embedded/issues/6) — variable
  (runtime-free) loop bounds: Tier 0 (vectorized mode, exists), Tier 1
  (Nmax generation + runtime trip count), Tier 2 (symbolic N).
- [#11](https://github.com/pdlourenco/adigator-embedded/issues/11) — N-D
  array support: Level 1 (folded-2D/cell patterns, docs), Level 2 (N-D
  parameter veneer with affine folded windows), Level 3 (full N-D `cada`).

The combined headline use case: **optimal allocation over time** — `N`
actuators × `K` time steps, both free at runtime from one generated
derivative file, with failure/reconfiguration masks.

Foundations already in place (see `docs/ANALYSIS.md` §1.5 for the full
disposition log): all analysis findings fixed or documented-benign with
pinning tests; CI through Phase 4 (PR gate + extended suites + ratchets);
embed modes verified equivalent and codegen-compatible; literal scatter
indices, data dedup/range compression in the inline emitter.

| # | Item | Source | Status |
|---|------|--------|--------|
| R1 | **Allocation-over-time example with today's machinery**: per-(actuator, time) terms vectorized over the product fold `N·K`, assembly wrappers for both reduction directions (moment matching per time step; time coupling), one generated file verified for several `(N,K)` pairs. Docs for the Level-1 patterns (folded 2D, cells). | #6 Tier 0, #11 options 1–2 + Level 1 | done (PR #13) |
| R2 | **#11 Level 2 veneer**: N-D declarations for parameters (`adigatorCreateAuxInput([m n ...])`), folded internally to 2D; `subsref` translates trailing-subscript slicing into affine column windows, multi-counter from day one (`B(:,:,a,k)`). Example `examples/jacobians/ndparam`, test `tests/integration/INDParamTest.m`. | #11 L2 | done (PR #14) |
| R3 | **#6 Tier 1**: `loopbound` option — generate at `(Nmax,Kmax)`, runtime trip counts (`assert(n <= Nmax); for ... = 1:n`), loop-overmap exit unions, padding-benign contract documented in `adigatorOptions`; nested-bounds form per #11 option 3, composed with the R2 veneer. Example `examples/jacobians/loopbound`, test `tests/integration/ILoopboundTest.m`. | #6 T1 | in progress |
| R4 | **Reverse mode, prototype path** (`docs/ANALYSIS.md` §3.4): standalone reverse transformer over the generated forward dialect, scoped to gradients of scalar costs with reductions — the companion both issues identify. | ANALYSIS §3 | planned |
| R5 | **Remaining §2.1 optimizations**: `J'·v`/triplet output modes, dead-code slicing — re-scoped after R1's solver integration shows which output form matters. | ANALYSIS §2 | planned |
| R6 | **Go/no-go on the deep extensions**: #6 Tier 2 (symbolic N) and #11 Level 3 (full N-D `cada`), decided on R1–R4 evidence. Expectation: fold + veneer + Tier 1 + reverse mode covers most practical demand; the shape-matrix suite is the regression net if Level 3 is attempted. | #6 T2, #11 L3 | decision gate |

Rationale for the order: each step de-risks the next. R1 proves the use
case decomposes with zero core risk and creates the shared fixture; R2 is
the smallest core touch and produces the parameter-side evidence for the
Tier-2 decision; R3 delivers reconfiguration; R4 covers the
reduction-shaped remainder; R6 spends the big effort only if the residual
need survives R1–R4.
