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
  so **minimum release is R2022a** and **GNU Octave is not an option**.
- CI runs on GitHub Actions with `matlab-actions/setup-matlab@v2`.
  For a public repository, MathWorks provides licensed MATLAB on
  GitHub-hosted runners at no cost; for a private repository a MATLAB
  batch-licensing token must be stored as the `MLM_LICENSE_TOKEN` secret.
- Core transformation tests need base MATLAB only. The optimization
  examples need the Optimization Toolbox; code-generation validation needs
  MATLAB Coder. These are isolated in separate, individually skippable jobs.
- Known bugs documented in `docs/ANALYSIS.md` (B1-B14) must be *pinned* by
  tests from day one. Tests for unfixed bugs are tagged `KnownIssue` and
  reported as expected failures, so the pipeline is green at introduction
  and each bug fix flips its test to a hard assertion.

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

### 1.2 Component-level requirements (REQ-C)

| ID | Component | Requirement |
|----|-----------|-------------|
| REQ-C-01 | `lib/@cada/cadaunarymath.m` | Every unary derivative rule shall match finite differences over each function's domain, including negative arguments and degree-mode variants. |
| REQ-C-02 | `lib/@cada/cadabinaryarraymath.m` | Every binary rule (incl. `atan2`, `power`, scalar-array broadcasting) shall match finite differences. |
| REQ-C-03 | Structural ops (`subsref`, `subsasgn`, `horzcat`, `vertcat`, `reshape`, `repmat`, `sum`, `transpose`, `mtimes`, `mldivide`) | Derivative values and `nzlocs` sparsity shall be correct for scalar/row/column/matrix operands. |
| REQ-C-04 | `util/adigatorGenJacFile.m`, `util/adigatorGenHesFile.m` | Dimension handling shall be correct in **every** branch: dense (`reshape`), scalar-of-vector, vector-of-scalar, scalar-of-matrix (remap), matrix-of-scalar (remap), matrix Jacobian sparse and full branches, vector-output Hessian (m≠n), gradient vs. Jacobian convention selection. *(Pins bugs B7, B8, B9, B10 of ANALYSIS.md.)* |
| REQ-C-05 | `prune_adigator_mat` (in `embedding/adigatorGenDerFile_embedded.m`) | Pruning shall retain all `Index*` and non-empty `Data*` fields; integer down-casting shall apply **only** to `Index*` fields; `Data*` values shall remain `double` and bit-identical. *(Pins bug B1.)* |
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
| TS-U-04 | `UPruneMatTest` — synthetic Gator structs (Index*, integer-valued Data*, sparse, empty fields) → prune → assert retained fields, classes (`Data*` stays double), values. Tagged `KnownIssue` until B1 fixed. | REQ-C-05 |
| TS-U-05 | `UEmbedMfileTest` — property-style round-trip of randomized structs (doubles, logicals, chars, cells, n-d arrays, empties, complex) through `structure_to_embed_mfile`; `isequaln` + class checks; `checkcode` on emitted file. | REQ-C-06 |
| TS-U-06 | `UPatchTest` — golden-file tests: checked-in fixture inputs (representative generated files, incl. one with two loader guards and nested subfunction names) → patch → compare to checked-in expected outputs for modes 'l' and 'i'. Tagged `KnownIssue` for the multi-match cases until B3/B4 fixed. | REQ-C-07 |
| TS-U-07 | `UOptionsTest` — option spelling/validation matrix. Tagged `KnownIssue` until B11/B12 fixed. | REQ-C-08 |
| TS-U-08 | `UHygieneTest` — wrap generator calls (incl. injected failures via invalid user function) and assert path/fid/global invariants. Tagged `KnownIssue` until B13 fixed. | REQ-C-09, REQ-T-07 |
| TS-U-09 | `ULintTest` — `checkcode` over `lib/`, `util/`, `embedding/` with error-level gating and warning ratchet file. | REQ-C-10 |

### 2.2 Integration tests — `tests/integration` (TS-I)

Generate derivative files into `tempdir` via the real pipeline, evaluate,
and compare. Run on every pull request (slower, still base MATLAB).

