# CI plan for adigator-embedded (simplified V-model)

This plan defines the continuous-integration strategy for the repository.
It follows a simplified V-model: requirements are stated first (left leg),
each requirement is then assigned one or more tests that verify or validate
it (right leg), and the CI workflows execute those tests automatically.
Requirement/test IDs are stable so commits, issues, and test code can
reference them.

```
  Left leg (specification)                Right leg (test execution)

  REQ-T  Tool requirements   ──────────►  TS-S  System / validation tests
     │                                          ▲
  REQ-C  Component requirements ───────►  TS-I  Integration tests
     │                                          ▲
   (code: lib/, util/, embedding/) ────►  TS-U  Unit tests
```

Constraints that shape the plan (verified against the codebase):

- The code requires real MATLAB. The embedding layer uses `arguments`
  blocks (R2019b+), `readlines`/`writelines` (R2022a+), and string arrays,
  so **minimum release is R2022a**. **GNU Octave is not viable today**:
  besides those three features (all unsupported in Octave), the core relies
  on `classdef`-based operator overloading (`lib/@cada/cada.m`,
  `@cadastruct`) with heavy `subsref`/`subsasgn` dispatch, an area where
  Octave's classdef support is incomplete. Octave could only become an
  option after a deliberate compatibility layer (replace `arguments`
  blocks, shim `readlines`/`writelines`, audit string usage, verify classdef
  dispatch) — tracked as a possible future work item for license-free local
  runs and private-repo CI, not assumed by this plan. The cheap
  license-free alternative for contributors is the local pre-push script
  (§3.3), which runs the same suites in an existing MATLAB session.
- CI runs on GitHub Actions with `matlab-actions/setup-matlab@v2`.
  For a public repository, MathWorks provides licensed MATLAB on
  GitHub-hosted runners at no cost; for a private repository a MATLAB
  batch-licensing token must be stored as the `MLM_LICENSE_TOKEN` secret.
- MATLAB installation is the dominant fixed cost of every job, so the PR
  pipeline is a **single job** (one install, sequential steps) rather than
  parallel jobs that each pay the install (§3.1).
- The repository already contains validation assets that the test suites
  reuse rather than reinvent: the finite-difference harness in
  `unit_tests/test_unarymath_rules.m`, and examples with built-in
  ADiGator-vs-finite-difference comparisons (`examples/jacobians/arrowhead`,
  `examples/jacobians/polydatafit`, `examples/stiffodes/brusselator`) —
  see §2.4a.
- Core transformation tests need base MATLAB only. The optimization
  examples need the Optimization Toolbox; code-generation validation needs
  MATLAB Coder. These are isolated in separate, individually skippable jobs.
