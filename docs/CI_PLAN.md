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
- Known bugs documented in `docs/ANALYSIS.md` (B1-B15) must be *pinned* by
  tests. The `KnownIssue` tag + `assumeFail` mechanism (a test that detects the
  buggy behaviour and reports as filtered until the fix lands, then runs its
  trailing assertions as a regression guard) is the policy for *future* bugs.
  As of `docs/ANALYSIS.md` §1.5, **all of B1–B15 are fixed / mitigated / won't-
  fix**, so the only remaining `KnownIssue`-tagged tests are the self-healing
  B7–B10 cases in `IShapeMatrixTest`, which already run as guards (the tag
  removal is a verified-cleanup follow-up, not an open bug).

---

## 1. Requirements (left leg)

### 1.1 Tool-level requirements (REQ-T)

| ID | Requirement | Acceptance criterion |
|----|-------------|----------------------|
| REQ-T-01 | **Derivative correctness.** Generated derivative files shall produce first and second derivatives that match a reference (analytic where available, central finite differences otherwise) for all supported operations. | Relative error ≤ 1e-6 (1st order) / 1e-4 (2nd order, FD reference) on all test points away from singularities. |
| REQ-T-02 | **Output conventions.** Wrapper outputs shall conform to `adigatorDerivativeConventions.m`: gradient of scalar f: Rⁿ→R is n×1; Jacobian of f: Rⁿ→Rᵐ is m×n; Hessian of scalar f is n×n; vector-function Hessian is [m·n × n] with row = (x₁−1)·m + y; generalized shapes per the conventions table. | Asserted shape and element placement for every (input shape × output shape × density) combination. |
| REQ-T-03 | **Sparsity metadata consistency.** `output.JacobianStructure` / `output.HessianStructure` shall be a superset of the numerically nonzero pattern and consistent with the wrapper's element placement. | `find(abs(J) > 0) ⊆ find(Structure)` at random test points; same indexing convention as the wrapper output. |
| REQ-T-04 | **Embeddability.** With `embed_mode='l'` the generated code shall contain no `global` declarations and no runtime `load`; with `embed_mode='i'` additionally no `.mat` file and no `coder.load`. All three modes shall return numerically identical results. | Static text checks on generated files + cross-mode numeric equality (exact, same arithmetic). |
| REQ-T-05 | **Code-generation compatibility.** Files generated in modes 'l' and 'i' shall pass MATLAB Coder `codegen` (lib target) without errors and the MEX/lib shall reproduce MATLAB results. | `codegen` exit success; MEX output equals MATLAB output to 1e-12. License-gated. |
| REQ-T-06 | **Reproducibility.** Regeneration with identical inputs and options shall produce functionally identical files; `overwrite=0` shall refuse to clobber; user-specified `path` shall receive all generated artifacts and nothing shall be left in the calling directory. | Byte comparison modulo timestamps; file-location assertions. |
| REQ-T-07 | **Robustness / hygiene.** Invalid inputs and mid-transformation errors shall raise clean errors, restore the MATLAB path, close all file handles, and leave no stray globals. | `path()` before == after; `fopen('all')` empty delta; `who('global')` delta empty after failure injection. |
| REQ-T-08 | **Example health.** All shipped examples shall run headless without error (toolbox-gated where applicable). | Each example `main.m` completes; spot numeric checks. |
| REQ-T-09 | **Randomized robustness (V&V).** Over a seeded Monte-Carlo campaign of generated derivatives (randomized function bodies, input/output shapes, sizes, densities, embed modes), outputs shall satisfy the tolerance-free oracles (cross-mode exact equality, known-derivative-by-construction, sparsity-superset) and the hygiene invariants of REQ-T-07. *Non-gating* — the campaign is opt-in/local; any failing seed shall be reproducible and reducible to a deterministic regression fixture. *(Planned; phased build in `docs/ROADMAP.md` R9. Issue #38, ADR-0007.)* | Pinned-seed smoke reports zero failures; each discovered failure is minimized (`mcShrink`) and promoted (`mcPromote`) into the deterministic suite. |

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

---

## 2. Tests (right leg) and traceability

### 2.1 Unit tests — `tests/unit` (TS-U)

Fast, base-MATLAB only, no file generation beyond `tempdir`. Run on every
push and pull request.

| ID | Test | Verifies |
|----|------|----------|
| TS-U-01 | `URulesUnaryTest` — port of `unit_tests/test_unarymath_rules.m` to `matlab.unittest`, FD sweep per rule with singularity exclusion. | REQ-C-01 |
| TS-U-02 | `URulesBinaryTest` — same harness over binary ops with operand-shape matrix {scalar, row, col, matrix} × {scalar, row, col, matrix}. | REQ-C-02 |
| TS-U-03 | `UStructuralOpsTest` — small fixed functions exercising each structural op; assert `y.dX`, `y.dX_location`, `y.dX_size` against dense FD Jacobians. | REQ-C-03 |
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
| TS-U-15 | `USlimDerivFileTest` — the interprocedural field-slice `adigatorSlimDerivFile` (issue #44 item 1; ADR-0009): splitting a multi-subfunction generated `_ADiGator*` file into per-function blocks, the forward worklist that propagates a callee's demand from the result-struct fields the caller reads at a kept call site, the per-function closure-gated slice and whole-file reassembly (dead value chains / unread output fields dropped in every function), single-derivative-function delegation to `adigatorSlimDerivBody`, and the conservative whole-file bails (no demanded fields; any rolled `for…end` in a multi-subfunction file). Text-in / text-out on hand-written snippets. | #44 item 1 (ADR-0009) |

### 2.2 Integration tests — `tests/integration` (TS-I)

Generate derivative files into `tempdir` via the real pipeline, evaluate,
and compare. Run on every pull request (slower, still base MATLAB).

| ID | Test | Verifies |
|----|------|----------|
| TS-I-01 | `IShapeMatrixTest` — the central dimension test. Parameterized over input shape {1×1, n×1, 1×n, n×m} × output shape {1×1, m×1, 1×m, r×c} × density {dense, structurally sparse} × derivative {jacobian, gradient, hessian} × size regime {small, ≥250-element sparse-branch trigger}. Asserts (a) output shape per the conventions table, (b) every element against dense FD, (c) `JacobianStructure`/`HessianStructure` consistency. The B7/B8/B9/B10 cases are `KnownIssue`-tagged and self-healing (detect the buggy outcome → `assumeFail`; otherwise run the trailing assertions as guards); B7–B10 are now fixed (`ANALYSIS.md` §1.5), so they run as guards. **Caveat until the tag is removed:** a *re-introduced* B7–B10 regression would re-trigger the `assumeFail` and report as *filtered*, not *failed* — so these are weaker than a true regression guard until the verified-cleanup pass drops the tag and the `assumeFail` scaffolding. | REQ-C-04, REQ-T-01, REQ-T-02, REQ-T-03 |
| TS-I-02 | `IEmbedModesTest` — for each fixture function (incl. one with an integer-valued constant matrix, one with subfunctions, one with a rolled loop): generate with `embed_mode` 'c', 'l', 'i'; assert numeric equality across modes, absence of `global`/`load(` in 'l'/'i' text, absence of `.mat` for 'i'. | REQ-T-04, REQ-C-05/06/07 end-to-end |
| TS-I-03 | `IReproTest` — regenerate twice, compare modulo timestamp lines; `overwrite=0` refusal; `opts.path` placement and calling-dir cleanliness. | REQ-T-06 |
| TS-I-04 | `ISecondDerivTest` — gradient+Hessian through `adigatorGenHesFile` for the `logsumexp` and `gapfun` fixtures, checked against analytic Hessians. | REQ-T-01, REQ-C-04 |
| TS-I-05 | `ILevelSelectTest` — the `DER_LEVELS` output-selection option (roadmap R7a, issue #21; ADR-0005): wrapper signature trimmed to the requested levels (`nargout`), each emitted output numerically identical to the full-generation counterpart, the gradient intermediate of a Grd→Hes chain stays `[Grd,Fun]`, the type/range/top-level validation guards, and composition with the embedded pipeline (mode `l`). | REQ-T-02 |
| TS-I-06 | `IEmbedSlimTest` — the `slim_embed` driver end-to-end (roadmap R7b/R7c, issue #21; ADR-0006): generating a structurally sparse Jacobian in coderload mode with vs. without `slim_embed`, asserting the slimmed derivative code drops the unread `_location` metadata, the pruned data is no larger, the numeric result is unchanged (coder-gated runtime check), that the R7c union-copy peephole in the path leaves the result numerically identical in both coderload and inline modes, that the peephole resolves the real (unpruned) `<func>.Gator<D>Data` index tables and parses real generated code without error (the `loadGatorData` layout integration), and that classic mode is a byte-for-byte no-op. | REQ-T-04 |
| TS-I-07 | `IPruneShrinkTest` — wraps the license-free core `tests/offline/prune_shrink_offline_checks.m` (issue #21; ADR-0010), which runs the real `adigatorReferencedIndex` + `prune_adigator_mat` (char/regexp, Octave- and MATLAB-runnable) on hand-written generated-derivative snippets and on the committed `slim1` fixture: per-function `Gator<d>Data.Index<n>` token mapping, the boilerplate table-only reference, comment mentions ignored, conservative keep-all on a dynamic field `Gator<d>Data.(v)` or aliased bare table, and that the prune drops the unread `Index*` (the fixture's orphan `Index7`) while the unshrunk fallback preserves a referenced-but-unindexed table (no zero-field `coder.const(struct())`). | REQ-C-05 (issue #21, ADR-0010) |
| TS-I-08 | `IPeepholeDriverTest` — positive assertion that the R7c union-copy peephole fires **through the real `adigatorSlimEmbeddedDeriv` driver** (issue #44 item 2 / roadmap R10(b); ANALYSIS §2.3(6)). Drives a committed, structurally faithful, genuinely-runnable **synthetic** fixture (`tests/fixtures/collapse/cf_ADiGatorJac.m` + `cf_Jac.m`, the identity `y = x`) — synthetic because adigator's emitter does not produce the ordered-identity *full* fill the peephole collapses (real overmaps are strict partial fills; see ANALYSIS §2.3(6)), so without this every other test would pass even if the driver's peephole call were silently removed. Asserts `info.collapsed >= 1`, that the authoritative rewrite replaced the `zeros`+scatter pair with a `reshape` on disk, and that the driver's numeric round-trip cross-check ran and agreed (`info.checked`). | REQ-T-04 (issue #44 item 2) |

### 2.3 System / validation tests — `tests/system` (TS-S)

Validate the tool against user-level intent. Run nightly and on `master`
merges; license-gated jobs skip cleanly when products are unavailable.

| ID | Test | Validates | Gate |
|----|------|-----------|------|
| TS-S-01 | `SExamplesTest` — run each `examples/**/main*.m` headless (seeded RNG); assert completion and spot values (e.g. fsolve converges, pipg gap function derivatives match FD). | REQ-T-08, REQ-T-01 | Optimization Toolbox for the solver examples; others base MATLAB |
| TS-S-02 | `SCodegenTest` — `codegen -config:lib` (and MEX) the 'i'-mode generated gradient, run MEX vs MATLAB vs analytic equality. Two points: the default (full, unshrunk embedded data) and a `slim_embed=true` point (issue #21) that puts the slice-before-prune shrunk data through the same Coder round-trip, proving the dropped `Index7` leaves the compiled result unchanged. | REQ-T-05 | MATLAB Coder |
| TS-S-03 | `SReleaseMatrixTest` — full TS-U + TS-I suite on MATLAB releases {R2022a (floor), latest}. | REQ-T-01..07 on supported releases | nightly only |
| TS-S-04 | `MCSmokeTest` + `tests/montecarlo/mcCampaign` — randomized-function campaign over the generators (affine / quadratic / shape-fuzz → expression-tree) checked by the tolerance-free oracles (cross-mode exact, known-derivative, sparsity-superset; FD secondary), with delta-debug shrinking and automatic fixture promotion. `MCSmokeTest` runs a fixed-seed, fixed-iteration subset in the extended (per-merge) suite; the unbounded campaign is an opt-in local / release-checklist run. *(Issue #38, ADR-0007, roadmap R9.)* | REQ-T-09 (cross-validates REQ-T-01..04 at scale) | base MATLAB (Coder oracles skip-clean) |

### 2.4 Traceability matrix

| Requirement | Verified / validated by |
|-------------|-------------------------|
| REQ-T-01 | TS-I-01, TS-I-04, TS-S-01 |
| REQ-T-02 | TS-I-01, TS-I-05 |
| REQ-T-03 | TS-I-01 |
| REQ-T-04 | TS-I-02, TS-I-06, TS-I-08 |
| REQ-T-05 | TS-S-02 |
| REQ-T-06 | TS-I-03 |
| REQ-T-07 | TS-U-08 |
| REQ-T-08 | TS-S-01 |
| REQ-T-09 | TS-S-04 |
| REQ-C-01 | TS-U-01 |
| REQ-C-02 | TS-U-02 |
| REQ-C-03 | TS-U-03 |
| REQ-C-04 | TS-I-01, TS-I-04 |
| REQ-C-05 | TS-U-04, TS-I-02, TS-I-07 |
| REQ-C-06 | TS-U-05, TS-I-02 |
| REQ-C-07 | TS-U-06, TS-I-02 |
| REQ-C-08 | TS-U-07 |
| REQ-C-09 | TS-U-08 |
| REQ-C-10 | TS-U-09 |

Bug-to-test mapping (test ↔ `docs/ANALYSIS.md`): B1→TS-U-04, B2→TS-U-05,
B3/B4→TS-U-06, B7/B8/B9/B10→TS-I-01, B11/B12→TS-U-07, B13→TS-U-08. All of these
are now fixed (`ANALYSIS.md` §1.5); the tests are the regression guards rather
than known-issue tripwires (TS-I-01's B7–B10 cases self-heal — see above).

### 2.4a Reuse of existing validation assets

The suites are built on what the repository already validates with, rather
than parallel new machinery:

| Existing asset | Reused as |
|----------------|-----------|
| FD harness in `unit_tests/test_unarymath_rules.m` (perturbation, tolerance, singularity exclusion) | Extracted to `tests/helpers/fdcheck.m`; shared by TS-U-01/02/03 and the value checks of TS-I-01/04. |
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
| 2 | Bug-fix PRs flip their `KnownIssue` tests to hard assertions (B1, B7 first — highest severity). TS-I-02/03, TS-U-02/03/06 golden files. | No remaining `KnownIssue` tags for fixed bugs; integration required check enabled. |
| 3 | `nightly.yml`: examples, codegen, release matrix. | One week of green nightlies; promote to required-on-master. |
| 4 | Coverage ratchet (fail if coverage of `embedding/` + `util/` drops), warning-count ratchet in lint. | Ratchet files committed and enforced. |

**Status:** Phases 1–2 and 4 are substantially landed — the documented bugs
B1–B15 are fixed/mitigated (`docs/ANALYSIS.md` §1.5) and their tests are
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