| ID | Test | Verifies |
|----|------|----------|
| TS-I-01 | `IShapeMatrixTest` — the central dimension test. Parameterized over input shape {1×1, n×1, 1×n, n×m} × output shape {1×1, m×1, 1×m, r×c} × density {dense, structurally sparse} × derivative {jacobian, gradient, hessian} × size regime {small, ≥250-element sparse-branch trigger}. Asserts (a) output shape per the conventions table, (b) every element against dense FD, (c) `JacobianStructure`/`HessianStructure` consistency. Cases hitting B7/B8/B9/B10 tagged `KnownIssue` with the bug ID. | REQ-C-04, REQ-T-01, REQ-T-02, REQ-T-03 |
| TS-I-02 | `IEmbedModesTest` — for each fixture function (incl. one with an integer-valued constant matrix, one with subfunctions, one with a rolled loop): generate with `embed_mode` 'c', 'l', 'i'; assert numeric equality across modes, absence of `global`/`load(` in 'l'/'i' text, absence of `.mat` for 'i'. | REQ-T-04, REQ-C-05/06/07 end-to-end |
| TS-I-03 | `IReproTest` — regenerate twice, compare modulo timestamp lines; `overwrite=0` refusal; `opts.path` placement and calling-dir cleanliness. | REQ-T-06 |
| TS-I-04 | `ISecondDerivTest` — gradient+Hessian through `adigatorGenHesFile` for the `logsumexp` and `gapfun` fixtures, checked against analytic Hessians. | REQ-T-01, REQ-C-04 |

### 2.3 System / validation tests — `tests/system` (TS-S)

Validate the tool against user-level intent. Run nightly and on `master`
merges; license-gated jobs skip cleanly when products are unavailable.

| ID | Test | Validates | Gate |
|----|------|-----------|------|
| TS-S-01 | `SExamplesTest` — run each `examples/**/main*.m` headless (seeded RNG); assert completion and spot values (e.g. fsolve converges, pipg gap function derivatives match FD). | REQ-T-08, REQ-T-01 | Optimization Toolbox for the solver examples; others base MATLAB |
| TS-S-02 | `SCodegenTest` — `codegen -config:lib` (and MEX) each 'i'-mode and 'l'-mode generated fixture; run MEX vs MATLAB equality. | REQ-T-05 | MATLAB Coder |
| TS-S-03 | `SReleaseMatrixTest` — full TS-U + TS-I suite on MATLAB releases {R2022a (floor), latest}. | REQ-T-01..07 on supported releases | nightly only |

### 2.4 Traceability matrix

| Requirement | Verified / validated by |
|-------------|-------------------------|
| REQ-T-01 | TS-I-01, TS-I-04, TS-S-01 |
| REQ-T-02 | TS-I-01 |
| REQ-T-03 | TS-I-01 |
| REQ-T-04 | TS-I-02 |
| REQ-T-05 | TS-S-02 |
| REQ-T-06 | TS-I-03 |
| REQ-T-07 | TS-U-08 |
| REQ-T-08 | TS-S-01 |
| REQ-C-01 | TS-U-01 |
| REQ-C-02 | TS-U-02 |
| REQ-C-03 | TS-U-03 |
| REQ-C-04 | TS-I-01, TS-I-04 |
| REQ-C-05 | TS-U-04, TS-I-02 |
| REQ-C-06 | TS-U-05, TS-I-02 |
| REQ-C-07 | TS-U-06, TS-I-02 |
| REQ-C-08 | TS-U-07 |
| REQ-C-09 | TS-U-08 |
| REQ-C-10 | TS-U-09 |

Known-issue mapping (test ↔ `docs/ANALYSIS.md`): B1→TS-U-04, B2→TS-U-05,
B3/B4→TS-U-06, B7/B8/B9/B10→TS-I-01, B11/B12→TS-U-07, B13→TS-U-08.

---

## 3. CI implementation (GitHub Actions)

### 3.1 Workflows

**`.github/workflows/ci.yml`** — on `push` to `master` and all PRs:

```yaml
jobs:
  lint:          # TS-U-09, minutes
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: matlab-actions/setup-matlab@v2
        with: { release: latest }
      - uses: matlab-actions/run-command@v2
        with: { command: "addpath(genpath('tests')); ci_lint" }

  unit:          # TS-U-01..08
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: matlab-actions/setup-matlab@v2
        with: { release: latest }
      - uses: matlab-actions/run-tests@v2
        with:
          select-by-folder: tests/unit
          test-results-junit: results/unit.xml
          code-coverage-cobertura: results/coverage-unit.xml
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: unit-results, path: results }

  integration:   # TS-I-01..04, needs: unit
    ... same pattern, select-by-folder: tests/integration,
        upload generated files from tempdir as artifact on failure
```

