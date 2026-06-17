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
| R3 | **#6 Tier 1**: `loopbound` option — generate at `(Nmax,Kmax)`, runtime trip counts (`assert(n <= Nmax); for ... = 1:n`), loop-overmap exit unions, padding-benign contract documented in `adigatorOptions`; nested-bounds form per #11 option 3, composed with the R2 veneer. Example `examples/jacobians/loopbound`, test `tests/integration/ILoopboundTest.m`. | #6 T1 | done (PR #15) |
| R4 | **Reverse mode, prototype path** (`docs/ANALYSIS.md` §3.4): `adigatorGenRevGradFile`, a standalone reverse transformer over the generated forward dialect — slices the function-value tape, executes it once at generation time to resolve sizes and index maps, and emits a self-contained adjoint gradient file; scoped to gradients of scalar costs with reductions. Example `examples/gradients/logsumexp`, test `tests/integration/IRevGradTest.m`. | ANALYSIS §3 | done (PR #19) |
| R5 | **Output-form optimizations** (re-scoped per ANALYSIS §2.3(5)): `jac_output='nonzeros'` wrapper mode (nonzero vector with the constant pattern exported once via `output.JacobianLocs`, no per-call dense projection) and `adigatorGenJtVFile` (`J'·v` in one forward+adjoint sweep on the R4 reverse engine, runtime `v`). Dead-code slicing re-scoped into R7 (issue #21). Test `tests/integration/IOutputModesTest.m`. | ANALYSIS §2 | done (PR #20) |
| R6 | **Go/no-go on the deep extensions**: #6 Tier 2 (symbolic N) and #11 Level 3 (full N-D `cada`), decided on R1–R4 evidence. Expectation: fold + veneer + Tier 1 + reverse mode covers most practical demand; the shape-matrix suite is the regression net if Level 3 is attempted. | #6 T2, #11 L3 | decision gate |
| R7 | **Generated-code slimming for embedded use** (issue #21), three increments (a)→(c): **(a) output-level selection + metadata gating** — a level vector selects which derivative levels the wrapper returns, and the printer does not emit `_location`/`_size` (or unrequested-level output assembly) where the mode provably never reads it. In embed `'l'`/`'i'` and `jac_output='nonzeros'` this is an *efficiency* lever (the slice in (b) removes the same statements anyway); for classic mode, which scatters through `_location` at runtime, it is a correctness boundary. Applied only to the final file of a Grd→Hes chain so intermediates stay re-differentiable (B6). **(b) Interprocedural backward field-slice** over the assembled single embedded file — a worklist fixpoint over `(function, demanded-output-field-set)` across the stored function list (`AdigatorGeneratedFiles`: `.name` wrapper → `.dername` → `.func`), seeded by the wrapper's declared returns; per function an intra-function slice (reusing the R4 parser; rolled `for…end` blocks handled conservatively as a unit) yields its live statements and the input fields it actually consumes, whose demand is pushed back to the producing function/struct. Field-granular and interprocedural, so it removes dead value chains *and* unread output fields (e.g. `_location`/`_size` in embed modes) and subsumes the per-variable `checkcode`/flatten idea. **Runs before `prune_adigator_mat`** so the now-unreferenced `Gator*Data.Index*` constants drop from the `.mat`/inline data. **(c) Peephole no-op union-copy elimination** (`cada1td1 = zeros(k,1); cada1td1(1:k) = src;`, ANALYSIS §2.3(6)). Lower-order *values* stay where derivative rules consume them. Every increment is gated by a generation-time numeric round-trip check (original vs. slimmed on staged inputs, the R4 harness). | issue #21, ANALYSIS §2 | planned |
| R8 | **Struct inputs through the convenience/embedded wrappers** ([#24](https://github.com/pdlourenco/adigator-embedded/issues/24), scope A — structs that *carry* inputs): the core `adigator` already accepts structs/cells (`ParseUserFunInputs` recursion + `@cadastruct`), but `adigatorGenJacFile`/`adigatorGenHesFile` (hence `adigatorGenDerFile_embedded`) scan only the top level of the input cell for the derivative variable and error if it is nested (`adigatorGenJacFile.m:142-158`, `adigatorGenHesFile.m:138-154`). Teach those generators to locate the deriv field by the same recursion, record its *access path* (`in.x`, `in.sub.x`, `in.c{2}.x` — scalar-struct fields and cell elements, to any depth; struct arrays excluded), and emit the seeding along that path (`gator_in.x.f = in.x; gator_in.x.dvod = ones(prod(size),1)`) while forwarding the rest of the struct unchanged; aux struct fields already pass through `adigator` untouched. Single-vod contract kept; composes with the R2 N-D aux veneer. No core/theory change — wrapper layer only; downstream embedded stages (`prune_adigator_mat`, `adigator_patch_derivative`, inline emission) are input-shape agnostic. Example `examples/jacobians/structinput` (e.g. `in.x` deriv + `in.par` aux), test `tests/integration/IStructInputTest.m` asserting cross-mode ('c'/'l'/'i') numeric equivalence. | issue #24 (scope A) | planned |

Rationale for the order: each step de-risks the next. R1 proves the use
case decomposes with zero core risk and creates the shared fixture; R2 is
the smallest core touch and produces the parameter-side evidence for the
Tier-2 decision; R3 delivers reconfiguration; R4 covers the
reduction-shaped remainder; R6 spends the big effort only if the residual
need survives R1–R4.

R7 design note (issue #21): the embedded pipeline already appends the
wrapper, the `_ADiGator*` function, and (inline mode) the data function
into one file (`adigatorGenDerFile_embedded.m`, the
`writelines(...,'WriteMode','append')` block), so the slice runs on the
fully-assembled file with no cross-file boundary — the only
live-by-contract outputs are the entry wrapper's declared returns
(`Jac`/`Hes`/`Grd`/`Fun`). `checkcode` alone is per-function and cannot
link a caller's `dydt.dy_location` read to the subfunction's field
assignment, which is why R7b is the interprocedural field-slice over the
stored function list rather than a single-file lint pass; the
flatten/`checkcode` trick is at most an optional mop-up. The slice-before-
prune ordering (vs. today's prune-first at the top of the per-derivative
loop) is what turns deleted `_location` writes into `.mat`/inline-data
savings.

R8 scope note (issue #24): scope A only — structs are containers that
*carry* the inputs (a deriv field plus aux fields used internally), and
differentiation is still w.r.t. a single numeric field, so the core's
existing per-field variable handling is sufficient and only the wrapper's
deriv-input discovery and seeding need to change. Scope B (a struct as the
*variable of differentiation* — one Jacobian against all numeric fields at
once, requiring the fields concatenated into a single vod with a combined
column-major linearization and a block-layout convention) is explicitly
out of scope here and would need its own design pass.