- Known bugs documented in `docs/ANALYSIS.md` (B1-B22) must be *pinned* by
  tests. The `KnownIssue` tag + `assumeFail` mechanism (a test that detects the
  buggy behaviour and reports as filtered until the fix lands, then runs its
  trailing assertions as a regression guard) is the policy for *future* bugs.
  As of `docs/ANALYSIS.md` §1.5, **all of B1–B22 are fixed / mitigated /
  won't-fix / documented-limitation** — the one open rough edge is the B19 `if`-guarded
  over-approximation residual (#108). The remaining `KnownIssue`-tagged tests are
  the self-healing B7–B10 cases in `IShapeMatrixTest`, which already run as
  guards (the tag removal is a verified-cleanup follow-up, not an open bug); the
  B17–B22 batch (§1.3c) is pinned by dedicated integration guards (TS-I-13..17).

---

## 1. Requirements (left leg)

### 1.1 Tool-level requirements (REQ-T)

| ID | Requirement | Acceptance criterion |
|----|-------------|----------------------|
| REQ-T-01 | **Derivative correctness.** Generated derivative files shall produce first and second derivatives — and, per R22, higher-order (`'nth-derivative'`) derivatives — that match a reference (analytic where available, central finite differences otherwise) for all supported operations. | Relative error ≤ 1e-6 (1st order) / 1e-4 (2nd order, FD reference) on all test points away from singularities; higher order checked against an analytic n-th derivative *(planned, R22)*. |
| REQ-T-02 | **Output conventions.** Wrapper outputs shall conform to `adigatorDerivativeConventions.m` / DESIGN §Contracts C-1: gradient of scalar f: Rⁿ→R is n×1; Jacobian of f: Rⁿ→Rᵐ is m×n; Hessian of scalar f is n×n; vector-function Hessian is [m·n × n] with row = (x₁−1)·m + y; **higher order (order k>2, C-1/ADR-0020)** the `[M·Nᵏ⁻¹ × N]` fold (row = i + (j₁−1)·M + … + (j_{k−1}−1)·M·Nᵏ⁻², col = j_k) *(planned, R22)*; generalized shapes per the conventions table. The output **form** (`matrix` vs `nonzeros`/`*Locs`) and canonical **names** (C-6) are governed by REQ-T-11. | Asserted shape and element placement for every (input shape × output shape × density) combination; the order-k fold's shape + placement per stage, and the Decision-6 host utilities `dvp(D,V)` (contracts one derivative order — directional-derivative / Taylor-step reconstruction — permute-free for a single direction) and `unfold(D)` (lossless N-D view ↔ the flat fold) verified against the fold *(planned, R22)*. |
| REQ-T-03 | **Sparsity metadata consistency.** `output.JacobianStructure` / `output.HessianStructure` shall be a superset of the numerically nonzero pattern and consistent with the wrapper's element placement. Per [ADR-0030](decisions/ADR-0030-csc-sparse-pattern-contract.md) this restates onto the sole CSC pattern (`*CSC` metadata superset + placement via reconstruction; the CSC invariants — monotone `ColPtr`, strictly-increasing per-column `RowIdx`, unique in-range locations, empty-column pointers — become part of this requirement) *(planned, R31 — flips with the implementation PR)*. | `find(abs(J) > 0) ⊆ find(Structure)` at random test points; same indexing convention as the wrapper output. Post-R31: superset + placement via `adigatorCSCToSparse` reconstruction, plus the CSC invariant checks (TS-U-20/TS-I-25). |
| REQ-T-04 | **Embeddability.** With `embed_mode='l'` the tool-generated code shall introduce no `global` declarations and no runtime `load`; with `embed_mode='i'` additionally no `.mat` file and no `coder.load` (a *user's own* construct may pass through per ADR-0023 below). All three modes shall return numerically identical results. Per ADR-0021 (C-4), `'l'` is **deprecated** — it shall emit a one-time deprecation warning while remaining numerically identical — and the inline **`split_data`** two-file form shall hold the same invariants (both derivative and data files are source; no `global`/`load`/`.mat`/`coder.load`) *(planned, R24)*. Per ADR-0023 rev 2026-07-04 (C-4), a user's own cells / `load` / `global` in the differentiated source shall pass through **verbatim (as classic) with a `adigator:embed:unsupportedConstruct` warning** — embed is no more restrictive than classic; generation continues, the embed result is numerically identical to classic (B21 reclassified warn-and-allow; B22-in-embed cells generate), and constructs classic itself rejects still error from the core. | Static text checks on generated files + cross-mode numeric equality (exact, same arithmetic); the embed source-construct gate **warns and still generates** on a user's cells/`load`/`global` (construct emitted verbatim, embed-vs-classic AbsTol 0) while classic stays silent; split-form static + cross-mode checks and the `'l'` deprecation warning *(planned, R24)*. |
| REQ-T-05 | **Code-generation compatibility.** Files generated in modes 'l' and 'i' shall pass MATLAB Coder `codegen` (lib target) without errors and the MEX/lib shall reproduce MATLAB results. Where MATLAB Test is licensed (R2023a+), the equivalence check is performed via `matlabtest.coder.TestCase` (Build→Execute→`verifyExecutionMatchesMATLAB`), with the hand-rolled `codegen`+compare path retained as the Coder-only / floor-release fallback (ADR-0014). | `codegen` exit success; MEX output equals MATLAB output to 1e-12. License-gated. |
| REQ-T-06 | **Reproducibility.** Regeneration with identical inputs and options shall produce functionally identical files; `overwrite=0` shall refuse to clobber; user-specified `path` shall receive all generated artifacts and nothing shall be left in the calling directory. | Byte comparison modulo timestamps; file-location assertions. |
| REQ-T-07 | **Robustness / hygiene.** Invalid inputs and mid-transformation errors shall raise clean errors, restore the MATLAB path, close all file handles, and leave no stray globals. | `path()` before == after; `fopen('all')` empty delta; `who('global')` delta empty after failure injection. |
| REQ-T-08 | **Example health.** All shipped examples shall run headless without error (toolbox-gated where applicable). | Each example `main.m` completes; spot numeric checks. |
| REQ-T-09 | **Randomized robustness (V&V).** Over a seeded Monte-Carlo campaign of generated derivatives (randomized function bodies, input/output shapes, sizes, densities, embed modes), outputs shall satisfy the tolerance-free oracles (cross-mode exact equality, known-derivative-by-construction, sparsity-superset) and the hygiene invariants of REQ-T-07. Where MATLAB Test + Coder are available (R2023a+), a *sampled* codegen-equivalence oracle additionally asserts that the compiled C of the embedded mode matches MATLAB over the random case (ADR-0014, cross-validating REQ-T-05 at scale). *Non-gating* — the campaign is opt-in/local; any failing seed shall be reproducible and reducible to a deterministic regression fixture. *(Phased build in `docs/ROADMAP.md` R9 / R14 / R15. Issue #38, ADR-0007, ADR-0014.)* | Pinned-seed smoke reports zero failures; each discovered failure is minimized (`mcShrink`) and promoted (`mcPromote`) into the deterministic suite. |
| REQ-T-10 | **Embedded-Coder (ERT) codegen completeness.** Every non-classic (`'l'`/`'i'`) generated derivative — gradient, Jacobian, Hessian, `gradient-reverse`, across `slim_embed` settings — shall codegen under the **stricter Embedded Coder target** (`coder.config('lib','ecoder',true)`), not only plain MATLAB Coder `lib` (which tolerates ERT-illegal struct-field patterns and was masking real embedded-codegen gaps). *(Core fork objective, issue #80; phased in `docs/ROADMAP.md` R20 — Gap A landed PR #81; Gap B rolled-path done via Path A (#89), with the unrolled O(n²) form and reverse-mode deferred to R21. Distinct from REQ-T-05, which checks compiled-output equivalence; this checks ERT acceptance.)* | `ecoder` codegen exit-success for every (DerType × `'l'`/`'i'` mode × `slim_embed`) cell exercised by the showcase / campaign; no plain-`lib`-only pass left masking an ERT failure. Rolled scalar-cost gradient/Hessian are green as of R20 Path A (#89, `SRolledErtCodegenTest` / TS-S-06); the still-open cells are the **unrolled** O(n²) form and **reverse-mode** (deferred to R21), plus R20's remaining CI switch — **(b) done (#92: `SCodegenTest` + `derivShowcaseC` lib builds now `ecoder`)**, **(c) spec'd born-ERT** (ADR-0014 amended, #80 R20c — the campaign oracle's build targets `ecoder`; the oracle implementation is R15/maintainer-authored), (d) option-C printer suppression. License-gated. |
| REQ-T-11 | **Generalized derivative output form.** Per ADR-0022 (C-6 output-form facet + C-2), the output form shall be selectable via `der_output ∈ {matrix, nonzeros}` selecting the generator's **top-order output** (`jac_output` a level-1-only alias, no cross-sync — it never flips a Hessian); in `nonzeros` form each supporting DerType shall export its constant sparsity pattern once via its `*Locs` companion (`HessianLocs` the `output.JacobianLocs` analog), reconstructing the dense derivative exactly. Every wrapper's outputs shall use the canonical C-6 **names** — including the forward gradient returning `Grd` (not `Jac`). **Phase 1 done** (R25/#99). The full `(der_output × DerType × mode)` matrix and genuine per-derivative-level selection are **deferred to R25 phase 2**. Per [ADR-0030](decisions/ADR-0030-csc-sparse-pattern-contract.md) (#192) the form respells to `der_output ∈ {matrix, csc}` with per-role `*CSC` metadata replacing the `*Locs`/`*Structure` surface and `jac_output` removed — a pre-v2.0-release break *(planned, R31 — flips with the implementation PR; decision-b top-order semantics unchanged)*. *(Issue #84; prerequisite for R22/#85.)* | `nonzeros` + `HessianLocs` reconstructs the dense Hessian to FD tolerance; `der_output='nonzeros'` flips only the top output (a Hessian file's `Grd` stays dense); the forward-gradient signature asserts `[Grd, Fun]` — verified by TS-I-12. Phase-2 support-matrix cells *(planned, R25 phase 2)*. |

### 1.2 Component-level requirements (REQ-C)

| ID | Component | Requirement |
|----|-----------|-------------|
| REQ-C-01 | `lib/@cada/cadaunarymath.m` | Every unary derivative rule shall match finite differences over each function's domain, including negative arguments and degree-mode variants. |
| REQ-C-02 | `lib/@cada/cadabinaryarraymath.m` | Every binary rule (incl. `atan2`, `power`, scalar-array broadcasting) shall match finite differences. |
| REQ-C-03 | Structural ops (`subsref`, `subsasgn`, `horzcat`, `vertcat`, `reshape`, `repmat`, `sum`, `transpose`, `mtimes`, `mldivide`) | Derivative values and `nzlocs` sparsity shall be correct for scalar/row/column/matrix operands. |
| REQ-C-04 | `util/adigatorGenJacFile.m`, `util/adigatorGenHesFile.m` | Dimension handling shall be correct in **every** branch: dense (`reshape`), scalar-of-vector, vector-of-scalar, scalar-of-matrix (remap), matrix-of-scalar (remap), matrix Jacobian sparse and full branches, vector-output Hessian (m≠n), gradient vs. Jacobian convention selection. *(Pins bugs B7, B8, B9, B10 of ANALYSIS.md.)* |
| REQ-C-05 | `prune_adigator_mat` (in `embedding/adigatorGenDerFile_embedded.m`), `embedding/adigatorReferencedIndex.m` | Pruning shall retain every `Index*` the (possibly slimmed) generated code still references and all non-empty `Data*` fields; with no slice it retains **all** `Index*` (the default). The slice-before-prune data shrink (issue #21 / ADR-0010) may drop an `Index*` only when a static scan proves the slimmed code cannot reference it (keep-all on any doubt). Integer down-casting shall apply **only** to `Index*` fields; `Data*` values shall remain `double` and bit-identical. *(Pins bug B1.)* |
| REQ-C-06 | `embedding/structure_to_embed_mfile.m` | Emitted data function shall round-trip: evaluating it returns a struct equal (values, classes, sizes, field set) to the input struct; emitted file shall be parseable (`checkcode` clean of errors). *(Pins bug B2.)* |
| REQ-C-07 | `embedding/adigator_patch_derivative.m` | Patching shall: remove the loader subfunction and loader guard, insert exactly one `%#codegen` per function, replace `global` per mode, wrap Gator data reads in `coder.const`, and behave correctly when patterns match multiple lines. *(Pins bugs B3, B4.)* |
| REQ-C-08 | Option handling (`adigatorOptions` + parsers in `util/`, `embedding/`) | Documented option spellings (upper/lower case) shall be accepted; unknown `embed_mode` values shall produce a clear error, including multi-character strings. *(Pins bugs B11, B12.)* |
| REQ-C-09 | File/path hygiene in generators | All opened file IDs shall be closed before generators return; `path()` restored on success and failure. *(Pins bug B13.)* |
| REQ-C-10 | Code quality | No new `checkcode` errors in `lib/`, `util/`, `embedding/`; warnings budget not exceeded (ratchet). |
| REQ-C-11 | Test-suite path isolation (`tests/AdigatorTestCase.m`, `tests/ci_prepush.m`) | Test classes that exercise `lib/`/`util/`/`embedding/` functions shall obtain the repo paths from the shared `AdigatorTestCase` base (or an equivalent `TestClassSetup` `PathFixture`), so the suite runs identically on a **clean path** (as CI and the pre-push hook do) and cannot pass only on a dirty interactive path. *(ADR-0017; issue #82 — the trap that reddened PR #81's CI twice.)* |

---

## 2. Tests (right leg) and traceability

### 2.1 Unit tests — `tests/unit` (TS-U)

Fast, base-MATLAB only, no file generation beyond `tempdir`. Run on every
push and pull request.

| ID | Test | Verifies |
|----|------|----------|
| TS-U-01 | `URulesUnaryTest` — port of `unit_tests/test_unarymath_rules.m` to `matlab.unittest`, FD sweep per rule with singularity exclusion. | REQ-C-01 |
| TS-U-02 | `URulesBinaryTest` — FD check of each binary derivative rule (plus, minus, times/`.*`, rdivide/`./`, power/`.^` with an inactive exponent, mtimes/`*`) with the variable of differentiation against constants of varied shapes (scalar/column variable × scalar/column/matrix constant) and against itself; the raw generated-file derivative reconstructed from the C-2 fields and compared to a dense FD Jacobian. | REQ-C-02 |
| TS-U-03 | `UStructuralOpsTest` — small fixed functions exercising each structural op (concatenation, gather with duplicate indices, indexed-assignment scatter, transpose, reshape, sum, mtimes); reconstruct the unrolled derivative from `y.dX`/`y.dX_location`/`y.dX_size` (asserting the C-2 interface shape) and compare against dense FD Jacobians. | REQ-C-03 |
| TS-U-04 | `UPruneMatTest` — synthetic Gator structs (Index*, integer-valued Data*, sparse, empty fields) → prune → assert retained fields, classes (`Data*` stays double), values. B1 fixed → hard-assertion guard (`dataFieldsStayDouble`); no longer tagged. Plus the `referenced*` cases (issue #21, ADR-0010): the optional referenced-map drops the unread `Index*`, keeps a referenced (even empty) one, the unshrunk-table fallback, drops a wholly-unreferenced table, leaves `Data*` alone, and `emptyMap == 2-arg` keep-all. | REQ-C-05 |
| TS-U-05 | `UEmbedMfileTest` — property-style round-trip of randomized structs (doubles, logicals, chars, cells, n-d arrays, empties, complex) through `structure_to_embed_mfile`; `isequaln` + class checks; `checkcode` on emitted file. | REQ-C-06 |
| TS-U-06 | `UPatchTest` — golden-file tests: checked-in fixture inputs (representative generated files, incl. one with two loader guards and nested subfunction names) → patch → compare to checked-in expected outputs for modes 'l' and 'i'. B3/B4 fixed → hard-assertion guard; no longer tagged. | REQ-C-07 |
| TS-U-07 | `UOptionsTest` — option spelling/validation matrix. B11/B12 fixed → hard-assertion guard; no longer tagged. | REQ-C-08 |
| TS-U-08 | `UCoreErrorHygieneTest` (gated, `tests/unit`): a successful transform AND a malformed one (injected failure) must each leave `path()`, the open-file set, and `who('global')` unchanged. Also pinned in the extended suite by the Monte-Carlo `mcGenNegative` / `oracleHygiene` pair (`MCSmokeTest.{negativeHygieneIsClean,successLeavesNoOpenHandles}`). Pins the B16 `adigator.m` error-path cleanup (ADR-0011); B13 family now pinned. | REQ-C-09, REQ-T-07 |
| TS-U-09 | `ULintTest` — `checkcode` over `lib/`, `util/`, `embedding/` with error-level gating and warning ratchet file. | REQ-C-10 |
| TS-U-10 | `UForwardTapeTest` — `adigatorForwardTapeSlice` (the statement parser / backward value-tape slicer extracted from `adigatorGenRevGradFile` for reuse by the R7b field-slice, issue #21): parsing, dependency extraction, the backward slice (dead-statement removal, derivative-chain exclusion, scatter reads-old), and the rolled-control-flow / parse guards, on hand-written tape snippets. | R7b foundation (issue #21) |
| TS-U-11 | `UFieldSliceTest` — `adigatorFieldSlice` (and the shared `adigatorParseTape`), the field-granular backward slicer at the core of R7b (issue #21): dropping UNdemanded sibling fields of an output struct (`.dy_location`/`.dy_size`) and the constant index tables they reference while keeping demanded fields and their value chains; whole-vs-field demand, value-only demand, scatter, and the inherited control-flow guard. | R7b core (issue #21) |
| TS-U-12 | `USlimEngineTest` — the R7b slice engine (issue #21): `adigatorWrapperDemand` (which output-struct fields the wrapper reads, embed vs classic) and `adigatorSlimDerivBody` (locate body → field-slice → eval-free dependency-closure gate → re-emit), including the conservative bail-outs (no demanded fields, missing markers, line continuation, rolled control flow) and the no-op-when-all-demanded path. Text-in / text-out on hand-written generated-file snippets. | R7b engine (issue #21) |
| TS-U-13 | `UPeepholeTest` — the R7c union-copy peephole (issue #21; ANALYSIS §2.3(6)): `adigatorPeepholeUnionCopy` collapsing `v = zeros(K,1); v(idx)=src;` to `v = reshape(src,K,1);` only when `idx` resolves (Gator-index or literal range) to the ordered identity `1:K`; the ordered-vs-permuted and partial-fill distinctions, the self-reference / vectorized-form skips, and the bail-outs. | R7c core (issue #21) |
| TS-U-14 | `UParseBlockTest` — the opt-in rolled-`for…end`-as-a-unit parsing in `adigatorParseTape` (roadmap R7b/#44): a rolled loop collapses into one atomic `.block` statement whose `.writes` is the union of bases it assigns and whose `.deps` are the externally defined bases it reads (loop variables and loop-local temporaries excluded; loop-carried bases also initialised outside kept); the line span, nested control-flow swallowing, and that strict mode (the default) and top-level non-`for` control flow stay rejected. | #44 (R7b rolled-loop coverage) |
| TS-U-15 | `USlimDerivFileTest` — the interprocedural field-slice `adigatorSlimDerivFile` (issue #44 item 1; ADR-0009): splitting a multi-subfunction generated `_ADiGator*` file into per-function blocks, the forward worklist that propagates a callee's demand from the result-struct fields the caller reads at a kept call site, the per-function closure-gated slice and whole-file reassembly (dead value chains / unread output fields dropped in every function), single-derivative-function delegation to `adigatorSlimDerivBody`, the **block-aware** call-site / result-field scans that slice a rolled `for…end` in a multi-subfunction file (R10(a): a subfunction call or callee-result read nested in a kept loop is seen and its demand propagated — both the call-in-loop and read-in-loop cases), and the conservative whole-file bails (no demanded fields; an in-loop call whose result is not a plain whole-struct assignment). Text-in / text-out on hand-written snippets. | #44 item 1 (ADR-0009) |
| TS-U-16 | `UTestPathHygieneTest` (subclasses `AdigatorTestCase`) — meta-test guard (ADR-0017, issue #82): scans every `tests/{unit,integration}` class and reports by name any that has **neither** a base class **nor** a `TestClassSetup`, i.e. relies on a globally-`genpath`'d (dirty) path. Catches in the suite itself — so CI and the clean-path pre-push hook both flag it — the PR #81 failure mode (a new class calling `embedding/`/`util/` without a `PathFixture` passes on a dirty interactive path, errors on CI's clean path). Checks setup *presence*, not path correctness (the clean-path run catches that). | REQ-C-11 |
| TS-U-17 | `UNormTest` — the `@cada/norm` overload + `isnan`/`isinf`/`isfinite` predicates (issue #28): vector p-norm gradients (2/1/Inf/`fro`, row + column) vs FD, the induced/matrix norms raise `adigator:norm:matrixNorm` rather than mis-differentiating, and the predicates are derivative-free. | REQ-C-01 |
| TS-U-18 | `UStripDeadOutputIndicesTest` — the output-index-metadata strip (#80/#81, approach D): the `_size`/`_location` output-field index tables are removed from the embeddable-mode generated data while retained tables/values are unchanged. | REQ-T-04 |
| TS-U-19 | `ULoopboundGuardTest` — lockstep pin for the shared loopbound guard shape (`util/adigatorLoopboundGuard`, #181): what the emitter template prints, the recognizer regex matches with `{name, bound}` tokens (consumers: `adigatorForInitialize` emit, `adigatorPrintTempFiles` drop/rediff, `adigatorParseTape` slim keep-always); user-assert lookalikes (non-numeric bound, wrong operator, missing semicolon) must NOT match — they take the fail-loud `adigator:loopbound:rediff` path. util/-only path fixture by design. | REQ-T-02 (loopbound) |
| TS-U-20 | *(planned, R31 — issue #192, ADR-0030)* `UBuildCSCTest` — the `adigatorBuildCSC` canonicalizer: CSC invariants (monotone `ColPtr`, `ColPtr(1)==1`, `ColPtr(end)==Nnz+1`, strictly-increasing per-column `RowIdx`, in-range/unique locations, empty columns as adjacent equal pointers), identity-permutation detection on natively-ordered input, non-identity constant-gather permutation correctness, duplicate/out-of-range rejection, uint32 range-guard fallback, and the host helpers (`adigatorCSCToLocs`/`adigatorCSCToSparse`) round-tripping. | REQ-T-03 |

### 2.2 Integration tests — `tests/integration` (TS-I)

Generate derivative files into `tempdir` via the real pipeline, evaluate,
and compare. Run on every pull request (slower, still base MATLAB).

| ID | Test | Verifies |
|----|------|----------|
| TS-I-01 | `IShapeMatrixTest` — the central dimension test. Hand-written cases (not `TestParameter`-parameterized) spanning input shape {1×1, n×1, 1×n, n×m} × output shape {1×1, m×1, 1×m, r×c} × density {dense, structurally sparse} × derivative {jacobian, gradient, hessian}. Asserts (a) output shape per the conventions table, (b) every element against dense FD, and (c) on the matrix Jacobian/Hessian cases, that the exported `JacobianStructure`/`HessianStructure` (+ `*Locs`) have the derivative's size and are a **sparsity superset** with a matching Locs↔Structure pattern — the B23 class (complemented by the specific B23 guard in TS-I-12). The B7/B8/B9/B10 cases are `KnownIssue`-tagged and self-healing (detect the buggy outcome → `assumeFail`; otherwise run the trailing assertions as guards); B7–B10 are now fixed (`ANALYSIS.md` §1.5), so they run as guards. **Caveat until the tag is removed:** a *re-introduced* B7–B10 regression would re-trigger the `assumeFail` and report as *filtered*, not *failed* — so these are weaker than a true regression guard until the verified-cleanup pass drops the tag and the `assumeFail` scaffolding. | REQ-C-04, REQ-T-01, REQ-T-02, REQ-T-03 |
| TS-I-02 | `IEmbedModesTest` — for each fixture function (incl. one with an integer-valued constant matrix, one with subfunctions, one with a rolled loop): generate with `embed_mode` 'c', 'l', 'i'; assert numeric equality across modes, absence of `global`/`load(` in 'l'/'i' text, absence of `.mat` for 'i'. | REQ-T-04, REQ-C-05/06/07 end-to-end |
| TS-I-03 | `IReproTest` — regenerate twice, compare modulo timestamp lines; `overwrite=0` refusal; `opts.path` placement and calling-dir cleanliness. | REQ-T-06 |
| TS-I-04 | *(planned)* `ISecondDerivTest` — gradient+Hessian through `adigatorGenHesFile` for the `logsumexp` and `gapfun` fixtures, checked against **analytic** Hessians (an FD-independent enhancement). Hessian correctness is already guarded without it: TS-I-01 (shape + exported structure + FD), TS-I-12 (`HessianLocs`), TS-I-13/14/15, and the CasADi oracle TS-S-05. | REQ-T-01, REQ-C-04 |
| TS-I-05 | `ILevelSelectTest` — the `DER_LEVELS` output-selection option (roadmap R7a, issue #21; ADR-0005): wrapper signature trimmed to the requested levels (`nargout`), each emitted output numerically identical to the full-generation counterpart, the gradient intermediate of a Grd→Hes chain stays `[Grd,Fun]`, the type/range/top-level validation guards, and composition with the embedded pipeline (mode `l`). | REQ-T-02 |
| TS-I-06 | `IEmbedSlimTest` — the `slim_embed` driver end-to-end (roadmap R7b/R7c, issue #21; ADR-0006): generating a structurally sparse Jacobian in coderload mode with vs. without `slim_embed`, asserting the slimmed derivative code drops the unread `_location` metadata, the pruned data is no larger, the numeric result is unchanged (coder-gated runtime check), that the R7c union-copy peephole in the path leaves the result numerically identical in both coderload and inline modes, that the peephole resolves the real (unpruned) `<func>.Gator<D>Data` index tables and parses real generated code without error (the `loadGatorData` layout integration), and that classic mode is a byte-for-byte no-op. | REQ-T-04 |
| TS-I-07 | `IPruneShrinkTest` — wraps the license-free core `tests/offline/prune_shrink_offline_checks.m` (issue #21; ADR-0010), which runs the real `adigatorReferencedIndex` + `prune_adigator_mat` (char/regexp, Octave- and MATLAB-runnable) on hand-written generated-derivative snippets and on the committed `slim1` fixture: per-function `Gator<d>Data.Index<n>` token mapping, the boilerplate table-only reference, comment mentions ignored, conservative keep-all on a dynamic field `Gator<d>Data.(v)` or aliased bare table, and that the prune drops the unread `Index*` (the fixture's orphan `Index7`) while the unshrunk fallback preserves a referenced-but-unindexed table (no zero-field `coder.const(struct())`). | REQ-C-05 (issue #21, ADR-0010) |
| TS-I-08 | `IPeepholeDriverTest` — positive assertion that the R7c union-copy peephole fires **through the real `adigatorSlimEmbeddedDeriv` driver** (issue #44 item 2 / roadmap R10(b); ANALYSIS §2.3(6)). Drives a committed, structurally faithful, genuinely-runnable **synthetic** fixture (`tests/fixtures/collapse/cf_ADiGatorJac.m` + `cf_Jac.m`, the identity `y = x`) — synthetic because adigator's emitter does not produce the ordered-identity *full* fill the peephole collapses (real overmaps are strict partial fills; see ANALYSIS §2.3(6)), so without this every other test would pass even if the driver's peephole call were silently removed. Asserts `info.collapsed >= 1`, that the authoritative rewrite replaced the `zeros`+scatter pair with a `reshape` on disk, and that the driver's numeric round-trip cross-check ran and agreed (`info.checked`). | REQ-T-04 (issue #44 item 2) |
| TS-I-09 | `IEmbedSlimRolledTest` — R10(a) end-to-end (issue #44 item 1): the `slim_embed` driver slices a **multi-subfunction** generated file containing a **rolled `for…end`** (`unroll=0`), which `adigatorSlimDerivFile` previously bailed on. Generates a 3-subfunction Jacobian whose middle subfunction sums via a rolled loop, in coderload mode with vs. without `slim_embed`, and asserts (a) the slice fired across the rolled file — the unread `_location` metadata is gone (proof the conservative bail is lifted, not just a no-op), and (b) the slimmed derivative is numerically identical (`AbsTol 0`) to the unslimmed baseline and equal to the analytic `diag(2x+3)` (coder-gated runtime check). | REQ-T-04 (issue #44 item 1) |
| TS-I-10 | *(planned, R22 — issue #85, ADR-0020)* `INthDerivTest` — the `'nth-derivative'` DerType end-to-end: for a scalar polynomial with known n-th derivatives, generate order `k` for the staged operand classes (scalar/scalar → scalar-var → scalar-fn-of-vector-var → vector → matrix), and assert (a) values vs the analytic n-th derivative + FD, and (b) the `[M·Nᵏ⁻¹ × N]` fold shape + element placement (C-1), reducing to Jacobian at k=1 and vector-Hessian at k=2, and (c) the Decision-6 host utilities — `dvp(D,V)` contracts one order (a directional-derivative / Taylor-step reconstruction agrees with direct evaluation) and `unfold(D)` ↔ the flat fold is lossless. Staged as R22 builds each slice. | REQ-T-01, REQ-T-02 |
| TS-I-11 | *(planned, R24 — issue #83, ADR-0021)* `ISplitDataTest` — the inline `split_data` two-file form: generate derivative + data as separate source files and assert the C-4 invariants hold in **both** (no `global`/`load`/`.mat`/`coder.load`), the result is numerically identical to the merged-inline and coderload/classic baselines, and that requesting `embed_mode='l'` emits the one-time deprecation warning. | REQ-T-04 |
| TS-I-12 | `IOutputModesTest` — the output-form modes (R5 + R25/#84, ADR-0022): `jac_output='nonzeros'` returns the Jacobian nonzero vector + `output.JacobianLocs` with no dense projection; `adigatorGenJtVFile` computes `Jᵀv`; and (R25) `der_output='nonzeros'` returns the **Hessian** nonzero vector in `output.HessianLocs` order for scalar **and** `m>1` vector functions, reconstructing the dense Hessian to FD tolerance. Pins **decision b** (`jacOutputDoesNotFlipHessian` — `jac_output` is level-1-only, never flips the Hessian) and the forward-gradient `[Grd, Fun]` name convention. | REQ-T-11, REQ-T-02 |
| TS-I-13 | `IConstStructFieldTest` — regression guard for **B17** (ANALYSIS §1.3c): a numeric field of a **constant struct** assigned in the function body must generate and match FD (a spurious `.f` formerly produced silent-broken codegen). | REQ-T-01 |
| TS-I-14 | `IConstCellFieldTest` — regression guard for **B22** (the constant-**cell** analog of B17): a numeric element of a constant cell assigned in the body generates and matches FD (classic path). | REQ-T-01 |
| TS-I-15 | `ICondAuxParamTest` — regression guard for **B18**: an `if` whose condition is arithmetic on constant/aux **struct-parameter fields** generates and matches FD on both branches (no longer reproduces — resolved by R8 struct-input support; guard only). | REQ-T-01 |
| TS-I-16 | `ISymbolicIndexTest` — **B19 / B20** actionable-error guard (ADR-0024): data-dependent / symbolic indexing (a `while`-counter or aux-valued subscript) raises an **actionable** error naming the construct and the logical-weight-sum rewrite — never a wrong derivative (REVIEW_CONTEXT principle 1); covers the `subsref`/`subsasgn` sites **and** the `sparse()`/`diag()` sites (#121 — formerly cryptic, id-less upstream errors); also scopes the B19 `if`-guarded over-approximation residual (#108). | REQ-T-07 |
| TS-I-17 | `IEmbedUnsupportedTest` — the **ADR-0023 rev 2026-07-04** embed-mode source-scan gate (B21 `load` / B22-in-embed cells): embed generation **warns** (`adigator:embed:unsupportedConstruct`) on a user's cells / `load` / `global`, emits the construct **verbatim**, and still generates — with the embed Jacobian numerically identical to classic (AbsTol 0) — while classic mode stays silent and a clean function warns not at all. | REQ-T-04 |
| TS-I-18 | `IRevGradTest` — `adigatorGenRevGradFile` (roadmap R4, ANALYSIS §3.4): reverse-mode adjoint gradients of scalar costs (log-sum-exp, least-squares with mtimes, structural ops with duplicate gather / scatter / concat, unrolled-loop variable reuse) vs analytic + FD; the scope guards (two derivative inputs, vector output, rolled loop, unsupported op, matrix `/`); and the fail-fast overwrite + forward-intermediate cleanup (#121-M6). | REQ-T-01 (reverse mode) |
| TS-I-19 | `IRevEmbedTest` — the `'gradient-reverse'` DerType through `adigatorGenDerFile_embedded` (R16b): cross-mode `c`/`l`/`i` equality + the C-4 invariants for the reverse gradient, in both the indexed and the dense zero-ROM regimes. | REQ-T-04 (reverse embed) |
| TS-I-20 | `ILoopboundTest` — the `LOOPBOUND` runtime-loop-bound option (R3, #6 Tier 1): generate at `Nmax`, evaluate for `n <= Nmax` without regeneration with exact structural zeros beyond `n`, the padding-benign contract and the `assert(n <= Nmax)` guard. | REQ-T-02 (loopbound) |
| TS-I-21 | `INDParamTest` — the N-D parameter veneer (R2, #11 Level 2): `adigatorCreateAuxInput([m n K])` folded to 2-D, `B(:,:,k)` slicing as affine column windows, Jacobian vs analytic + FD, 3-D and folded-2-D acceptance. | REQ-T-01 (N-D params) |
| TS-I-22 | `IStructInputTest` — struct inputs carrying the VOD / aux data (R8, #24 scope A): flat + nested-struct Hessian, vector-function Jacobian, and `c`/`l`/`i` cross-mode equality. | REQ-T-01, REQ-C-04 (struct inputs) |
| TS-I-23 | `IAllocationTest` — the allocation-over-time headline example (R1): per-(actuator, time) terms vectorized over the `N*K` product fold, assembly wrappers for both reduction directions, one generated file verified across several `(N,K)` pairs. | REQ-T-01, REQ-T-08 (allocation) |
| TS-I-24 | `IConcatLoopLiteralTest` — regression guard for **B28** (ANALYSIS §1.3f, #168): a numeric literal in a `vertcat` inside a **rolled-loop print context** (an `unroll=0` `for`, or a subfunction printed as a loop) must generate without a spurious `.f` and match FD — a formerly broken-file bug; a horzcat control guards the vertcat-vs-horzcat asymmetry the fix relies on. | REQ-T-01 |
| TS-I-25 | *(planned, R31 — issue #192, ADR-0030)* `ICscOutputTest` — the CSC contract end-to-end: `der_output='csc'` returns the `Nnz×1` value vector whose CSC-metadata reconstruction exactly equals the matrix-mode derivative; classic/inline cross-mode CSC values identical; FD/analytic agreement; shape coverage per the #192 acceptance (sparse+dense Jacobians, `[n,1]` gradients, scalar + vector-fold Hessians, remap cases, empty columns/derivatives, single-row/column, loopbound at `n<Nmax` with padded structural zeros); asserts the `adigatorBuildCSC` permutation is **identity** (`isIdentity == true`) on representative Jacobian/gradient/Hessian cases — a tripwire so a future `nzlocs` ordering change cannot silently introduce the constant gather; generated-code checks (no `sparse(`, no dense scatter, no runtime sort/search; metadata not returned per call). | REQ-T-03, REQ-T-11, REQ-T-01 |

### 2.3 System / validation tests — `tests/system` (TS-S)

Validate the tool against user-level intent. Run nightly and on `master`
merges; license-gated jobs skip cleanly when products are unavailable.

| ID | Test | Validates | Gate |
|----|------|-----------|------|
| TS-S-01 | `SExamplesTest` — run the curated examples headless (seeded RNG); assert completion and spot values (arrowhead/polydatafit vs FD, pipg/structinput/brusselator). Plus a **completeness guard** (`discoveryCoversEveryExample`, issue #69): the shared `tests/helpers/discoverExamples` (a mechanical `examples/**/main*.m` glob + manifest of non-`main` entries / per-example requirements — the same source of truth `examples/runAllExamples` sweeps) must agree with this test's curated + smoke-acknowledged lists, so a newly added example can't be silently un-run. | REQ-T-08, REQ-T-01 | Optimization Toolbox for the solver examples; others base MATLAB |
| TS-S-02 | `SCodegenTest` — **Embedded Coder (ERT)** `codegen -config:lib,ecoder` (and MEX) the 'i'-mode generated gradient, run MEX vs MATLAB vs analytic equality. The embeddable static-lib build goes through ERT (the strict target — #80 R20b, plain Coder was masking ERT-only gaps); the MEX build stays MEX for the runtime-equivalence check. Two points: the default (full, unshrunk embedded data) and a `slim_embed=true` point (issue #21) that puts the slice-before-prune shrunk data through the same round-trip, proving the dropped `Index7` leaves the compiled result unchanged. The equivalence check runs the hand-rolled `codegen`+`verifyEqual` path today; migrating it to `matlabtest.coder.TestCase` where MATLAB Test is licensed (R2023a+) is *(planned, R15 — ADR-0014, issue #64; no `matlabtest` asset exists in the repo yet)*. The ERT lib build is guarded on the Embedded Coder license, so a Coder-only runner still verifies the MEX equivalence (REQ-T-05) at its true floor; only the ERT lib build (REQ-T-10) needs Embedded Coder. | REQ-T-05 | MATLAB Coder (MEX equivalence); Embedded Coder for the ERT lib build; MATLAB Test (preferred path) |
| TS-S-03 | `SReleaseMatrixTest` — full TS-U + TS-I suite on MATLAB releases {R2022a (floor), latest}. | REQ-T-01..07 on supported releases | nightly only |
| TS-S-04 | `MCSmokeTest` + `tests/montecarlo/mcCampaign` — randomized-function campaign over the generators (affine / quadratic / shape-fuzz → expression-tree) checked by the tolerance-free oracles (cross-mode exact, known-derivative, sparsity-superset, **param-delivery invariance** — `oracleParamDeliveryInvariance`, the R27/#103 input-topology backstop for the B17/B22 class; FD secondary), plus, where MATLAB Coder is available, a **sampled** `oracleCodegenEquivalence` (**born ERT**, hand-rolled `codegen`+compare) that builds the embedded `'i'` wrapper through Embedded Coder (`coder.config('lib','ecoder',true)`, proving strict-target codegen) plus a MEX and asserts compiled-C ≡ MATLAB over `c.x0` + a few perturbations (ADR-0014, issue #64; `MCSmokeTest.codegenEquivalenceIsClean` runs a tiny deterministic set, the full sampled sweep is a release-checklist `mcCampaign` including this oracle). Migrating it to the `matlabtest.coder.TestCase` supported API + `GeneratedCodeCoveragePlugin` generated-C coverage is *(planned, R15 — needs MATLAB Test R2023a+)*. Failures feed delta-debug shrinking and automatic fixture promotion. `MCSmokeTest` runs a fixed-seed, fixed-iteration subset in the extended (per-merge) suite; the unbounded campaign is an opt-in local / release-checklist run, and the codegen-equivalence oracle (sampled, license-gated) runs only in that fuller run. *(Issue #38, ADR-0007, roadmap R9 / R14 / R15; codegen oracle issue #64, ADR-0014.)* | REQ-T-09 (cross-validates REQ-T-01..05 at scale) | base MATLAB (Coder / MATLAB Test oracles skip-clean) |
| TS-S-06 | `SRolledErtCodegenTest` — **ERT regression guard** (#80 Gap B / Path A): the rolled (`unroll=0`) `scostfun` gradient + Hessian must codegen under strict Embedded Coder (`coder.config('lib','ecoder',true)`, `GenCodeOnly`) at **n=32** — the size where identical index tables get de-duplicated, the regime where the old `S.x.IndexN = S.x.IndexM` static-data self-alias broke ERT ("field added after struct read"). Pins ERT *acceptance* end-to-end (the unit test `UEmbedMfileTest` pins only the emitted form). Coder + Embedded Coder gated; skips clean without the licenses. | REQ-T-10 | MATLAB Coder + Embedded Coder (skip-clean) |
| TS-S-05 | `SCasadiOracleTest` — **independent-oracle** cross-check: ADiGator's generated derivative vs **CasADi** (symbolic expression graph — a method independent of source transformation) on the *same unmodified* source m-file, compared on reconstructed dense values. Battery: `vvecfun/jacobian`, `scostfun/{gradient, gradient-reverse, hessian}`, `vcostfun/gradient` (`vfun` omitted — not `SX`-consumable; covered by `vvecfun`). Tool-gated: skips cleanly when CasADi is absent; CasADi binaries are not committed (uses whatever is on the MATLAB path, or `CASADI_DIR` if set). *(Issue #87, ADR-0018; the independent ground truth for the #80 v2 engine work.)* | REQ-T-09 (independent cross-validation of REQ-T-01..05) | base MATLAB; CasADi (skip-clean) |
| TS-S-07 | `SDerivShowcaseTest` — pins `bench/derivShowcase.m` (R17a): the all-axes MATLAB-level complexity/correctness grid (embed_mode × slim × unroll × DerType) that emits `bench/SHOWCASE.md`, with each cell gated for correctness against the analytic derivative. | REQ-T-09 (showcase, R17a) | base MATLAB |

| Requirement | Verified / validated by |
|-------------|-------------------------|
| REQ-T-01 | TS-I-01, TS-S-01, TS-I-13, TS-I-14, TS-I-15; TS-I-04 *(planned)*, TS-I-10 *(planned, R22)*, TS-I-25 *(planned, R31)* |
| REQ-T-02 | TS-I-01, TS-I-05, TS-I-12, TS-I-20, TS-U-19 (loopbound); TS-I-10 *(planned, R22)* |
| REQ-T-03 | TS-I-01; TS-U-20, TS-I-25 *(planned, R31)* |
| REQ-T-04 | TS-I-02, TS-I-06, TS-I-08, TS-I-09, TS-I-17; TS-I-11 *(planned, R24)* |
| REQ-T-05 | TS-S-02; cross-validated at scale by the TS-S-04 `oracleCodegenEquivalence` (born-ERT, sampled, hand-rolled `codegen`+compare; ADR-0014). The `matlabtest.coder` supported-API migration is *(planned, R15)* |
| REQ-T-06 | TS-I-03 |
| REQ-T-07 | TS-U-08, TS-I-16 |
| REQ-T-08 | TS-S-01 |
| REQ-T-09 | TS-S-04, TS-S-05 |
| REQ-T-10 | TS-S-06 (rolled-form ERT acceptance, #89); TS-S-02 migrated to the ERT `ecoder` target (#92); TS-S-04 (MC oracle) spec'd born-ERT (ADR-0014 amended, R20c; oracle implementation is R15); issue #80 |
| REQ-T-11 | TS-I-12 (Hessian-nonzeros/`HessianLocs` + the `Grd` name fix, R25/#99); TS-I-25 *(planned, R31 — CSC respelling, ADR-0030)*; phase-2 support-matrix + per-level selection *(planned, R25)* |
| REQ-C-01 | TS-U-01 |
| REQ-C-02 | TS-U-02 |
| REQ-C-03 | TS-U-03 |
| REQ-C-04 | TS-I-01; TS-I-04 *(planned)* |
| REQ-C-05 | TS-U-04, TS-I-02, TS-I-07 |
| REQ-C-06 | TS-U-05, TS-I-02 |
| REQ-C-07 | TS-U-06, TS-I-02 |
| REQ-C-08 | TS-U-07 |
| REQ-C-09 | TS-U-08 |
| REQ-C-10 | TS-U-09 |
| REQ-C-11 | TS-U-16 |

Bug-to-test mapping (test ↔ `docs/ANALYSIS.md`): B1→TS-U-04, B2→TS-U-05,
B3/B4→TS-U-06, B7/B8/B9/B10→TS-I-01, B11/B12→TS-U-07, B13→TS-U-08;
B17→TS-I-13, B18→TS-I-15, B19/B20→TS-I-16, B21+B22(embed)→TS-I-17,
B22(classic)→TS-I-14. All of these are now fixed / mitigated / won't-fix / documented-limitation
(`ANALYSIS.md` §1.5) — the B19 `if`-guarded over-approximation residual excepted
(#108); the tests are the regression guards rather than known-issue tripwires
(TS-I-01's B7–B10 cases self-heal — see above).

### 2.4a Reuse of existing validation assets

The suites are built on what the repository already validates with, rather
than parallel new machinery:

| Existing asset | Reused as |
|----------------|-----------|
| FD harness in `unit_tests/test_unarymath_rules.m` (perturbation, tolerance, singularity exclusion) | The unary-rule points/tolerance live in TS-U-01; a shared central-difference Jacobian/Hessian oracle `tests/helpers/fdcheck.m` is used by TS-U-02/03 (TS-U-01 and TS-I-01 keep equivalent inline FD). |
| `examples/jacobians/arrowhead/main.m` (ADiGator vs FD and compressed FD) | TS-S-01 case with the existing comparison promoted from printed output to an assertion; small `N` for PR-speed, large `N` nightly. |
| `examples/jacobians/polydatafit/main.m` (FD comparison) | TS-S-01 assertion case. |
| `examples/stiffodes/brusselator/main.m` (FD comparison) | TS-S-01 assertion case. |
| `examples/hessians/logsumexp`, `examples/optimization/pipg` (`gapfun` + analytic structure), brachistochrone | Fixture functions for TS-I-01/02/04 (known analytic gradients/Hessians, struct inputs, aux inputs, subfunctions). |
| `util/adigatorUncompressJac.m` / `adigatorColor.m` round trip | Compression sanity case inside TS-I-01. |

New fixtures are only written where no example covers the case — chiefly
the degenerate shapes in TS-I-01 (row-vector inputs, matrix-of-scalar,
vector-output Hessians with m≠n) that the bug analysis showed are exactly
the untested paths.

---

## 3. CI implementation (GitHub Actions)

### 3.1 Workflows

Every GitHub Actions *job* runs on a fresh runner and pays the MATLAB
install/license handshake again, while *steps* within a job share one
install. The PR pipeline is therefore a single job with sequential steps
(lint is cheap and fails fast before the test steps), and parallel jobs are
reserved for the nightly workflow where the product set or release actually
differs.

**`.github/workflows/ci.yml`** — on `push` to `master` and all PRs:

```yaml
jobs:
  test:                       # one MATLAB install for the whole PR gate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: matlab-actions/setup-matlab@v2
        with: { release: latest, cache: true }
      - name: Lint (TS-U-09)
        uses: matlab-actions/run-command@v2
        with: { command: "addpath(genpath('tests')); ci_lint" }
      - name: Unit tests (TS-U-01..08)
        uses: matlab-actions/run-tests@v2
        with:
          select-by-folder: tests/unit
          test-results-junit: results/unit.xml
          code-coverage-cobertura: results/coverage-unit.xml
      - name: Integration tests (TS-I-01..04)
        if: success()
        uses: matlab-actions/run-tests@v2
        with:
          select-by-folder: tests/integration
          test-results-junit: results/integration.xml
          code-coverage-cobertura: results/coverage-integration.xml
      - uses: actions/upload-artifact@v4
        if: always()           # JUnit+coverage always; generated files on failure
        with: { name: ci-results, path: results }
```

(`cache: true` additionally caches the MATLAB installation across runs of
the same release, cutting the remaining setup time.)

**Docs-only skip.** The `test` job runs on every pull request — so the
required check always reports — but its first step diffs the PR against its
base and, when *every* changed path is under `docs/` or ends in `.md`, skips
the MATLAB setup + lint + test + coverage steps. The job still succeeds, so
the required check stays green without paying the (dominant) MATLAB install,
and a docs-only diff cannot change any lint/test outcome anyway. The filter is
conservative by direction: any non-docs path (including `.github/`, `tests/`,
`*.m`) runs the full gate, and `push` events always run — an unnecessary full
run is harmless, skipping when code changed is not. (A PR that edits the
workflow itself therefore runs the full gate, since `ci.yml` is not a docs
path.)

**User-guide PDF (`docs-pdf.yml`).** A separate, non-gating workflow compiles
the LaTeX user guide (`docs/userguide/`, via a TeXLive container running
the `makepdf.sh` pdflatex/bibtex sequence) and commits the regenerated
`docs/userguide/ADiGatorUserGuide.pdf`. It is path-filtered to `docs/userguide/**`,
so it only runs when the guide sources change — a plain `paths:` filter
suffices here precisely because it is **not** a required check (the in-job diff
trick is only needed for the required `test` job). To avoid pushing to the
protected `master` branch (which would require a GitHub App / PAT / bypass), it
runs on pull requests and commits the rebuilt PDF **back to the PR branch**
using the built-in `GITHUB_TOKEN`, so the PDF merges into `master` through the
normal PR flow; the job is restricted to same-repo PRs (a fork PR's head branch
is not in this repo and its token is read-only, so it is skipped cleanly rather
than failing). The build is reproducible (`SOURCE_DATE_EPOCH` /
`FORCE_SOURCE_DATE` pin pdftex's timestamps), so an unchanged source yields a
byte-identical PDF and the commit step no-ops — only a genuine guide-source
change produces a PDF commit. Because a `GITHUB_TOKEN` commit does not retrigger
workflows, that one PDF commit leaves the `test` check stale on the new head;
re-run `test` before merging if branch protection requires it.

**`.github/workflows/extended.yml`** — runs the heavy suites on every push
to `embedded` (i.e., on merge) and on manual dispatch.

*Implementation note (supersedes the cron design below):* the plan
originally scheduled these suites nightly. The cron was dropped at
implementation time: its only unique value over push triggers is drift
detection on an *idle* repository (new `latest` MATLAB releases,
runner-image changes, action deprecations), GitHub fires cron only from
the default branch, and this repository's activity pattern makes
push-on-merge coverage sufficient. Re-add a `schedule:` block on the
default branch if idle-repo drift detection becomes wanted. References to
"nightly" elsewhere in this plan should be read as "extended suite (per
merge)".
Jobs are split here only along axes that genuinely need separate installs:
- release matrix `{R2022a, latest}` re-running unit+integration (TS-S-03) —
  different MATLAB versions cannot share an install;
- one job with `products: Optimization_Toolbox MATLAB_Coder` running the
  examples (TS-S-01) and codegen (TS-S-02) steps sequentially on a single
  install; steps check product availability (`license('test',...)`) and
  `assumeFail` → skip rather than error when a product is missing, so the
  same workflow runs on licenses without Coder.
Separately (no extra install axis), a base-MATLAB step in the extended
workflow runs `MCSmokeTest` (TS-S-04) by selecting the `tests/montecarlo`
folder — the fixed-seed, fixed-iteration Monte-Carlo smoke (ADR-0007). It runs
here, **not** in the PR gate or the `ci_local` folder sweep
(`tests/{unit,integration,system}`), because random-seed campaigns must not
gate; `MCSmokeTest` lives under `tests/montecarlo/` precisely so those two
selectors skip it. The unbounded campaign (`tests/montecarlo/mcCampaign`) stays
an opt-in local / release run.

### 3.2 Licensing and runners

- Public repo: `setup-matlab` provides licensed MATLAB on GitHub-hosted
  runners with no further setup (batch licensing is implicit for public
  repos). Private repo: create a MathWorks batch-licensing token and add
  it as the `MLM_LICENSE_TOKEN` repository secret; reference it via the
  `MLM_LICENSE_TOKEN` env on each MATLAB step. Coder/toolbox products must
  be on the license tied to the token.
- If the token cannot cover Coder, run TS-S-02 on a self-hosted runner with
  a local install, kept in the nightly workflow only.
- *Observed on hosted public-repo runners:* requesting `products:
  MATLAB_Coder` does not yield `codegen` (`license('test','MATLAB_Coder')`
  is false, `which codegen` empty), while `coder.load`/`coder.const`
  resolve in base MATLAB regardless. Consequently TS-I-02's numeric
  cross-mode checks run everywhere, but TS-S-02 stays assumption-filtered
  until run on a runner whose license actually includes Coder (MLM token
  or self-hosted).

### 3.3 Conventions and policies

- **Test layout:** new `tests/{unit,integration,system}` tree using
  `matlab.unittest` classes; existing `unit_tests/test_unarymath_rules.m`
  is ported into TS-U-01 (keep the FD harness, wrap in test methods).
  Shared fixtures (small user functions, golden patch files) under
  `tests/fixtures`. All generation goes to `TestCase`-managed temp folders
  via `opts.path` so the repo tree stays clean.
- **Known-issue policy:** tests for documented unfixed bugs carry the tag
  `KnownIssue` and call `assumeFail("Known issue Bn, see docs/ANALYSIS.md")`
  so they appear as *filtered* (visible, counted, non-blocking). When the fix
  lands the test becomes the regression guard — either by deleting the
  `assumeFail` in the fix PR, or via the self-healing pattern (the `assumeFail`
  fires only on the buggy outcome, so it stops firing once fixed and the
  trailing assertions run; see `IShapeMatrixTest`). A stale-tag detector that
  fails CI when a `KnownIssue` test unexpectedly *passes* is **planned, not yet
  implemented** in `ci_lint`; until it lands, dropping the tag after a fix is a
  manual cleanup step (the self-healing tests are the current example awaiting
  that pass).
- **Gating:** `lint` + `unit` + `integration` are required checks for PRs.
  Nightly jobs (`examples`, `codegen`, release matrix) are informational
  for the first month, then promoted to required-on-master once stable.
- **Determinism:** seed all RNG (`rng(0)`) in tests and examples; FD
  tolerances chosen per derivative order as in REQ-T-01; no test depends
  on `cd`.
- **Artifacts:** JUnit XML + Cobertura coverage on every run; on failure,
  upload the generated `.m`/`.mat` files for offline diagnosis.
- **Local runner:** a `tests/ci_local.m` entry point runs lint + unit +
  integration (and, license permitting, the nightly suites) in the
  developer's existing MATLAB session — the license-free way to get the CI
  verdict before pushing; optionally wired as a git pre-push hook.

### 3.4 Phased rollout

| Phase | Content | Exit criterion |
|-------|---------|----------------|
| 0 | `ci.yml` with `lint` + TS-U-01 (ported existing test) + one smoke integration case (`gapfun` jacobian, mode 'c', FD check). | Pipeline green on a trivial PR; licensing path proven. |
| 1 | TS-I-01 shape matrix + TS-U-04..08, with `KnownIssue` tags for B1-B13. | All documented bugs pinned by a failing-but-filtered test. |
| 2 | Bug-fix PRs flip their `KnownIssue` tests to hard assertions (B1, B7 first — highest severity). TS-I-02/03; TS-U-06 golden files; TS-U-02/03 FD rule tests. | No remaining `KnownIssue` tags for fixed bugs; integration required check enabled. |
| 3 | `nightly.yml`: examples, codegen, release matrix. | One week of green nightlies; promote to required-on-master. |
| 4 | Coverage ratchet (fail if coverage of `embedding/` + `util/` drops), warning-count ratchet in lint. | Ratchet files committed and enforced. |

**Status:** Phases 1–2 and 4 are substantially landed — the documented bugs
B1–B22 are fixed/mitigated/won't-fix/documented-limitation (`docs/ANALYSIS.md` §1.5; the
B19 `if`-guarded residual, #108, excepted) and their tests are
regression guards, and the lint/coverage ratchets are implemented
(`tests/ci_lint.m`, `tests/ci_coverage.m`). Phase 2's exit criterion ("no
remaining `KnownIssue` tags for fixed bugs") is met except for the self-healing
B7–B10 cases in `IShapeMatrixTest`, whose tag removal is a verified-cleanup
follow-up.

### 3.5 Out of scope (explicitly)

- Performance benchmarking of generated code (worth a later, separate
  workflow with stored baselines; too noisy for gating now).
- Windows/macOS runners — the toolbox is OS-agnostic MATLAB code; a single
  Linux runner suffices until an OS-specific issue appears (the historical
  filesep issues are covered by tests running through `fullfile`).
- Testing the vectorized (GPOPS-II) mode beyond what the examples cover.