**`.github/workflows/nightly.yml`** — `schedule` (cron) + manual dispatch:
release matrix `{R2022a, latest}` running unit+integration (TS-S-03);
`examples` job with `products: Optimization_Toolbox` (TS-S-01); `codegen`
job with `products: MATLAB_Coder` (TS-S-02). Toolbox jobs check license
availability at startup (`license('test',...)`) and `assumeFail` → skip
rather than error when unavailable.

### 3.2 Licensing and runners

- Public repo: `setup-matlab` provides licensed MATLAB on GitHub-hosted
  runners with no further setup (batch licensing is implicit for public
  repos). Private repo: create a MathWorks batch-licensing token and add
  it as the `MLM_LICENSE_TOKEN` repository secret; reference it via the
  `MLM_LICENSE_TOKEN` env on each MATLAB step. Coder/toolbox products must
  be on the license tied to the token.
- If the token cannot cover Coder, run TS-S-02 on a self-hosted runner with
  a local install, kept in the nightly workflow only.

### 3.3 Conventions and policies

- **Test layout:** new `tests/{unit,integration,system}` tree using
  `matlab.unittest` classes; existing `unit_tests/test_unarymath_rules.m`
  is ported into TS-U-01 (keep the FD harness, wrap in test methods).
  Shared fixtures (small user functions, golden patch files) under
  `tests/fixtures`. All generation goes to `TestCase`-managed temp folders
  via `opts.path` so the repo tree stays clean.
- **Known-issue policy:** tests for documented unfixed bugs carry the tag
  `KnownIssue` and call `assumeFail("Known issue Bn, see docs/ANALYSIS.md")`
  so they appear as *filtered* (visible, counted, non-blocking). A bug fix
  must delete the `assumeFail` in the same PR — the test then becomes the
  regression guard. CI fails if a `KnownIssue` test unexpectedly *passes*
  (stale tag detector in `ci_lint`), keeping the list honest.
- **Gating:** `lint` + `unit` + `integration` are required checks for PRs.
  Nightly jobs (`examples`, `codegen`, release matrix) are informational
  for the first month, then promoted to required-on-master once stable.
- **Determinism:** seed all RNG (`rng(0)`) in tests and examples; FD
  tolerances chosen per derivative order as in REQ-T-01; no test depends
  on `cd`.
- **Artifacts:** JUnit XML + Cobertura coverage on every run; on failure,
  upload the generated `.m`/`.mat` files for offline diagnosis.

### 3.4 Phased rollout

| Phase | Content | Exit criterion |
|-------|---------|----------------|
| 0 | `ci.yml` with `lint` + TS-U-01 (ported existing test) + one smoke integration case (`gapfun` jacobian, mode 'c', FD check). | Pipeline green on a trivial PR; licensing path proven. |
| 1 | TS-I-01 shape matrix + TS-U-04..08, with `KnownIssue` tags for B1-B13. | All documented bugs pinned by a failing-but-filtered test. |
| 2 | Bug-fix PRs flip their `KnownIssue` tests to hard assertions (B1, B7 first — highest severity). TS-I-02/03, TS-U-02/03/06 golden files. | No remaining `KnownIssue` tags for fixed bugs; integration required check enabled. |
| 3 | `nightly.yml`: examples, codegen, release matrix. | One week of green nightlies; promote to required-on-master. |
| 4 | Coverage ratchet (fail if coverage of `embedding/` + `util/` drops), warning-count ratchet in lint. | Ratchet files committed and enforced. |

### 3.5 Out of scope (explicitly)

- Performance benchmarking of generated code (worth a later, separate
  workflow with stored baselines; too noisy for gating now).
- Windows/macOS runners — the toolbox is OS-agnostic MATLAB code; a single
  Linux runner suffices until an OS-specific issue appears (the historical
  filesep issues are covered by tests running through `fullfile`).
- Testing the vectorized (GPOPS-II) mode beyond what the examples cover.
