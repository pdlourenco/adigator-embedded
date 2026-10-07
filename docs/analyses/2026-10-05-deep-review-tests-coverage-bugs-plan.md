# Deep review — test facilities, coverage gaps, bug candidates, publishable parts, and a plan

**Analysis date:** 2026-10-04/05. **Commit examined:** `a4e24bc` (`origin/master`,
2026-08-07, "fix(prepush): say when the gate is not armed"). `file:line`
references are relative to that commit and will drift.

> **Immutable snapshot** (`docs/analyses/README.md` rule 3). Findings here are
> not updated as they get fixed. Live status: the issues and PRs opened from this
> review, `ROADMAP.md` rows the maintainer promotes from §9, and `ANALYSIS.md`
> for any bug candidate in §4 that a MATLAB reproduction confirms. **Nothing
> here is a contract**; where a finding says a contract and an implementation
> disagree, the finding names both sides and stops (CLAUDE.md §3).

## 0. Scope, method, and what this review could and could not establish

**Scope.** Everything in the tree: the transformation engine (`adigator*.m`,
`lib/`), the fork layer (`util/`, `embedding/`), the test suite (`tests/`: 66
classes, 384 methods, 425 instances), the CI harness (`.github/`, `.githooks/`,
`tests/ci_*.m`, the ratchet baselines), the documentation set (`docs/`,
`CHANGELOG.md`, `CLAUDE.md`, `DISCIPLINE_ADOPTION.md`, the user guide, the ADRs),
`bench/`, `examples/`, and the full git history (417 commits, unshallowed).

**Environment.** A cloud session **without MATLAB**. GNU Octave 8.4.0 was
installed (`apt-get install octave`) and used wherever a claim could be settled
by executing plain MATLAB-dialect code. The GitHub Actions API was queried
read-only for workflow-run history. Consequently:

- **No MATLAB test was run.** Every statement about what a test asserts, filters
  or would miss is from reading the test text and the source under test. Where a
  statement would need MATLAB to settle, the finding says so and the plan item
  carries `[matlab]` or `[coder]`.
- **Bug candidates (§4) are static findings.** Each carries a confidence grade,
  the quoted code, a minimal reproduction to run in MATLAB, and whether an
  existing test would catch it. None has been entered into `ANALYSIS.md`'s
  `Bnn` register: that is the maintainer's call after the reproduction (§9).
- **Octave results are measured**, with the command and its output recorded (§7
  and Appendix B).

**Method.** Three inventories were built first and then judged by dimension:

| Inventory | What it covers | Size |
|---|---|---|
| Test inventory | every test method: assertion kinds, tolerances, `assume`/`KnownIssue` gates and what each means on a hosted runner, fixture, REQ/TS ids cited, which gate runs it | 66 classes / 384 methods |
| Test-history census | every commit touching `tests/`, `.github/`, `.githooks/`: tolerance changes, gates added, assertions weakened or removed, expected values changed, workflow/baseline changes | 153 commits, 344 file diffs, 301 hunks (171 read line by line) |
| Doc-claims inventory | every `CI_PLAN.md` TS/REQ row, every `DESIGN.md` *Verified by*, every `ANALYSIS.md` §1.5 pin, every `ROADMAP.md` status, every ADR revisit clause, cross-doc ranges/paths | 63 TS rows, 22 REQ rows, 6 contracts, 36 §1.5 rows, 31 roadmap rows, 38 ADRs |

Dimension reviews then ran over those inventories: relaxed tests (from history),
relaxed/vacuous tests (from the current text), functionality not covered,
derivative-rule bugs, structural/control-flow engine bugs, fork-layer bugs,
documentation drift and the deferral sweep, CI infrastructure, Octave
feasibility (measured), publishability, examples/guide health, and
hygiene/licensing. The highest-impact claims were then re-verified directly by
the orchestrating session before being written here; those re-verifications are
named in the text ("verified directly").

**Evidence discipline.** `REVIEW_CONTEXT.md` §"Evidence discipline" binds this
document. Every finding quotes the text it rests on with `file:line`, and says
how it was checked. A negative claim ("no test exercises X") names the search
forms it enumerated. Counts carry their population. Where this review found a
documented measurement that does not reproduce, it says so rather than
restating it.

**Finding identifiers.** `TF-` test facilities, `CG-` coverage gaps, `BG-` bug
candidates, `DD-` documentation drift, `CI-` CI infrastructure, `HY-` hygiene
and release, `OC-` Octave, `PB-` publishable parts. Severity: *critical* = can
produce or hide a silently wrong derivative (principle 1); *high* = a property
believed guarded is not, or a gate is hollow; *medium* = real gap with a clear
fix; *low* = hygiene; *info*. Environment tags for the plan: `[cloud]` no MATLAB
needed, `[octave]` needs GNU Octave, `[matlab]` base MATLAB, `[coder]` MATLAB
Coder / Embedded Coder / C toolchain.

**What this review did not read.** The bodies of most `lib/@cada` overloads
beyond the derivative-rule kernels and the files named in §4; `lib/@cadastruct`
bodies beyond the fallback-naming arm; `lib/@cada/adigatorAnalyzeForData.m`
(2708 lines) beyond grep; the user guide beyond its section list, option table,
command reference and fork sections; the PDFs under `docs/papers` and
`docs/thesis`. Appendix B lists per-dimension coverage notes.

---

## 1. Headline findings

Ten things a maintainer should know before anything else. Each is expanded in
the section cited.

1. **The post-merge gate has never run on `master`** (TF-01). The
   Extended workflow triggers only on pushes to the `embedded` branch (abandoned
   2026-06-18, now 270 commits behind) or by manual dispatch. The Actions API
   shows 15 runs in its life: eleven push-triggered on `embedded`
   (2026-06-11 … 2026-06-18), then four manual dispatches on feature branches,
   zero on `master`. So the system suite (`SExamplesTest`, `SDerivShowcaseTest`,
   `SCscMetadataTest`), the Monte-Carlo smoke, the R2022a floor matrix and the
   ADR-0032 per-folder coverage floor, all described in `CI_PLAN.md` §3.1/§3.6
   and ADR-0032 as per-merge, have not executed on any merged commit for about
   four months. Fix is one line of YAML plus six doc corrections. `[cloud]`

2. **Twelve candidates graded critical for a silently wrong derivative, none
   covered by a test** (§4.1 and §4.5: BG-01..06, BG-10..13, BG-39, BG-41;
   seven verified directly in the source or re-run in Octave: BG-01, 02, 04,
   05, 06, 11, 39; ten reproduced in MATLAB R2024a by the review of this PR,
   §4 preamble). Eight are in upstream-inherited rule and engine code
   (BG-01..06, BG-10, BG-12), two in the fork's `loopbound` layer (BG-11,
   BG-13), one in a shipped fork utility (BG-39), one in the reverse-mode
   transformer (BG-41, medium confidence). A thirteenth, BG-25, returns a
   silently wrong *value* for non-square `x/y` through `adigator()`. `mod(x, y)` with an active scalar divisor applies the
   `d/dy` rule only when `y == 0` (BG-01); `sum(X, 2)` emits the derivative in
   the wrong order when a variable touches a non-monotone set of entries
   (BG-02, also reached by `X*ones(n,1)` and `dot(·,·,2)`); `cross` on `3×N`
   permutes derivative rows in the wrong direction for `N ∉ {1,3}` (BG-03);
   overdetermined `A\b` with constant `A` emits **no** derivative (BG-04); the
   logical operators build the second operand's zero mask from the first
   operand (BG-05, which also folds `if` conditions at generation time); an
   inline numeric block in a concatenation records its *nonzero* positions as
   zeros, pruning real derivatives in the homogeneous-rotation idiom (BG-06);
   solve sparsity is pruned by numeric cancellation (BG-10); `loopbound` pads
   wrongly for a loop whose values depend on the bound (BG-11) or for a
   counter-dependent inner loop at second order (BG-13); and, with no
   `loopbound` involved, the Hessian of a `for j = 1:i` inner loop prints a
   vector colon bound (BG-12). All were static/Octave findings when written;
   the review of this PR ran them in MATLAB R2024a (§4 preamble): ten of the
   eleven it ran (BG-01..06, BG-10..13, BG-39) reproduce as silently wrong,
   BG-04 is silent through `adigator()`, and BG-25 is confirmed. None has entered the
   `Bnn` register yet; each entry carries its reproduction. The shipped utility
   `adigatorUncompressJac` applies the colouring permutation in the wrong
   direction (BG-39, confirmed in Octave on the repository copy) and is the
   untested utility `CI_PLAN.md` describes as round-trip tested. `[matlab]`

3. **The B7–B10 regression guards cannot fail on the bugs they guard** (TF-02,
   verified directly). The six `KnownIssue` methods in `IShapeMatrixTest` still
   wrap generation/evaluation in `try … catch → assumeFail`, and the silent-B7
   method filters on the *same* `1e-4` threshold its trailing `verifyEqual`
   uses, so no finite value deviation can ever reach the assertion. A re-introduced
   B7/B8/B9/B10 would report *Filtered* inside a green PR gate. `ANALYSIS.md`
   §1.5 calls these methods the guards without the caveat `CI_PLAN.md` TS-I-01
   carries. The stale-tag detector that would have caught this has been
   "planned, not yet implemented" since Phase 2. `[matlab]` to confirm green
   after the scaffolds are removed.

4. **Six of the eleven binary derivative rules have no value oracle anywhere**
   (CG-01): `atan2`, `mod`, `rem`, `ldivide`, `power` with an *active*
   exponent, and two-argument `max`/`min`. `REQ-C-02` promises `atan2` and
   `power`; its only verifying row (TS-U-02) scopes `power` to an inactive
   exponent and omits the rest. The unary sweep drives all 42 rules through a
   `[1 1]` input, so the vector/gather emission branches of
   `cadaunarymath.m` run for at most five rules (CG-02). This is the gap that
   let item 2 survive. `[matlab]`

5. **The ratchets do not ratchet** (TF-03, TF-04). The PR-gate coverage
   baseline has been `0.1941` since its bootstrap commit (2026-06-11) while
   the gated suite grew roughly ninefold (38 → 347 `methods (Test)` entries
   in `tests/unit` + `tests/integration`, 8 → 54 classes, `2d5f6f9` →
   `a4e24bc`); the lint baseline has been 423
   findings since day one and the lint scope omits `tests/montecarlo`,
   `tests/helpers`, `tests/offline`, `bench/` and `lib/@cadastruct/private`;
   the per-folder floor (the only full-suite coverage run) is in the workflow
   of item 1. `[matlab]` to read the current numbers, then `[cloud]`.

6. **GNU Octave runs the transformation core** (OC-01, verified directly).
   `CI_PLAN.md` §0 and `DESIGN.md` §Constraints state, as a constraint
   "verified against the codebase", that Octave is not viable because of
   `classdef` dispatch. Measured: with four small MATLAB-neutral edits and a
   dependency-walker shim, Octave 8.4 generates Jacobians, Hessians (the
   two-pass re-differentiation), struct-input and interprocedural derivatives
   that match analytic references, and the interprocedural `gapfun` output
   differs from the committed MATLAB-captured fixture only by the two metadata
   lines inline mode strips. Three engine defects surfaced on the way
   (BG-07..09): an unescaped `(` in the only engine regexp, a `numel(x)`
   signature that Octave calls with index arguments, and a reliance on
   `rehash` that makes a second generation in one Octave session **silently
   differentiate the previous function**. This changes what a cloud session
   can verify (§7, §9). `[octave]`

7. **Tolerances are set by the oracle, not the derivative** (TF-05). `REQ-T-01`'s
   `≤ 1e-6` first-order criterion is enforced by no finite-difference test; the
   unary sweep uses one-sided FD at relative `1e-4`; `UNormTest` compares an
   *analytic* gradient at `1e-4`; the polydatafit example, the only place the
   `mldivide` rule with an active left operand is exercised, accepts
   `RelTol 5e-3` because its own central-difference oracle is that noisy
   (reproduced in Octave), and it lives in the suite of item 1. `[matlab]`

8. **Filter-on-failure idioms turn defects into green runs** (TF-06..08).
   Thirteen `catch e; if … contains(e.message,'coder.') assumeFail` sites in
   eleven test files (fifteen with `bench/` and `examples/`) would report a patcher that emits a misspelled `coder.*` call as *Filtered*; the
   footprint harnesses fold a *failed codegen build* into the same `-1`/`NaN`
   sentinel as "no gcc", so the stack and ROM gates skip on exactly the
   regressions (B35, #217) they were built to catch; `ci_ert` prints `PARTIAL`
   but exits 0. `[matlab]`/`[coder]`

9. **Documentation drift is broad but mechanical** (§5): two phantom test classes
   in the CI plan (`ULintTest`, `SReleaseMatrixTest`), eight real classes with
   no registry row, three stale ROADMAP statuses (R14, R17, R27 describe as
   outstanding work that is in the tree), a user-facing CHANGELOG sentence
   about "47 generated artifacts committed under `examples/`" (zero are
   tracked), the bug register quoted as B1–B22 / B1–B26 against an actual B40,
   contracts quoted as C-1..C-5 against C-6, and the `'l'` embed mode accepted
   with no deprecation warning while its help text still says "Suitable for
   code generation". All `[cloud]`.

10. **The deferral sweep finds one gate never taken and one latent drift**
    (§5.4): ADR-0021's `'l'`-removal decision is gated on an "R17
    large-data measurement" that does not exist (no `'l'` or split-data
    compiled cell was ever measured); ADR-0022's revisit fired and was handled
    (ADR-0030); ADR-0028 notes its five loop-guard copies "have already drifted
    textually", with no test pinning them in step. `[cloud]`/`[coder]`

Bug candidates from the engine, fork-layer and reverse-mode reviews are in §4;
the plan in §9 orders everything by what a cloud session can do now, what Octave
unlocks, and what needs a licensed machine.

---
## 2. Test facilities

The suite is large and mostly well-aimed: 100 methods compare against an
analytic reference and 59 against finite differences, most analytic checks sit
at `AbsTol 1e-12` or exact (`AbsTol 0`), the clean-path discipline (ADR-0017)
and the suite guard (#235) are real improvements, and the tolerance-free
Monte-Carlo oracles are a genuinely good idea. The findings below are about
where the *gates* are hollow, where tests were *relaxed* and the relaxation was
never revisited, and where an assertion cannot fail on the thing it is named
for. They are ordered by what they hide.

### 2.1 Gates that are not armed or cannot ratchet

**TF-01 (high, `[cloud]`) — the Extended workflow does not run on the default
branch.** `.github/workflows/extended.yml:12-15`:

```yaml
on:
  workflow_dispatch:
  push:
    branches: [embedded]
```

The default branch is `master` (`git remote show origin` → `HEAD branch:
master`); `origin/embedded` is 270 commits behind it and 0 ahead (`git log
origin/embedded..origin/master | wc -l` = 270; last commit 9ff3d9a,
2026-06-18). GitHub Actions, queried through the API on 2026-10-04, lists 15
runs of `extended.yml` in total: runs 1–11 `event=push` on `embedded`
(2026-06-11 … 2026-06-18; run 1 failed, runs 2–11 succeeded), runs 12–15 `event=workflow_dispatch` on
`claude/prune-shrink-timestamp-717b3e0`, `claude/vv-foundation-coverage-floor`
(twice) and `fix/ci-gate-suite-loss`; none on `master`. The last run of any kind
is 30894932553 (2026-08-04). `ci.yml` by contrast runs on `push: branches:
[master, embedded]` (`:10`, the `embedded` entry is dead).

What that means, because every one of these is described as a per-merge gate:

| Described in | Claim | Reality on `master` since 2026-06-18 |
|---|---|---|
| `CI_PLAN.md:345-346` | extended runs "on every push to `embedded` (i.e., on merge)" | never triggered by a merge |
| `CI_PLAN.md:176-177` (TS-S) | system tests "run nightly and on `master` merges" | never run post-merge |
| `CI_PLAN.md:190` TS-S-03 | release matrix {R2022a, latest} | R2022a floor last exercised 2026-06-18 on `embedded` |
| `tests/montecarlo/MCSmokeTest.m:4-6` ("per-merge"); `CI_PLAN.md:366-373` ("runs in the extended workflow") | Monte-Carlo smoke | never run post-merge |
| `CI_PLAN.md:516-528`, ADR-0032 | per-folder coverage floor "enforced post-merge" | never run post-merge; the committed baseline (`bc07453`, 2026-07-29) comes from a PR-branch dispatch |
| `CI_PLAN.md:465-467` | nightlies "promoted to required-on-master once stable" | never promoted; there are no nightlies |

The history census shows how it happened (TF-12 below): `2d5f6f9`
(2026-06-11) renamed `nightly.yml` to `extended.yml`, dropped the cron and set
the trigger to `embedded` *because* that "removes the need to change the
repository default branch"; the default branch then moved to `master` a week
later and only `ci.yml` was updated. A justified narrowing whose justification
lapsed silently, which is `REVIEW_CONTEXT.md` tell 3 at the scale of a whole
workflow: every "Extended is green" statement since June describes manual runs
on PR branches.

*Fix:* `branches: [master]` (drop `embedded` from both files), re-add the
`schedule:` block the file's own header says to add "once this file lives on
the default branch", dispatch one run on `master`, and re-baseline
`tests/coverage_baseline_folders.txt` from it. Then correct the six rows above.

**TF-02 (high, `[matlab]` to confirm) — the B7–B10 "regression guards" filter
on their own failure modes.** `tests/integration/IShapeMatrixTest.m:136`
opens `methods (Test, TestTags = {'KnownIssue'})` and keeps the six
self-healing scaffolds that pinned B7–B10 *before* they were fixed
(`31fcad7`, 2026-06-10). Verified directly at HEAD:

- `jacScalarOfMatrix` (:142-146), `jacMatrixOfScalar` (:161-165),
  `hesVectorOutputNGreaterM` (:185-189) and `hesMatrixOfScalar` (:220-224) wrap
  the generator call or the wrapper evaluation in `try … catch e;
  tc.assumeFail("Known issue … " + e.message); end`. A re-introduced error in
  any of these branches is **caught and filtered**.
- `hesVectorOutputMGreaterN` (:204-207), the pin for the *silent* B7 variant
  ("the wrong multiplier stays in bounds but collides rows → wrong values"),
  reads `if max(abs(H(:) - Hexp(:))) > 1e-4, tc.assumeFail(...)`, then calls
  `verifyVectorHessian`, whose assertion is `verifyEqual(H, …, 'AbsTol', 1e-4,
  'RelTol', 1e-4)` (:333-337). Any element that would fail the assertion
  trips the filter first. **The value assertion is unreachable**, and a size
change errors at `:204` (`H(:) - Hexp(:)`) before `verifySize` is reached, so
no outcome of this method can report as a failure.
- `grdSparseBranchOfVectorOutput` (:245-248) filters on `~isequal(size(G),
  [25 10])`, so the B9 shape regression it exists for reports *Filtered*.
- The two B10 methods discard the generator's output struct (`:143`, `:162`),
  so the exported `JacobianCSC` for the scalar-of-matrix and matrix-of-scalar
  remaps, the exact surface B10 corrupted, is asserted nowhere; the `148ccca`
  hardening that added `verifyExportedStructure` reached only the five
  non-`KnownIssue` methods (:50, :77, :92, :109, :131).

`ANALYSIS.md:1282-1286` says B7 is "Covered by `hesVectorOutput*`", B9 "Guarded
by `grdSparseBranchOfVectorOutput`", B10 "Guarded by `jacScalarOfMatrix` /
`jacMatrixOfScalar`", with no caveat; `CI_PLAN.md:142` carries the caveat ("a
re-introduced B7–B10 regression would … report as *filtered*, not *failed*")
and `:460-463` says the stale-tag detector is "planned, not yet implemented";
`:493-495` records Phase 2's exit criterion as met "except for" exactly this
block. Principle 6 ("a bug fix flips its `KnownIssue` test to a hard assertion
in the *same* PR") was not followed by the fix commits `31fcad7`/`f33aea6`
themselves (their bodies say the cases "auto-flip"), and the red flag "a
`KnownIssue` tag left on a test that now passes" has been live for four
months. No other gated test compares a vector-output Hessian's values to an
analytic or FD reference in a way that would catch a row collision
(`IZeroHessianTest.vectorOutputLinearHessianIsZero` compares to the analytic
zero, which a collision of zero rows also satisfies): `ICscOutputTest` FD-checks Hessians only when square
with `numel(x)` rows (:232), `IOutputModesTest.hessianCscVectorFunction` compares
csc to matrix mode of the same generator, `ILevelSelectTest` compares variants to
`Href` from the same generator, the Monte-Carlo expression-tree Hessians are
scalar-output, the CasADi battery's Hessian case is `scostfun` (scalar).

*Fix:* move the six methods to a plain `methods (Test)` block; delete the four
`try/catch` wrappers and the two threshold pre-checks so the trailing
assertions run unconditionally; capture `out = adigatorGenJacFile(...)` in the
B10 methods and add `verifyExportedStructure(tc, out, 'Jacobian', J)`; then
drop the caveats in `CI_PLAN.md` TS-I-01/§3.4 and the class header. One MATLAB
run to confirm the six pass as hard assertions (expected per §1.5). Separately,
implement the stale-tag detector as a licence-free check (§9, WP-C3).

**TF-03 (medium) — the PR-gate coverage ratchet is a one-time floor.**
`tests/coverage_baseline.txt` is `0.1941`, written by `2d5f6f9` on 2026-06-11
("the numbers reported by this PR's first CI run") and never changed (`git log
-- tests/coverage_baseline.txt` → one commit). `tests/ci_coverage.m:42-47`
errors only if `rate < base - 0.005` and otherwise prints "consider tightening
… to X" on every green run. The full-suite per-folder baselines of 2026-07-29
(`lib` 0.59, `lib/@cada` 0.40, `util` 0.75, `embedding` 0.92) show the gated
aggregate is far above 0.19, so coverage could fall by more than half without a
signal. The exact current PR-gate rate could not be read here (the job-log
download is blocked by the proxy). *Fix:* read the "consider tightening" line
from the latest `master` run (or run `ci_coverage` locally) and commit it; add
to `CONTRIBUTING.md` that a PR adding tests raises the baseline. `[matlab]` then
`[cloud]`.

**TF-04 (low) — the lint ratchet tolerates 423 findings and scans a subset of
the tree.** `tests/lint_baseline.txt` = 423 since `2d5f6f9`; `ci_lint.m:13-25`
lists root, `lib`, `lib/cadaUtils`, `lib/@cada`, `lib/@cada/private`,
`lib/@cadastruct`, `util`, `embedding`, `tests`, `tests/unit`,
`tests/integration`, `tests/system`; it omits `lib/@cadastruct/private`,
`tests/montecarlo` (+ `generators`, `oracles`), `tests/helpers`,
`tests/offline`, `tests/legacy`, `bench`, `examples`. A count ratchet lets a
new finding hide behind a removed one (REQ-C-10 says "no *new* `checkcode`
errors"). *Fix:* extend the folder list (one-time baseline bump), and store
the finding *set* (file:line:message) rather than the count so a new finding
is named. `[matlab]` to regenerate, otherwise `[cloud]`.

**TF-05 (medium) — the tolerance policy in `REQ-T-01` is enforced nowhere, and
one tolerance is set by the oracle rather than the derivative.** `REQ-T-01`
(`CI_PLAN.md:73`): "Relative error ≤ 1e-6 (1st order) / 1e-4 (2nd order, FD
reference)". Measured over the suite:

| Where | Oracle | Tolerance used |
|---|---|---|
| `URulesUnaryTest` (42 rules × 30 points) | one-sided FD, `h = 1e-6` | relative `1e-4` (and a NaN AD value can never register: `abs(NaN−df)/(1+abs(df)) > 1e-4` is false) |
| `UNormTest` | one-sided FD; `rowVectorNorm` vs **analytic** | relative `1e-4` even for the analytic case |
| `fdcheck` users (`URulesBinaryTest`, `UStructuralOpsTest`, `IShapeMatrixTest`, `IRevGradTest`, `INDParamTest`, …) | central FD, `h = 1e-6` | `AbsTol/RelTol 1e-5` |
| `SExamplesTest.arrowheadExample` | example's `numjac` | `1e-4` |
| `SExamplesTest.polydatafitExample:60-67` | test-side central FD, `h = 1e-6` | `AbsTol 1e-3, RelTol 5e-3` |
| Hessian FD checks | central FD, `h = 1e-4` | `1e-4` (meets the 2nd-order criterion) |
| Monte-Carlo `oracleFiniteDiff` | central FD | `atol 1e-5, rtol 1e-4` |

The polydatafit case matters beyond its number: `fit.m:38` (`p = V\d`, `V`
built from the derivative input) is the **only** place in the suite where the
`mldivide` rule with an active left operand is exercised (the other `\`/`/`
hit, `IRevGradTest.m:175`, pins a *refusal*; `UStructuralOpsTest`, the TS-U-03
row that `REQ-C-03` names for `mldivide`, has no such fixture). The band was set
in `4e1c8b0` (2026-06-11), the commit that turned the first red Extended run
green, by swapping the example's `numjac` reference for test-side central FD
and widening `RelTol 1e-3 → 5e-3`; the commit body says "if the ADiGator
Jacobian were actually wrong this still fails", an assertion that was not
shown. An Octave reproduction of the example's own problem (`m = 8`, `n = 100`,
three seeds) gives: analytic normal-equation Jacobian computed three ways agrees
to `~2e-7` relative; central FD at `h = 1e-6` differs from it by `0.03–0.04`
**absolute** (`|J|` up to `4.9e4`); the `(1e-3, 5e-3)` band passes all seeds,
`(1e-3, 1e-3)` fails one seed at `h = 1e-6` but passes all at `h = 1e-5`. The
band width is a property of the instrument (tell: "the number is real, but it
measures something other than what the sentence says"). A Jacobian wrong by
`~0.4%` relative would pass, and the test is in the suite TF-01 never runs.

*Fix:* (a) decide the policy: either tighten the FD tests to central
differences at `1e-5` and reword `REQ-T-01` to the enforced numbers, or keep
`1e-6` and make the analytic path the primary oracle where a closed form exists
(`REQ-T-01` itself says "analytic where available"); (b) for polydatafit use
the analytic normal-equation Jacobian at `RelTol 1e-5`, or at least `h = 1e-5`
with `(1e-3, 1e-3)`; (c) add an `mldivide`/`mrdivide` fixture with an analytic
reference to `UStructuralOpsTest` (CG-03); (d) in `UNormTest.rowVectorNorm`
compare the analytic gradient at `1e-12`. `[matlab]`

### 2.2 Tests relaxed in history — verdicts

The census read every hunk in the test and CI history that could be a
relaxation (301 hunks, 171 line by line). The list below is every entry judged
*wrongful*, *questionable*, or *justified at the time but lapsed*. Everything
else was either feature-driven (a contract changed with its ADR), a tightening
(derivative-value tolerances were tightened, never loosened: e.g.
`IOutputModesTest` csc comparisons went from `1e-13`/`1e-14` to `AbsTol 0` in
#192), or a licence gate that genuinely needs Coder.

| # | Commit | What changed | Stated reason | Verdict | Current state |
|---|---|---|---|---|---|
| TF-12 | `2d5f6f9` 2026-06-11 | extended trigger → `push: [embedded]`, cron dropped | "removes the need to change the repository default branch" | **lapsed** — default branch moved to `master` a week later | still `[embedded]` (TF-01) |
| TF-13 | `31fcad7` 2026-06-10, `f33aea6` 2026-06-11 | B7 fixed and B8–B10 fixed with the pins left as `KnownIssue` self-healers | "the KnownIssue cases auto-flip into hard regression guards" | **wrongful** — principle 6 asks for the flip in the same PR; the auto-flip never happened and the scaffold hides regressions | unchanged (TF-02) |
| TF-14 | `4e1c8b0` 2026-06-11 | polydatafit `RelTol 1e-3 → 5e-3` + oracle swapped to test-side FD | the example's `numjac` "cannot deliver the asserted tolerance" | **questionable** — band set by FD noise; analytic reference available | unchanged (TF-05) |
| TF-15 | `ef43635` 2026-06-11 | `ILoopboundTest` exact padded-tail assertion wrapped in `if numel(vm.f) == Nmax … else verifySize(vm.f,[n 1])`; the padding-unsafe pin fixture changed `zeros(N,1) → zeros(6,1)` | "CI revealed … buffers sized by the bound come out runtime-sized — better than the documented contract" | **questionable** — an either/or assertion cannot detect a regression in the direction the rewritten contract (`adigatorOptions.m:94-97`) now specifies; the runtime-sized behaviour is pinned by no test | unchanged (`:78-82`, `:188`) |
| TF-16 | `4038de7` 2026-06-11 | `IEmbedModesTest` expected `'Grd(['` changed to `'Jac(['` to match the generator | match the generator | **wrongful** (test bent to the implementation, against C-6) | reversed by `225e329` 2026-07-01 — resolved |
| TF-17 | `17f6bfa` 2026-07-07 | `UNormTest.matrixNormErrors` accepts `MATLAB:norm:unknownNorm` alongside the C-5 id for `p = -Inf` | — | **low** — pins a MATLAB-internal id (the kind #226 refused) and that iteration no longer exercises the C-5 gate; the sibling method solved it by dropping `-Inf` | unchanged |
| TF-18 | `96052e6`/`33b905e` 2026-07-30 | `SLoopboundPaddingTest` ROM-ratio floor at `n = Nmax` `≥ 0.95 → > 0.75` | justified in-comment, after B36 changed the measured artifact | **low** — set after the artifact moved (0.88 then 1.09); Coder-gated, local-only | unchanged |
| TF-19 | `2677642` 2026-06-27 | `SCodegenShowcaseTest` dropped `rev < fwd` and `ana ≤ fwd` source-byte asserts | "pinned there" (R17c), which landed 13 days later asserting convergence, not "leaner" | **low** — the AD-vs-analytical ordering is pinned nowhere; the headline was retracted (ADR-0027) | unchanged |
| TF-20 | `9b9086e` 2026-07-01 | `SCodegenTest` ERT lib build wrapped in a silent `if license('test','RTW_Embedded_Coder')` | — | **wrongful** at the time (silent no-op on Coder-only runners) | fixed by `8398f6d` 2026-07-07 (`assumeTrue`) — resolved |
| TF-21 | `eaa26ae` 2026-06-23 | B16 hygiene invariant weakened strict → populated-only | a success-path failure | maintainer-decided | re-tightened `2026-06-25` (ADR-0015) — resolved |
| TF-22 | `3d44384`, `7cc36cc`, `56bc8f6` 2026-06-22 | three "update fixtures" golden regenerations with empty commit bodies (`56bc8f6` deletes 2 `.m` + 2 `.mat`) | none recorded | **low** — bounded by the `AbsTol 0` equivalence guard, but no rationale | — |
| TF-23 | `be65654 → 93e2d92` 2026-07-03/06 | embed gate `verifyError → verifyWarning` | ADR-0023 rev (C-4 flipped in the same PR, `AbsTol 0` cross-mode added) | policy, tracked | — |
| TF-24 | `5d7e1f7` 2026-07-11 | `hessians/logsumexp` example added to `discoverExamples`' Coder-required skip list | — | **low** — skipped on Coder-less sweeps | — |
| TF-25 | `7bf37ff`, `1c63b48`, `f81ec79` | `KnownIssue` tripwires added for live bugs (B27 silent-wrong, #173, #217 63.4× stack) | per policy | conformant (one hollow pin, healed) — each *filtered* (`assumeFail`) while live, each healed on its fix within a day; `f81ec79`'s pin used the filter-threshold-equals-assertion shape TF-02 calls hollow, noted here for consistency (healed since) | — |

Two census facts worth keeping: no assertion is commented out anywhere at HEAD
(`^\s*%\s*(tc\.)?(verify|assert)\w*\(` over `tests/` → 0 hits), and no test was
ever moved out of `tests/unit` or `tests/integration` into a non-gated folder
(`git log --diff-filter=R --name-status a4e24bc -- tests/` → no rename leaving
either folder; the only "moves" were `test_norm_rules.m` → `UNormTest` and
`test_unarymath_rules.m` → `tests/legacy`, both superseded by ported classes).

### 2.3 Weak, vacuous or self-referential assertions at HEAD

**TF-06 (medium) — the `coder.*` catch idiom filters a class of embed-pipeline
regression on every runner.** Thirteen sites in eleven test files, fifteen
counting `bench/derivShowcase.m` and `examples/jacobians/structinput/main.m`
(`IEmbedModesTest.m:116-121`, `IConstStructFieldTest`, `IConcatLoopLiteralTest`,
`IEmbedSlimTest`, `IEmbedSlimRolledTest`, `ILevelSelectTest`, `ILoopboundTest`,
`IRevEmbedTest`, `IStructInputTest`, `SExamplesTest`, `oracleCrossMode`) use:

```matlab
catch e
    if strcmp(e.identifier, 'MATLAB:UndefinedFunction') && contains(e.message, 'coder.')
        tc.assumeFail(...)
    end
    rethrow(e);
end
```

The predicate keys on the *message* containing `coder.`, not on
`which('coder.const')` being empty. `CI_PLAN.md:395-397` records that
`coder.load`/`coder.const` resolve on hosted runners, so today the branch is
dormant; the day `adigator_patch_derivative` or `structure_to_embed_mfile`
emits a misspelled or renamed `coder.*` call, every numeric cross-mode check
reports *Filtered* instead of *Failed*, on every runner (`REVIEW_CONTEXT.md`
red flag: a guard whose failure direction is documented but not asserted).
*Fix:* decide the assumption once in `TestClassSetup`
(`assumeTrue(~isempty(which('coder.const')) && ~isempty(which('coder.load')))`,
or a shared `tests/helpers/coderNamespaceAvailable.m`) and remove the catch.
`[matlab]`

**TF-07 (medium, `[coder]`) — the footprint gates convert a failed build into
"toolchain absent".** `bench/loopboundPaddingPenalty.m:86` initialises
`fp = struct('rom',-1,'ram',-1,'stack',-1)` and `:118-120` catches the codegen
exception into a warning, leaving `-1`, the same sentinel
`measureErtFootprint.m:30,35` returns when `gcc`/`size` are missing;
`SLoopboundPaddingTest.m:42` then `assumeTrue(rp.padded.rom > 0, 'gcc/size
toolchain absent …')`. `bench/measureStackScaling.m:170-172` does the same and
`SStackScalingTest.m:140` `assumeFalse(isnan(r.maxOverhead), '… no overhead
measured (standalone gcc/size absent, or a build failed) …')`, naming the
conflation in its own message. `SGenericBoundFoldingTest` skips when the `gcc`
compile fails and `SCodegenShowcaseTest` skips every footprint assertion on a
`-1` cell. The bench's own comment (`loopboundPaddingPenalty.m:104-107`) says a
re-introduced unbounded size "fails the build loudly"; the test turns that loud
failure into *Filtered*. B35 and #217 were caught by exactly these builds.
*Fix:* return a `built` flag separately from the sentinel and `assertTrue(all
built)` **before** the toolchain `assume`.

**TF-08 (medium, `[coder]`) — `ci_ert` prints `PARTIAL` but exits 0.**
`tests/ci_ert.m:44` `knownPins = {}` and `:70-79` print "PARTIAL — N unexpected
filter(s)" for any filtered method; `:95` `assertSuccess(results)` passes on
filtered results (empirically: the 2026-08-04 dispatch run's system and
montecarlo steps succeeded on a Coder-less runner). The attestation's exit code
therefore does not match its verdict. *Fix:* `error('ci_ert:partial', …)` after
the table when any class is PARTIAL or ABSENT.

**TF-09 (medium, `[matlab]`) — csc-mode tests compare against the matrix mode
of the same generator and call it an FD check.** `ICscOutputTest.m:5-9` says
"the exported pattern is a superset cross-checked vs finite differences";
`checkJac` (:196-217) evaluates the matrix-mode wrapper, regenerates with
`der_output='csc'`, and asserts `adigatorCSCToSparse(csc, v) == Dm` at
`1e-12` plus the superset check, with no `fdcheck`/analytic anywhere
(`tests/helpers` is not even on the class's `PathFixture`, :15-24); `checkHes`
FD-checks only `if expectSize(1) == expectSize(2) && numel(xv) ==
expectSize(1)` (:232). `IOutputModesTest` (`:54`, `:60`, `:91`) likewise
compares csc to matrix mode at `AbsTol 0` for the vector-function
`[m·n × n]` Hessian, the plain Jacobian and the gradient. csc and matrix mode
share the derivative arithmetic (only the final projection differs), so a shared
wrong value passes: `REVIEW_CONTEXT.md` §"Drift hardening", *implementations
conform to the contract, not to each other*. Fixtures `cjd`, `cg`, `cz`, `csr`,
`csc1`, `cs11`, `clb` and the two non-square Hessians have their values checked
by no other class. `CI_PLAN.md:166` (TS-I-25) lists "FD/analytic agreement" and
maps the row to REQ-T-01. *Fix:* add `fdcheck('jac', …)` to `checkJac` (and the
closed forms for the two Hessians), or reword the header and the row.

**TF-10 (medium, `[matlab]`) — two of the five "numeric-assertion" examples
assert nothing.** `SExamplesTest.m:71-76` (brusselator): "completing without
error is the assertion (the script compares solver behavior internally)";
`examples/stiffodes/brusselator/main.m` (57 lines) generates `mybrussode_Jac`,
solves the ODE three times and prints timings — no comparison of the Jacobian
to anything, nor of the three solutions to each other (the file has no
`assert`/`norm`/`max(abs` call at all; its only tolerances are `odeset`
options). `pipg/main.m` is fourteen
lines with no assert; `SExamplesTest.m:78-92` only runs it. `CI_PLAN.md:242`
lists brusselator as "(FD comparison) | TS-S-01 assertion case" and `:188` TS-S-01
as asserting "spot values (arrowhead/polydatafit vs FD, pipg/structinput/
brusselator)". A wrong `mybrussode_Jac` makes `ode15s` take more steps and still
completes. *Fix:* assert `ws.y(end,:)` of the AD solve against the FD solve at
`RelTol 1e-6` and FD-check `mybrussode_Jac(0, y0, N)`; assert `H == 2*eye(2)`
and `G == w + 2*z` for pipg (the closed form `IEmbedModesTest` already uses).

**TF-11 (medium, `[matlab]`) — `IGenFiles4Test` pins text shape only.** All
six methods assert `checkcode` cleanliness, header regexps or field presence
(`:37-71`, `:143-160`); no generated `_Hes`/`_Grd` is ever evaluated, although
the fixtures are closed-form (`sum(x.^2)` → `2I`; constraint `x(1)x(2)+x(3)x(4)
−1` → four unit off-diagonals). The M1 defect this class pins was a broken file;
a wrong Lagrangian assembly (sign, `lambda` indexing, transposed sparse dims)
would parse fine. The family is deprecated (ADR-0037) but shipped; #156 covers
parity, not test strength. *Fix:* evaluate the wrappers at `x0` with a fixed
`lambda` and assert the closed forms at `1e-12`.

**Smaller instances, all `[matlab]` unless noted:**

- *TF-26* `IEmbedSlimTest.m:160` asserts `pinfo.count >= 0` (a tautology) and
  `:71` `verifyLessThanOrEqual(nB, nA)` accepts a no-op slim; the slim-vs-noslim
  text assertions no longer discriminate because #80's strip removes the
  metadata lines from *both* files.
- *TF-27* `ILoopboundTest.m:121` `verifyError(@() lb_guard_dx(x,Nmax+1),
  ?MException)` accepts any exception while its input has only `Nmax` entries,
  so an index-out-of-bounds error satisfies it even if the generated guard were
  removed; `IReproTest.m:91` likewise accepts `?MException` where siblings pin
  an id. `ISymbolicIndexTest.ifGuardedWhileCounterErrorsSafely` would stay
  green if #108 were fixed, contrary to its comment (pin "not
  `adigator:symbolicIndex`", `IVectorizedFenceTest` style).
- *TF-28* `IRolledOvermapWidthTest.pruneGateStaysInStepWithTheRemapGate` is a
  token-presence regexp: it passes if the two gate tokens appear anywhere in
  each file, not that they gate the same conditional (ADR-0036's "keep in step"
  obligation is therefore asserted weaker than described). `[cloud]` to
  tighten the regexp to the conditional's shape.
- *TF-29* `IEmbedSlimRolledTest` and `IConcatLoopLiteralTest` fixtures never
  assert that the generated file actually contains a rolled `for cadaforcount`
  loop, so a silently-unrolled generation would pass both. `[cloud]`
- *TF-30* `MCRegressionTest` has never executed its body: `regressions/` holds
  only a README, so the sentinel `'__none__'` (`:44`, `:82`) reports one
  *Filtered* result per run and the reproducer-consumption path (`feval`,
  `mcCase` rebuild, frozen `expected` compare) is untested dead code. A
  committed synthetic reproducer would exercise it. `[cloud]` to write, `[matlab]`
  to confirm.
- *TF-31* `MCSmokeTest.derOutputInvarianceIsClean` draws from
  `{Affine, Quadratic}` but the oracle is Jacobian-only, so half its cases skip
  by construction; `codegenEquivalenceIsClean` runs `nIters = 2`; the
  Hessian/gradient csc forms are never fuzzed.
- *TF-32* `IInterprocGapEquivTest`'s header describes "a genuinely sliced
  interprocedural file"; the committed `slim0`/`slim1` derivative *code* is
  byte-identical (the diff is the header stamps and one `Index7` data line), so
  the `AbsTol 0` equivalence guards the data prune, not a code slice (which
  `USlimDerivFileTest`/`IEmbedSlimRolledTest` do pin). `[cloud]` wording fix.
- *TF-33* `UTestPathHygieneTest` scans `tests/unit` and `tests/integration`
  only; `tests/system` and `tests/montecarlo` classes are unguarded for
  path-setup presence. `[cloud]`
- *TF-34* Reverse-gradient and JtV wrappers carry no #200 generation stamp
  (`adigatorGenRevGradFile`/`adigatorGenJtVFile` never call
  `cadaPrintGeneratedHeader`), although `UGenerationStampTest` describes the
  stamp as carried by "every generated file"; `IGuideFixturesTest`'s
  byte-compare of `lse_cost_RGrd.m` relies on that absence. `[matlab]`

### 2.4 What a green hosted job does not prove

For the record, the set of methods that **always** filter on hosted CI (no
Coder/ERT/CasADi/gcc licence): `SCodegenTest` (6), `SRolledErtCodegenTest` (2),
`SStackScalingTest` (4), `SGenericBoundFoldingTest` (2),
`SCodegenShowcaseTest` (1), `SLoopboundPaddingTest` (1), `SCasadiOracleTest`
(1), `MCSmokeTest/codegenEquivalenceIsClean`, and the `MCRegressionTest`
sentinel. Of the compiled-value checks, only `SCodegenTest`'s MEX equivalence
(`1e-14`) and the Monte-Carlo codegen oracle (two iterations) compare
*numbers*; `SCodegenTest.ertLib*` (3) and `SRolledErtCodegenTest` (2) are
exit-success only. All of these are `[coder]` local-only by design
(`CI_PLAN.md` §3.2); the point of listing them is that, combined with TF-01,
**nothing in `tests/system` or `tests/montecarlo` has run on a merged commit
since June, licence-free or not.** Also measured: the gcc/size probe in
`bench/measureErtFootprint.m` and `SGenericBoundFoldingTest` is Windows/MinGW
only (`gcc.exe`, `size.exe`, `cd /d`), so the stack and ROM gates can be
established on a Windows machine only, while `CONTRIBUTING.md` describes a
generic "standalone gcc/size toolchain" (TF-35, `[cloud]` to document or
`[coder]` to port the probe).

---
## 3. Functionality not fully covered

Method: every `@cada`/`@cadastruct` overload (files **and** the 94 methods
defined inside `lib/@cada/cada.m`), every option in `adigatorOptions.m`, every
DerType and every generator was cross-referenced against the *fixture strings*
of every test (comment lines stripped, harness uses excluded by reading each
hit) and the example function files. "No value oracle" below means no test
compares the derivative of that operation to an analytic or finite-difference
reference; "no test" means not even a smoke. The `docs/vv/cada-surface-
inventory.md` worklist was taken as the starting point and is corrected where it
has drifted.

### 3.1 Derivative-rule coverage

**CG-01 (high, `[matlab]`) — six of the eleven binary rules have no value
oracle.** `lib/@cada/cada.m:432-466` defines `atan2`, `ldivide`, `mod`,
`plus`, `power`, `rdivide`, `rem`, `times`, `minus` (plus external `max`/
`min`). `tests/unit/URulesBinaryTest.m:38-86` has exactly `plus_col`,
`plus_scalar`, `minus_cf`, `times_col`, `times_scalar`, `times_xx`,
`rdiv_num`, `rdiv_den`, `rdiv_both`, `pow_int` (`x .^ 3`), `pow_col` (`x .^
[2;3;2]`), `mtimes_A`, `scalar_vod`; its header says "power/.^ with an inactive
exponent". The `getdzdy` rules for `power` (`log(x).*x.^y.*dy`), `atan2`,
`mod`, `rem`, `max`, `min` (`cadabinaryarraymath.m:673-684`) and the `getdzdx`
rules for `atan2`/`max`/`min` (`:651-656`) are executed by no value-checked
test: fixture-string scan over `tests/**` finds `atan2`, `mod`, `rem`, `ldivide`
**nowhere**, and `max(`/`min(` only as derivative-free index arithmetic in
`ISymbolicIndexTest.m:38,61`. The Monte-Carlo generators emit only `+ − .*`
(`mcGenExprTree.m:20-21`) and `.*`, `.^2`, `+`, `−` (`mcGenShapeFuzz.m:20-27`).
`REQ-C-02` (`CI_PLAN.md:90`) promises "every binary rule (incl. `atan2`,
`power`, …)"; its sole verifying row TS-U-02 (`:113`) scopes `power` to an
inactive exponent and omits the rest. This is the gap that hid BG-01. Active-
exponent `power` is a classic silent-NaN site (`x ≤ 0`), and `max`/`min` at a
tie emit `(x == max(x,y)).*dx` for both operands (double counting), both
untested.

*Fix:* parameterise `URulesBinaryTest` over {rule} × {operand pattern}: rules
`atan2, mod, rem, ldivide, power, max, min, times, rdivide, plus, minus`;
patterns `x op const-vector`, `const-vector op x`, `x op scalar-active
(x(1)+c)`, `x op x`, `scalar-active op x`, plus a `[1 3]` row and a `[2 2]`
matrix variable of differentiation. Sample away from kinks (non-integer `x./y`
for `mod`/`rem`, `x > 0` for active-exponent `power`, no ties for `max`/`min`).
Oracle `fdcheck('jac')` at `1e-5`. Then correct TS-U-02.

**CG-02 (high, `[matlab]`) — unary coverage is scalar-only.**
`URulesUnaryTest.m:59` creates the only input shape, `[1 1]` (the legacy
harness is identical, `test_unarymath_rules.m:50`). `cadaunarymath.m:60-77`
selects the emitted derivative operand by shape: scalar `x.func.name`, full
vector `x(:)`, and the sparse-gather path `cada…tf1 = x(idx)` plus the
vectorized `x(:,idx)`/`.'` forms; a scalar input never reaches the gather or
vectorized branches. Vector-shaped unary ops appear under AD only for `sin`,
`cos`, `exp`, `tanh`, `atan` (the Monte-Carlo op tables and the
`IShapeMatrixTest` fixtures), so the gather branch, exactly where an index-table
mistake would misplace a derivative while the scalar form stays right, is
exercised for five of 42 rules. The twelve non-table unary methods have no
value test at all: `ceil`/`fix`/`floor`/`round` zero the operand's derivatives
and call `cadaCancelDerivs` in the first pass (`cada.m:201-212, 262-287,
308-319`); `sign` emits an identifier-less warning (`:333-343`); `full`/`real`/
`imag`/`conj` print `callerstr(dx)`; `uminus`/`uplus`; `angle`. The derivative-
cancelling family is the only place the engine deliberately zeroes derivatives;
an off-by-one in `cadaCancelDerivs` (`numvars` from `find(NAMELOCS(:,1),1,
'last')`) would drop derivatives of unrelated variables and nothing guards it.

*Fix:* parameterise `URulesUnaryTest` over `xshape ∈ {[1 1],[3 1],[1 3],[2 2]}`
and a sparse-seed variant (`xx.dx` seeding only entries 1 and 3 so the gather
branch prints), reconstructing with `reconstructUnrolled` + `fdcheck`; add a
`UDerivFreeUnaryTest` (`floor`/`ceil`/`round`/`fix` inside a product at
non-integer points vs FD; `sign(x).*x.^2` with `verifyWarning` once the warning
has an id; `[real(x); imag(x); conj(x); full(x); -x; +x]` vs the identity/
negation Jacobian at `AbsTol 0`).

**CG-03 (medium, `[matlab]`) — fourteen shipped `@cada` overloads have no value
oracle in any test:** `interp1`, `interp2`, `ppval`, `adigatorEvalInterp2pp`,
`cross`, `inv`, `mrdivide`, `prod`, `nnz`, `sub2ind`, `isequal`/
`isequalwithequalnans`, `num2str`, `dot`, `fliplr`/`flipud`, `nonzeros`,
`repmat`; `mldivide` with an active left operand only in polydatafit (TF-05).
Call-site scan: `interp1` appears only in example function files that no test
runs (brachistochrone, minimumclimb, DCALcontrol are in `SExamplesTest`'s
`smokeOnly` list, `:118-139`); `prod(` only as an *oracle* (`IRevGradTest.m:122`,
the fixture is a loop); `repmat(` only in emitted-data text
(`UEmbedMfileTest.m:122`) and unrun examples; the rest nowhere under AD. The
private kernels `cadainversederiv` (← `inv`/`mldivide`/`mrdivide`) and
`cadamtimesderivvec` (← vectorized `mtimes`) are at 0% per the inventory and
that is still true. *Fix:* one `UHighLevelOpsTest` with `fdcheck` at `1e-5`:
`interp1(xb,yb,x)` with constant breakpoints/active query **and** active
`yb`/constant query; `interp2(X,Y,Z,x(1),x(2))`; `A = [x(1) 1; 2 x(2)]` with
`inv(A)*b`, `A\b`, `c/A`; `cross(x(1:3),[1;2;3])` and `cross(x, x([2 3 1]))`;
`prod(x)`; `repmat`; `fliplr`/`flipud`; `dot`; `nonzeros(sparse(…))`; and `nnz`/
`sub2ind`/`isequal` on value paths asserting the surrounding derivative is
intact. Add the `repmat`/`mldivide` fixtures `REQ-C-03` names to
`UStructuralOpsTest`.

**CG-04 (medium, `[matlab]`) — `@cadastruct` struct-array overloads.** Only
`vertcat`/`horzcat`/`ctranspose` are value-checked (`IStructArrayNamingTest.m:
59,75,134-148`); `transpose`, `reshape`, `repmat`, `size`, `length`, `ppval`,
`struct` and `subsasgn` on struct arrays have none. The inventory still lists
the three covered ones at 0% (`cada-surface-inventory.md:46,120`), and records
that `transpose`/`reshape`/`repmat` name their result with the `NVAROFDIFF`
spelling `ANALYSIS.md` §1.3g flags as principle-1 relevant ("the open follow-up
to harmonize those three"). *Fix:* extend `IStructArrayNamingTest` with
`s.'`, `reshape([s;s],1,2)`, `repmat(s,2,1)`, `size`/`length` on struct arrays,
through a named variable **and** the unnamed-intermediate arm
(`hlp(repmat(s,2,1))`), vs analytic at `1e-12`; refresh the inventory rows.

**CG-05 (medium, `[cloud]`) — the surface inventory is file-granular, so the
94 methods inside `cada.m` are invisible to the V&V denominator.** The
inventory's full classification (`:112-118`) names files only; `cada (56.5)`
appears once as "machinery"; `atan2`, `mod`, `rem`, `ldivide`, `dot`, `norm`,
`fliplr`/`flipud`, `num2str`, `end`, the nine comparisons and the zero-
derivative family are nowhere in it, so its headline "no `@cada` op is
whole-op untested" is unverified for them (and false for the six binary rules
of CG-01). `CI_PLAN.md:128` (TS-U-17) refers to "the `@cada/norm` overload";
`norm` is `cada.m:626`, there is no `lib/@cada/norm.m`. *Fix:* add a
"`cada.m` methods" table to the inventory (dispatch target, zeroflag, value-
oracle test or NONE), fold CG-01/02 into the worklist, correct TS-U-17's
wording.

**CG-06 (medium, `[matlab]`) — comparison/logical overloads and derivative flow
through masks are untested.** Fixture scan for `x > c`-style comparisons on an
active operand: the single hit is `ISymbolicIndexTest.m:64`, a derivative-free
index compare. The only predicate test, `UNormTest.predicatesAreDerivativeFree`
(`:118-128`), exercises `|`/`~` on `isnan`/`isinf` predicates. The
`cadabinaryarraymath.m:121-139` "Logical Reference Check" (`z = x(x>y).*y(x>y)
is not …` error) and the `logicref` propagation in `cadaunarymath.m:33-35`
are never reached. *Fix:* `UMaskOpsTest` with `x.*(x > 0.5)`, `x.*(x >=
[0.2;0.6;1.0])`, `ind = x > 0.5; y = x(ind).^2`, `sum(x.*(x > 0.5 & x < 1.5))`,
`all`/`any`/`xor` forms vs `fdcheck` away from thresholds, plus the negative
`logicref` case with an identifier.

**CG-07 (low, `[matlab]`) — `UNormTest` covers fewer cells than TS-U-17
claims:** row orientation only for `p = 2`; general `p` (`cada.m:697`
`sum(abs(x).^p).^(1/p)`) and vector `p = -Inf` never value-checked;
`adigator:norm:badp` (`:673, :677`) untested; the complex arms need
`complex=1` (CG-10). *Fix:* loop `orient × specs {2,1,Inf,-Inf,3,0.5,'fro'}`;
add the two `badp` error cases.

**CG-08 (low, `[matlab]`) — reverse-mode adjoints for `tan`, `sqrt`, `sinh`,
`cosh`, `asin`, `acos` are whitelisted and emitted
(`adigatorGenRevGradFile.m:304-305, 700-716`) but never value-checked:
`IRevGradTest` uses `log`/`exp`/`sum`/`mtimes`/`.^`; `mcGenScalarSum`'s op table
is `sin, cos, tanh, atan, exp`. The 14-vs-42 forward/reverse support asymmetry
is stated only in the m-file help (#206 is the tracking issue). *Fix:* extend
`mcGenScalarSum` to the full whitelist with domain-safe sampling; one
deterministic `IRevGradTest` fixture `sum(sqrt(x) + tan(x) + asin(x/3))`.

### 3.2 Option, DerType and construct coverage

**CG-09 (medium, `[matlab]`) — no test or example ever differentiates a
`while` loop successfully.** All four `while` fixtures (`ISymbolicIndexTest.m:
87,141,174,200`) assert an error; `maxwhileiter` appears in no test; the
fixed-point search (`adigatorForInitialize.m:29`) and its exhaustion error
(`adigatorForIterEnd.m:565`, identifier-less, cf. #246) are exercised neither
way. A `while` whose body carries derivatives but whose counter is not an
index is a supported, documented construct (`adigatorOptions` MAXWHILEITER);
a wrong fixed point would be a silent wrong derivative. *Fix:* `IWhileLoopTest`
with `s = 0; p = x(1); n = 1; while n <= 3, s = s + p; p = p.*x(1); n = n+1; end`
vs `1 + 2x + 3x²` at `1e-12`, a vector variant, and `maxwhileiter = 1` →
`verifyError` once the error has an id.

**CG-10 (medium, `[matlab]`) — option/DerType cells with no value-checked
test:** `complex = 1` (switches real code paths in `abs`, `ctranspose`, `dot`,
`norm`: `cada.m:119, 594, 617, 654, 690`; the only occurrence in tests is a
stamp-text fixture with value 0); `auxdata = 1` with `adigatorGenJacFile`/
`GenHesFile` (only via the deprecated Fmincon wrapper); `gradient-reverse ×
der_output='csc'` (no fixture); any `[1 n]` row-vector variable of
differentiation beyond `UNormTest.m:57` (TS-I-01 claims row-vector inputs,
`CI_PLAN.md:142,246-249`); Hessian × `unroll = 1` outside the extended-only
showcase and CasADi battery; `comments = 0`; the undocumented `optoutput`/
`genpat`. `adigatorGenJtVFile` is tested classic-only and the embedded DerType
switch (`adigatorGenDerFile_embedded.m:123-129`) has no `jtv` case, an N/A by
omission rather than by statement. *Fix:* publish the `(DerType × embed_mode ×
der_output × der_levels × unroll × loopbound × slim_embed × input topology)`
support matrix (R25 phase 2 promised it) with each cell a test method, an
"N/A: reason", or UNTESTED; add `UComplexOptionTest` (`complex=1` on real data
must equal `complex=0` at `1e-12`, a cheap consistency oracle), an `auxdata=1`
case vs FD, a `[1 n]` variant in `IShapeMatrixTest`/`ICscOutputTest`, and a
reverse × csc case.

**CG-11 (medium, `[matlab]`) — vectorized (`Inf`-dimension) mode has one
value-checked fixture** (`IAllocationTest`, Jacobian/gradient only) and no
vectorized Hessian check; the nine GPOPS-II vectorized example entry points
(brachistochrone ×5, minimumclimb ×4) plus the vectorized allocation main are in
`SExamplesTest`'s `smokeOnly` list and `examples/runAllExamples.m` is invoked by
no workflow or `ci_*` script. `CI_PLAN.md:504` scopes vectorized testing to
"what the examples cover", which is therefore nothing automated. The vectorized
`mtimes` kernel is at 0%. *Fix:* curate `main_vect_1stderivs`/`_2ndderivs`
into `SExamplesTest` with a central-FD assertion; add `IVectorizedTest` (`[Inf
3]` input, Jacobian and Hessian vs analytic at two runtime `N`, one `[Inf 1] *
constant-matrix` product).

**CG-12 (medium, `[matlab]`) — third order is value-checked by exactly one
fixture** (`ISpecializedTripCountTest.guardSurvivesToThirdDerivative`, a loop of
`x^3`). No test re-differentiates any unary/binary rule expression even once
beyond `sin`/`exp`/`x²`: the emitted first-derivative expressions of the other
37 unary rules (`sec(x).^2`, `1./x.^2./sqrt(1-1./x.^2)`, `-pi/180.*cscd(x).^2`,
…) are never themselves differentiated under test, so an overload missing or
wrong for a function that appears only inside an emitted rule (`sec`, `csc`,
`cot`, `sech`, `csch`, `coth`, `sind`…`cscd`, `sign`) would surface only in a
user's Hessian. R22/TS-I-10 cover the n-th-order *fold shape*, not rule
correctness. *Fix:* `UHigherOrderRulesTest`: for each rule generate `_dx`,
re-differentiate once and twice with the `struct('f',gx,'dx',1)` idiom, compare
`dxdx`/`dxdxdx` to central FD of the previous-order file at the TS-U-01 points.

**CG-13 (low, `[cloud]`/`[matlab]`) — platform/path handling.** The
Windows-only branch `adigator.m:1262-1268` (`if strcmp(filesep,'\')` …
`regexp(…,[filesep,filesep,UserFunName,'.m$'])`) followed by `CFswap =
CalledFunctions{thisIsIt}` (`:1275`, `thisIsIt` undefined if nothing matched)
runs on no CI runner; `CI_PLAN.md:501-503` says the historical `filesep` issues
"are covered by tests running through `fullfile`", which on Linux never yields a
backslash. No test generates into a path with a space or non-ASCII character
(83 test files use `fullfile`; none builds such a folder). *Fix:* reword
`CI_PLAN.md:503`; add `UPathHygieneTest` (`adigatorOptions('path',
fullfile(tmp,'dir with space','ünïcode'))`, REQ-T-06); consider a
`windows-latest` unit+integration leg once TF-01 is repaired.

### 3.3 Generators, examples and error paths

**CG-14 (medium, `[matlab]`) — 21 of 26 example entry points run in no test,
and the sweep script is wired to nothing.** `SExamplesTest` curates five
(arrowhead, polydatafit, brusselator, pipg, structinput) and acknowledges the
rest as `smokeOnly` (`:118-139`); the Optimization Toolbox examples never
execute in CI (the `full-products` job is in TF-01's workflow); `runAllExamples`
is invoked by no workflow or `ci_*` script. REQ-T-08 ("all shipped examples
shall run headless") is validated for five. `DCALcontrol/main.m` and the
brachistochrone/minimumclimb mains contain `figure`/`plot` calls (headless
fitness unverified). *Fix:* a parameterised smoke over `discoverExamples()`
with `requires`-gating, run in the Extended job; curate the vectorized mains
(CG-11).

**CG-15 (low, `[matlab]`) — the deprecated `GenFiles4*` family:** parse/
field/banner pins only (TF-11); `adigatorGenFiles4Fsolve` and
`adigatorGenFiles4gpops2` have no test at all; four `adigator:genfiles4*:io`
ids untested. *Fix:* one numeric assertion per wrapper, or an ADR-0037 note
that the family carries no numeric pin and its examples are excluded from
REQ-T-08.

**CG-16 (medium, `[cloud]` list + `[matlab]` tests) — 25 of 68 `adigator:*`
error identifiers have no test that triggers them, and ~400 `error(` sites
carry no identifier at all.** Census (regexp over `lib/**`, `util/**`,
`embedding/**`, `adigator*.m`): 68 distinct ids; untested include
`adigator:norm:badp`, `adigator:ppval:unnamedPP`,
`adigator:ndparam:subsOutOfRange` (`subsref.m:351,358,389`, the N-D declared-
extent check added with B25, whose fall-through would read the wrong fold
column), `adigator:revgrad:{parse,exec,io}`, `adigator:cadastruct:remap`,
`adigator:cadaPrintReMap:idlessWithDeriv`, `adigator:cadafuncname:emptyVarID`,
`adigator:genjac:io`, `adigator:genhes:io`, the four `genfiles4` ids,
`adigator_patch_derivative:headerNotFound`, `structure_to_embed_mfile:io`,
`emit_data_helper_file:unsupported`, and seven re-raised `MATLAB:chckxy:*`.
Separately, of 509 `error(` calls in the toolbox source, 399 have no
identifier-shaped first argument (per-file: `adigatorAnalyzeForData` 23,
`@cada/subsasgn` 17, `@cada/repmat` 16, `adigator.m` 16, `@cadastruct/repmat`
15, `@cada/subsref` 13, …); B40 records the vectorized fence's eleven, #246 one
more. REQ-T-07 asks for "clean errors". *Fix:* publish the untested-id list;
add `verifyError` cases per id (the `subsOutOfRange` three first); adopt a
namespace policy and convert the id-less sites in the files above opportunistically
(an `error`-without-id lint in `ci_lint` keeps the count from growing).

**CG-17 (medium, `[matlab]`) — the Monte-Carlo vocabulary is far narrower than
its description.** Every generator fixes `xsize = [n 1]`; op vocabularies are
`sin, cos, tanh, atan, exp` (`mcGenElementwise.m:14-19`, `mcGenScalarSum.m:
11-16`) and `sin, cos, scaled-exp, square, negate` with `+ − .*`
(`mcGenExprTree.m:20-21`); no generator emits `./`, `.^` with a non-2 exponent,
`atan2`/`mod`/`rem`/`max`/`min`, any of the other 37 unary rules, `mrdivide`/
`mldivide`/`inv`, `interp*`, or a `[1 n]`/`[m n]`/struct/vectorized input.
`REQ-T-09` describes "randomized function bodies, input/output shapes, sizes,
densities, embed modes" and ROADMAP R14 "typed expression-tree synthesis …
over the rule tables"; with a five-op vocabulary the battery cannot reach the
binary rule in BG-01 or any `rdivide` chain, and R27 (#103) widens topology and
options, not ops. *Fix:* draw `unary()` from the full `getdydx` table with
per-rule domain-safe sampling, add `./`, `.^` (constant and active exponent),
`atan2`, `mod`/`rem`, `max`/`min` to `binop()`, add an `xshape` draw, wire into
the FD-Hessian campaign; reword R14's status to the op subset actually
synthesised.

**CG-18 (low, `[cloud]`) — two contradictions inside `CI_PLAN.md` itself:**
`REQ-C-02` requires every rule incl. `atan2`/`power` while TS-U-02 describes
inactive-exponent `power` only; `REQ-C-03` names `repmat`/`mldivide` that
TS-U-03 omits. Also `§2.4a:244` claims an `adigatorColor`/`adigatorUncompressJac`
round-trip "inside TS-I-01"; neither function is referenced by any test or
example (grep over `tests/`, `examples/`): an untested shipped utility.

---
## 4. Bug candidates

**Read this first.** Every entry below is a *candidate*: found by reading the
source and, where marked "Octave run", reproduced by executing the engine in
GNU Octave 8.4 on a scratch copy that carries only the four portability
patches of §7.3 (none of which touch the code paths named here; the patched
files and lines are listed in Appendix B). The Octave runs generate the
derivative file with the unmodified rule/engine code and compare the file's
output to central finite differences or a closed form in a fresh process per
generation. That is strong evidence, and seven candidates were re-run or re-read
directly by the orchestrating session (BG-02, BG-06, BG-11 and BG-39 re-run
in Octave; BG-01, BG-04 and BG-05 re-read in the source; Appendix B); it was
**not a MATLAB reproduction** when written. Each entry therefore ends with the
MATLAB reproduction to run (`[matlab]`). None has been entered into
`ANALYSIS.md`; the maintainer assigns `Bnn` numbers after reproduction (WP-M1,
WP-M10). Grading follows `REVIEW_CONTEXT.md` principle 1: a silently wrong
derivative outranks a crash.

**MATLAB reproduction (review of PR #250, 2026-10-07).** The reviewing
session ran the §4.1 candidates in MATLAB R2024a from this PR's head (engine
code identical to `a4e24bc`; only `docs/analyses/*` differs), in a
scratch folder with `fdcheck` as the oracle, and posted the results on the
PR. They are recorded here as the review's data, not the orchestrating
session's; the snapshot stays anchored at `a4e24bc`.

| Candidate | MATLAB R2024a (review) |
|---|---|
| BG-01 `mod(x, x(1)+2.5)` | wrong: `J = I` vs FD `[1 0 0; −1 1 0; −2 0 1]` (the `rem` sibling is correct) |
| BG-02 `sum(X,2)` and `X*ones(2,1)` | wrong: `[4 1; 6 1]` vs `[3 1; 7 1]`, as the entry states |
| BG-03 `cross(reshape(x,3,2), C, 1)`, `3×4` | wrong: rows permuted (errors of 7 and 17) |
| BG-04 overdetermined `A\b` | through `adigator()`: no `y.dx` field at all (silent); through `adigatorGenJacFile`: `MATLAB:badsubscript` at `adigatorGenJacFile.m:382` (loud but uninformative) |
| BG-05 (a) mask, (b) `if` fold | (a) `dw1/dx5` lost; (b) wrong branch, and the value is wrong too (`3x` vs `2x`) |
| BG-06 identity block; rotation idiom | both wrong, as the entry states |
| BG-10 solve sparsity | `J = [0; 1]` vs `[1; 1]` |
| BG-11 `N:-1:1` | `n = 3`: `g = [0 2 4 6]` vs `[2 4 6 0]`; `n = 2` as the entry states |
| BG-12 inner-loop Hessian | `F = 6` vs 25; MATLAB warns "Colon operands must be real scalars … will become an error" |
| BG-13 `loopbound` inner loop | `n = 3`: `F = 42` vs 36; `n = 2`: `F = 10` vs 9 |
| BG-24 `mod(7.3, x)` | generation succeeds, the generated file does not parse (`Invalid use of operator`) |
| BG-25 `[x(1) x(2) 1]/A`, `A` 2×3 | through `adigator()`: silently wrong value, `y.f = eye(2)(:)`, 4 elements where 2 are expected; through `adigatorGenJacFile`: `badsubscript`; tall `A` → `'Not coded yet'` |
| BG-39 `adigatorUncompressJac` | `[0 2; 3 0; 7 0]`, as the entry states |

Ten of the eleven candidates the review ran (BG-01..06, BG-10..13, BG-39)
reproduce as silently wrong derivatives; BG-04, the eleventh, is silent
through `adigator()`; BG-25, a §4.2 loud defect
in the first draft, returns a silently wrong value through `adigator()` and
is moved to §4.1 below; BG-01's y-only pin is blocked by BG-24 (see the
entry). The review also found one new loud defect, BG-51 (§4.2).

Provenance: with four exceptions, every candidate in §4.1–4.2 is in code
**unchanged since the upstream import** (`git blame` → `5855f6a`/`1f6ac95`).
The exceptions are fork code: BG-11 (`adigatorLoopboundMatch.m`, `6271102`,
2026-06-11), BG-13 (`adigatorForInitialize.m:366-390`, mostly `3e37ad5a`,
2026-07-11) and BG-14/BG-15 (the B36 residuals: `adigator.m:731-740` is
`8ac9527`, `adigatorPrintTempFiles.m:186-188` is `33b905e`); BG-12's
`DERNUMBER == 1` gate at `adigatorForInitialize.m:373-374` is upstream but the
block around it was restructured in `3e37ad5a`. The rest are upstream ADiGator
defects this fork inherited, which is itself a finding: the fork's bug
register (B1–B40) is entirely about fork-touched or field-reported paths, and
the rule tables were never swept.

### 4.1 Silently wrong derivative (critical) or wrong-with-no-signal (high)

**BG-01 (critical, high confidence) — `mod(x, y)` with an active *scalar*
divisor applies the `d/dy` rule only when `y == 0`.** Verified directly.
`lib/@cada/cadabinaryarraymath.m:585-593` (y-only arm):

```matlab
if strcmp(callerstr,'mod')
  % if mod, protect against y = 0 (divide by zero)
  if yscalarflag
    fprintf(fid,[indent,'cadaconditional1 = ',y.func.name,' == 0;\n']);
    fprintf(fid,[indent,'if cadaconditional1\n']);
    fprintf(fid,[indent,'    ',derivstr,' = ',getdzdy(Xstr,Ystr,DYstr,callerstr),';\n']);
    fprintf(fid,[indent,'else\n']);
    fprintf(fid,[indent,'    ',derivstr,' = zeros(%1.0d,1);\n'],nzy);
```

and the both-active arm `:411-417` adds the `d/dy` term inside `if
cadaconditional1`. The rule itself (`getdzdy` `'mod'` → `-floor(x./y).*dy`,
`:677`) is right; the guard is inverted, so for every `y ≠ 0` the divisor's
contribution is zero and at `y == 0` it is `-floor(±Inf)·dy`. The vector-`y`
arms (`TD2(Ystr == 0) = 0`) are correct. Octave emulation of the emitted text:
`x = [2.3;5.7;−1.2;9.9]`, `y = 1.7`: rule `[−1;−3;1;−5]` matches FD to `5e-9`;
emitted scalar form `[0;0;0;0]`. No test uses `mod` on an active operand
(CG-01). *Fix:* swap the arms (or reuse the vector form). *Pin:* `y = mod(x,
x(1)+2.5)` (both active), `y = mod([7;8;9], x(1))` (y only), `y = mod(x,
1.7*ones(3,1)+x)` vs `fdcheck` away from the floor steps; `rem` siblings.
*MATLAB repro:* generate the first and compare to FD (R2024a, review of this
PR: `J = I` vs FD `[1 0 0; −1 1 0; −2 0 1]`; the `rem` sibling is correct).
The y-only pin `mod([7;8;9], x(1))` cannot reach this bug until BG-24 is
fixed: its generated file does not parse, so M1 orders BG-24 before BG-01.
`[matlab]`

**BG-02 (critical, high) — `sum(X, 2)` on a matrix emits the derivative in
the wrong order when a variable touches a non-monotone set of entries.**
Re-run directly: `X = x(1)*[1 2;3 4] + x(2)*[0 1;1 0]; y = sum(X,2)` at
`x = [0.7; 1.3]` → generated `J = [4 1; 6 1]`, FD `[3 1; 7 1]` (the column sums
instead of the row sums for `x(1)`). `lib/@cada/sum.m:199-219` builds the
`Dim == 2` derivative pattern by transposing the reference and calling
`[xrows, xcols] = find(dxtR)` (`:215`), which returns the pattern in
transposed order, but the runtime vector `dx` stays in `nzlocs` order and the
third output of `find` is never used to re-sort before printing
(`:240` copies `dx` outright when `nzx == nzy`; `:253` and `:258-261` scatter
it by `K = (xcols-1)*xdim + xrows`). `cadamtimesderiv.m:117-119` does the
`sortrows` that `sum.m` lacks. The `Dim == 1` branch is right (reshape keeps
linear order). The finder's other runs: `X = [0 x; x^2 0]` → `[3;1]` vs
`[1;3]`; `2×3` case `[7;14]` vs `[6;15]`; `20×15` sparse-projection branch
error `2e3`; `X*ones(2,1)` (which `mtimes.m:141-144` routes through `sum`)
same wrong `[4;6]`; `dot(·,·,2)` reaches it too. Cases where each variable
touches one row/column pass, which is why the existing fixtures (`sum(x)`,
`sum(x.^2)`) never saw it. *Fix:* keep `find`'s third output and reorder
(`[xrows,xcols,xind] = find(dxtR); [~,ord] = sort(xind); …`), and in the
`nzx == nzy` case print the permutation rather than `dy = dx`. *Pin:*
`sum(x(1)*C, 2)`, `sum(x*x.', 2)`, `X*ones(n,1)`, `dot(X,C,2)`, a `≥ 250`-
element case for the sparse branch, in `UStructuralOpsTest`. `[matlab]`

**BG-03 (critical, high) — `cross(X, Y, 1)` on a `3×N` matrix with `N ∉
{1, 3}` applies the row permutation in the wrong direction.**
`lib/@cada/cross.m:116-119` builds `tranref = refInds.'; tranref =
tranref(:)` (the *forward* component-major → column-major map) and then uses
it as an index, `dxL = dxL(tranref,:)` (`:230`, likewise `:237, :244, :251`
and the reference vectors at `:287, :341, :395, :449`), which needs the
*inverse* map; the two coincide only for involutions (`N = 1`, `N = 3`).
Octave runs: `cross(reshape(x,3,2), C, 1)` → rows 2–5 of `J` swapped vs FD
(max error 6); both operands active, `3×4`, y-only all wrong; `3×1`, `2×3`
along dim 2, `3×3` pass. A Hessian file of `sum(cross(X,C,1)(:).^2)` returns
the wrong `Grd` (`[112 6 −26 72 −12 −16]` vs FD `[26 8 −10 168 0 −56]`) while
`Hes` happens to match (`(P·dc)ᵀ(P·dc)` is permutation-invariant). `cross` is
at 0% coverage. *Fix:* `tranref = reshape(1:FMrow*FNcol, FNcol, FMrow).';
tranref = tranref(:)` (the inverse) with consumers unchanged. *Pin:* `3×2`,
`3×4` along dim 1 and `2×3`, `4×3` along dim 2, x-only/y-only/both, with
both operand kinds: an *inline-literal* constant operand does not reach this
bug today, generation fails first on an undefined `xvec` (BG-51, §4.2).
`[matlab]`

**BG-04 (critical, high) — overdetermined `A\b` with constant `A` and active
`b` emits no derivative at all.** Source structure verified:
`lib/@cada/mldivide.m:230` opens the `xMrow > xNcol` branch, whose only
derivative arm is `if ~isempty(x.deriv(Vcount).nzlocs) … else error('not coded
yet') end` (`:239-384`); there is no `y`-only arm, unlike the square branch
(`:215-228`). With `A` constant the `if` is skipped silently, the file has
`z.f = A.f\b.f;` and no `z.dx`, so the Jacobian is zero. Octave run: `A =
[1 2;3 4;1 1]`, `b = [x1;x2;3]` → `J = zeros(2,2)` vs FD `[−1.5 0.5; 1.167
−0.167]`. Non-square `mrdivide` (`mrdivide.m:88`, `v3 = v2\v1`) reaches the
same hole (and BG-25 first). MATLAB R2024a (review of this PR): through
`adigator()` the file has no `y.dx` field at all — silent; through
`adigatorGenJacFile` the wrapper fails with `MATLAB:badsubscript` at
`adigatorGenJacFile.m:382` — loud but uninformative. The repro must run both
entry points. *Fix:* add the `elseif ~isempty(y.deriv…)` arm
using `cadamtimesderiv(x,y,…,'mldivide')` (expected `dz/db = pinv(A)`);
likewise or keep the loud error for the underdetermined branch. *Pin:* tall
constant `A`, active `b` (vector and matrix RHS) vs `pinv(A)`. `[matlab]`

**BG-25 (critical, high) — non-square `x/y` prints its three temporaries
under one name and returns a silently wrong *value* through `adigator()`.**
`mrdivide.m:81-91` with `cadafuncname.m:31-36`: the branch resets
`VARINFO.COUNT` before each of `x.'`, `y.'` and `y.'\x.'`, so all three print
as the same name and the file contains `cada1f1 = cada1f1\cada1f1`. MATLAB
R2024a (review of this PR): `[x(1) x(2) 1]/A` with constant `2×3` `A` →
`y.f = eye(2)(:)`, four elements where two are expected, no derivative, no
error; through `adigatorGenJacFile` a `MATLAB:badsubscript`; tall `A` →
`'Not coded yet'`. Listed as a loud defect in the first draft of this
document; moved here on the review's evidence (principle 1). *Fix:* distinct
temporaries (as `mldivide` does with `TF3`/`TF4`), then BG-04 for the
derivative. *Pin:* wide and tall constant `A` vs `pinv(A)`, through both entry
points. `[matlab]`

**BG-05 (critical, high) — `cadabinarylogical` builds the *second* operand's
known-zero mask from the *first* operand's zero locations.** Verified directly,
`lib/@cada/cadabinarylogical.m:108-112`:

```matlab
if ~isempty(y.func.value)
  ytemp = logical(y.func.value);
elseif ~isempty(x.func.zerolocs)
  ytemp = true(yMrow,yNcol);
  ytemp(x.func.zerolocs) = false;
```

(the `x` block above it is the correct template). For `or` (`ztemp =
or(xtemp,ytemp)`) and `ne` (`ztemp(~xtemp & ~ytemp) = false`) the result is
marked structurally false wherever `x` is structurally zero regardless of
`y`. Two consequences, both reproduced: (a) `z.func.zerolocs` drives
`cadabinaryarraymath`'s zero-flag cancellation (`:203-207`), so `a = [0;1].*
x(1:2); b = [1;0].*x(3:4); z = a | b; w = z.*x(5:6)` loses `dw1/dx5` (`J` row 1
= 0, FD 1; `w.f` correct); (b) `subsref.m:184-187` promotes an all-zero
reference to a *known* value and `adigatorIfInitialize` folds a known
condition, so `a = zeros(2,1); a(1) = x(1); b = [x(2);x(2)]; m = a | b; if
m(2) … else … end` is generated **without the `if`** and returns the wrong
branch (`[9 15]` vs `[6 10]`); `~=` identical; `and` and operands without
partial zero locations are correct. *Fix:* `y.func.zerolocs` at `:110-111`,
plus a bounds guard for the matrix-vs-scalar case. *Pin:* both shapes vs
analytic, and that a runtime `if cadaconditional1` is printed. `[matlab]`

**BG-06 (critical, high) — an inline numeric block in a concatenation records
its *nonzero* `(row, col)` pairs as `func.zerolocs`.** Verified directly,
`lib/@cada/vertcat.m:427-431` (`horzcat.m:435-439` identical):

```matlab
if nnz(x) < numel(x)
  [xrows,xcols] = find(x);
  ...
  y.func.zerolocs = [xrows,xcols];
```

Every other producer stores *linear indices of zero entries*
(`subsasgn.m:350` `find(~ytemp(:))`), and the consumer `vertcat.m:110`
`yTemp(iRefs{Icount}(x.func.zerolocs)) = false` indexes with the pairs as
linear indices. Only an inline literal block reaches this path (named
constants get `zerolocs = []` via `adigatorMakeNumeric`). Re-run directly:
`a = [[1 0; 0 1]; x.']; v = a*[x(1); x(2)]` → `v.f` correct, `J = [0 0; 0 1;
6 10]` vs true `[1 0; 0 1; 6 10]` (`dv1/dx1` lost). Finder's further runs:
`a.*B` loses `dv(1,1)/dx1`; `a = [x.'; [1 0]]` loses `J(2,1)`; the
**homogeneous-rotation idiom** `R = [cos(t) −sin(t) 0; sin(t) cos(t) 0; [0 0
1]]; v = R*p` loses `dv3/dp3`; and `if a(1,1) > 0.5` is **folded to false at
generation** (`[9 15]` vs `[6 10]`). No fixture has a mixed-zero literal block
inside a concatenation (only named `eye(2)`-style constants). *Fix:*
`y.func.zerolocs = find(~x(:))` in both files (shared helper). *Pin:* the four
shapes above and the rotation idiom vs analytic; that the `if` stays a runtime
branch. `[matlab]`

**BG-10 (critical, high) — solve sparsity pruned by *numeric* cancellation.**
`lib/@cada/mldivide.m:87-88` uses the constant matrix's actual values
(`xtemp = x.func.value`, where `mtimes.m:155` uses `logical(abs(…))`), and
`cadamtimesderiv.m:374-382` derives the result pattern from `dzyR =
xtemp\dyR` with `dyR` holding the index values `1..nzy`, then `find(dzy)`: a
true-nonzero combination can cancel exactly for the index-weighted one.
Octave run: `A = [0.5 0.5; 0 1]` (`inv(A) = [2 −1; 0 1]`), `b = [x1; x1]`:
`inv(A)·[1;2] = [0;2]` → location dropped, `J = [0; 1]` vs true `[1; 1]`;
`mrdivide` mirror (`b/A.'`) the same. Single-entry RHS columns are safe,
which is why the existing solve fixtures pass. *Fix:* compute solve sparsity
structurally (random positive weights on a 0/1 pattern, as the symbolic-`A`
path at `:90-96` already does), never exact index values against exact `A`.
*Pin:* the shape above and its `mrdivide` mirror. `[matlab]`

**BG-11 (critical, high) — `loopbound`: a matched loop whose loop-variable
*values* depend on the bound is padded wrongly.** Re-run directly:
`for k = N:-1:1; y = y + x(k)^2; end` with `loopbound 'N'`, `Nmax = 4`,
`x = [1;2;3;4]`: `n = 4` correct; `n = 3` value correct (14) but gradient
`[0 2 4 6]` vs true `[2 4 6 0]`; `n = 2` gradient `[0 0 2 4]` vs `[2 4 0
0]`. Mechanism: `adigatorLoopboundMatch.m:19` pairs loop and bound by trip
count *value* only; the generated file keeps the runtime values
(`cadaforvar1.f = N:-1:1; … x.f(k.f)`) but the derivative gather uses the
static per-iteration table built at `k = Nmax−j+1`. `adigatorLoopboundRangeCheck.m:47-49`
explicitly names this shape ("a shape whose loop-variable VALUES depend on the
bound … genuinely cannot be padded — but that is a different case and is not
what this check is about") and nothing refuses it. `for k = N:2*N-1` fails the
same way; `0:N-1` (values independent of `N`) is correct. Every
`ILoopboundTest`/`ISpecializedTripCountTest` fixture uses `1:N`. *Fix:* refuse
a matched loop whose range start or step mentions the bound or whose step is
negative (`adigator:loopbound:rangeshape`, with the three ways out, B39-style).
*Pin:* `N:-1:1` and `N:2*N-1` refused; `0:N-1` and `2:N+1` still generate and
match the `n`-sized program. `[matlab]`

**BG-12 (critical, high) — Hessian of a counter-dependent inner loop prints
`for c = 1:<vector>`.** `adigatorForInitialize.m:373-377` builds the dependent
header only when `DERNUMBER == 1` (comment at `:363-365`: "stays
DERNUMBER==1-only"); at second order the fall-through at `:394-397` prints `'
= 1:', UserLoopVar.func.name` where that variable is the padded range *vector*
(`adigatorPrintTempFiles.m:238-240`). Octave run: `for i = 1:3; for j = 1:i; y
= y + x(i)*x(j); end; end` through `adigatorGenHesFile`: the gradient file is
right (`F = 25`, `g = [7 8 9]`); the Hessian file contains `cada2tempf1 =
zeros(1,3); cada2tempf1(1:cada1forindex1) = 1:cada1forindex1; … for
cadaforcount2 = 1:cada2f1` and returns `F = 6`, `H = [2 1 1; 1 0 0; 1 0 0]`
(true `25`, `ones(3)+eye(3)`): exactly the `j = 1` terms. B27/§1.3e recorded
the identical `for c = 1:(1:N)` malformation for the loopbound-matched arm and
fixed only that arm. No fixture has a `1:i`-style inner bound at any order.
*Fix:* re-derive the dependent header at every `DERNUMBER`, or fail loud
(`adigator:nested:rediff`) when `isa(UserLoopVar,'cada') &&
prod(UserLoopVar.func.size) ~= 1 && isempty(LoopVarStr)`. *Pin:* the fixture
above vs `ones(n)+eye(n)` (a natural first `ISecondDerivTest` row). `[matlab]`

**BG-13 (critical, high) — `loopbound` at second order matches a
counter-dependent inner loop to the bound.** `adigatorAnalyzeForData.m:70`
sets the inner loop's `MAXLENGTH = max(ForLengths(:))` (= `Nmax` for `for j =
1:i` under `for i = 1:N`); `adigatorForInitialize.m:366-369` matches it to the
bound; at first order the dependent header wins (`:378-381`), at second order
`LoopVarStr` is empty so `:382-390` prints the runtime `1:N` header and the
inner loop runs `N` (not `i`) iterations. Octave run (`y = y + x(i)^2`,
`loopbound N`, `Nmax = 3`): gradient file right; Hessian file `n = 3`: `F =
42` (true 36), `H = diag(6,6,6)` (true `diag(2,4,6)`); `n = 2`: `F = 10`
(true 9). With `x(i)*x(j)` the padded zero of the inner range is read as an
index and it fails loud (`x(0)`). First-order `loopbound` of the same shape is
correct. *Fix:* never match a loop whose per-parent-iteration lengths vary
(`numel(unique(nonzeros(FOR(1).LENGTHS))) > 1`), give the dependent form
precedence at every order (needs BG-12), and until then refuse at `DERNUMBER
> 1` (`adigator:loopbound:dependentInner`). *Pin:* Hessian at `n = Nmax` and
`n < Nmax` vs `diag(2i)`. `[matlab]`

**BG-14 (high, high) — B36 residual: a verbatim numeric statement keeps a
main input by name.** `adigatorPrintTempFiles.m:186-188` harvests trip-count
candidates only inside the `for` branch, and `adigatorVarAnalyzer.m:233-237`
prints a numeric assignment verbatim. Octave run: `idx = 1:N; y =
sum(x(idx))`, generated at `N = 4` with `x` `6×1`: the file has `idx.f = 1:N;`
and no `assert`; called with `n = 5` the value is right (15) and the gradient
is `[1 1 1 1 0 0]` vs `[1 1 1 1 1 0]`. §1.3j's residual list (routes 1–4) does
not include a non-loop verbatim statement. *Fix:* harvest identifiers from
every verbatim-printed numeric statement in the main function into
`TRIPCOUNTCANDIDATES` (the `adigator.m:725-745` filter then emits `assert(N
== n)`). *Pin:* the fixture gets a guard; an `n = 5` call asserts. `[matlab]`

**BG-15 (high, high) — B36 residual: a local alias of the trip count.** `M =
N; for k = 1:M` generates `M = N; cadaforvar1.f = 1:M; for cadaforcount1 =
1:4` with no `assert` (the harvest keeps only names that are main inputs,
`adigator.m:731-740`); an `n = 5` call silently returns the `n = 4` result
(`30` vs `55`). §1.3m records one-hop indirection as a residual of the
*loopbound refusal* only. *Fix:* resolve one hop of verbatim numeric aliasing
in the main function; add the route to §1.3j. *Pin:* `assert(N == 4)` is
emitted. `[matlab]`

**BG-16 (high, high) — `interp1` with a multi-column `Y` prints the index
table in place of `xi`'s derivative.** `lib/@cada/interp1.m:218, 220` print
`x.deriv(Vcount).name` where `x` is the *breakpoint* vector; the differentiated
variable is `xi`. Octave run (`xb = 0:0.5:3`, `yb` `7×2`): generated `cada1td1
= (Gator1Data.Index1); … yi.dx = cada1tf2(:).*cada1td1;` — the derivative
multiplies the index table `[1;1]`, so the result is right only for a unit
seed (`x.dx = 2` returns the same `dx` as `x.dx = 1`; a Hessian file would be
wrong). `ppval.m:229, 231` reference `x`, which is not a variable in `ppval`
at all (loud `undefined` at generation for `pp.dim > 1`). *Fix:*
`xi.deriv(Vcount).name` at the four sites. *Pin:* `interp1` with 2-column `Y`
evaluated with a non-unit seed and through `adigatorGenHesFile`; `ppval` with
`pp.dim = 2`. `[matlab]`

**BG-17 (high, *medium* confidence) — Hessian wrong for a sparse-patterned
symbolic `6×6` `A` through `inv`/`mldivide` combined with `sum(sum(Z.^2))`.**
Octave runs: `A = diag(x(1:6)); A(1,2) = x(7); A(3,1) = x(8); Z = inv(A); f =
sum(sum(Z.^2))` → `Hes` asymmetric and wrong (`H(1,2) = 0.057` vs `H(2,1) =
0.126`, FD `0.126` both; `H(4,4) = 0.0115` vs `0.0234`) while `Grd` matches FD
to `4e-8`; `Z = A\C` likewise. Controls pass: same `A` with `sum(Z(:).^2)`
(vector sum), dense `3×3` `inv` with `sum(sum(·))`, `A*C`, the sparse `mtimes`
branch at `n = 80`, the vector-sum sparse projection at `n = 40`. A
plain-variable transcription of the generated gradient file differentiates
correctly at first order, so the defect is in the **second pass over the real
gradient dialect** (struct fields, `Gator1Data` references, a `cada1td1`
temporary reused at four different sizes, name-based derivative selection),
not in any single rule — and the second pass has not been independently
validated under Octave, hence medium. *MATLAB repro:* the two fixtures through
`adigatorGenHesFile` vs `fdcheck('hess')`; if confirmed, bisect pass 2
(candidate: derivative tracking of the size-changing `cada1td1`). `[matlab]`

**BG-18 (medium, high) — `max`/`min` at ties emit the *sum* of all tied
branches.** `getdzdx` `'max'` = `(x == max(x,y)).*dx`, `getdzdy` = `(y ==
max(x,y)).*dy`, both true at a tie and added (`cadabinaryarraymath.m:426`);
`max.m:114, 123, 133, 140` build the reduction mask the same way. Octave runs:
`max(x1,x2)` at `[1.5 1.5]` → `J = [1 1]`; `max(x, 0.5)` at `x2 = 0.5` →
`dz2/dx2 = 1` (FD `0.5`); `norm(x, Inf)` with `|x2| = |x3|` → `[0 −1 1]`.
MATLAB's `max` returns the first maximal index; the Clarke subdifferential at a
tie is the convex hull of the candidates, which never contains their sum. Not
documented. *Fix:* one-hot masks (first-argument-wins; first maximum per
column). *Pin:* `max(x,x)`, tied columns, `norm(x,Inf)` at a tie. `[matlab]`

**BG-19 (medium, high) — `nonzeros(x)` on an array without a static zero
pattern returns `x(:)`.** `lib/@cada/nonzeros.m:72-88`: `y.func.size =
[xMrow*xNcol 1]` and `y = x(:)`. Octave run: `v = [x(1); 0; x(2); 0]; y =
nonzeros(v)` → generated `y.f = v.f(:)`, a 4-vector (MATLAB: 2), because the
concatenation records no zero locations for literal zeros. *Fix:* an actionable
refusal when neither value nor zero pattern is known, and/or record literal
zeros in `vertcat`/`horzcat`. `[matlab]`

**BG-20 (medium, high; documented-limitation territory) — known numeric
inputs are read *by name* while their generation-time values are baked into
sparsity and branch tables.** `adigatorFunctionInitialize.m:743-757` makes a
numeric input a `cada` with `func.value = CurVar` and its own name, so the
generated file reads the runtime value. Octave runs: `y = c.*x` generated at
`c = [1;0;2]`, called with `c = [1;1;2]` → `y.f` right, `diag(J) = [1 0 2]`
vs `[1 1 2]`; `for k = 1:4; if c(k) > 0; y = y + x(k)^2; end; end` at `c =
[1;−1;1;−1]`, called with `ones(4,1)` → value right (30), gradient `[2 0 6 0]`
vs `[2 4 6 8]`. The guide documents known inputs as fixed (`tex:183, 619`),
but the hazard is the *silent* half: correct value, wrong derivative, no stamp
or guard, and the embedded generator defaults to `auxdata = 0`. *Fix:* stamp a
value hash of each known numeric main input into the header and emit an
`assert(isequal(c, <literal>))` guard for sign-/index-steering inputs (B36
style, opt-out via `auxdata = 1`); document the hazard release-relative.
`[matlab]`

**BG-21 (medium/low) — zero-propagation flags for `atan2`, `power`, `ldivide`
are wrong or swapped.** `cadabinaryarraymath.m:161-171` computes the result's
zero set as `otherwise ztemp = xtemp` for everything but `plus`/`minus`/
`times`: `atan2(0, y<0) = π` and `0.^0 = 1` are then structurally zero and a
downstream `.*` prunes the derivative at those entries; `ldivide`
(`cada.m:437`) swaps the operands to `rdivide` but keeps flags `(0,1)` instead
of `(1,0)`, pruning `dz/d(numerator)` where the *denominator* is structurally
zero. Read from source; reachability needs an active variable with a
structurally-known-zero entry (`v = zeros(3,1); v(1:2) = x(1:2); z = atan2(v,
−ones(3,1)); y = z.*x`). *Fix:* `case 'atan2'` → no propagation; `power` →
`xtemp & ytemp`; `ldivide` flags `(1,0)`. *Pin:* the three shapes vs FD.
`[matlab]`

**BG-22 (low, high) — `x.^y` with an active exponent at `x == 0` emits `NaN`**
(`log(0).*0.^y.*dy` unguarded, `:673-674`; the `dx` term is guarded at
`:328`). Octave: `x1^x2` at `x = [0 2.5]` → `J = [0 NaN]` (true `[0 0]`).
*Fix:* `TD2(x == 0 & y > 0) = 0`. `[matlab]`

**BG-23 (low, high) — generated `interp1`/`interp2` code extrapolates with the
end polynomial where MATLAB returns `NaN` outside the breakpoints**
(`interp1.m:243-245` prints `ppval`; `adigatorEvalInterp2pp.m:48-49` clamps
with `histc(XI,[−inf,…,inf])`). A documentation-or-mask decision. `[matlab]`

### 4.2 Loud defects: generation crashes or an unparsable generated file

| ID | Where | What | Octave run | Fix |
|---|---|---|---|---|
| **BG-24** (high) | `cadabinaryarraymath.m:531-534` | the y-only arm sets `Xstr = []; Ystr = []` for `mod`/`rem` too, but their `getdzdy` needs both, so the file contains `z.dx = -floor(./).*…` — **adigator reports success and the file does not parse** | `mod(7.3, x)`, `mod([7.3;2.1], x)`, `rem(7.3, x)` all unparsable | `case {'plus','minus'}` only at `:532` |
| **BG-51** (medium) | `cross.m:290` | `xvec` is undefined on the path where the constant operand is an inline literal: `cross(X, [1 4;2 5;3 7])` with `X = [x(1:3), x(4:6)]` fails at generation with `Unrecognized function or variable 'xvec'`; the named-constant form works and hits BG-03 instead | not run in Octave; MATLAB R2024a (review of this PR) | define `xvec` on the literal-operand path; the CG-03 `cross` pin should cover both operand kinds |
| **BG-26** (medium) | `adigatorVarAnalyzer.m:296-297` | multi-output numeric branch uses undefined `NUMvar` (the variable is `NUMvars`) and overmaps the last output into every slot | `[X,Y] = meshgrid(…)` inside the user function → `'NUMvar' undefined` | `for Vcount = 1:NUMvars; varargout{Vcount} = cadaOverMap(varargout{Vcount}); end` |
| **BG-27** (medium) | `adigatorAssignOvermapScheme.m:320, 327` | `error()` in a branch that also assigns: the compaction tests `BreakLocs` twice instead of `ErrorLocs`, leaving zeros used as `LASTOCC` indices | `if x(1) < 0; z = 0; error('…'); end; y = x.^2` → `LASTOCC(0,_)` | `\|\| ~isempty(ErrorLocs)` |
| **BG-28** (medium) | `adigatorForIterEnd.m:899` | `ADIGATORVARIABLESTORAGE.OVERAMP{OverLoc}` (field is `OVERMAP`) on the break-inside-loop-inside-`if` path whose exit variable is read after the loop and assigned in the other branch | `structure has no member 'OVERAMP'`; seven other break/continue shapes generate and match FD | rename; then pin the now-reachable path |
| **BG-29** (medium) | `adigatorPrintTempFiles.m:856` | zero-argument subfunction call `P = mkp();` → `SpaceLocs(end) = 0` on an empty vector | `SpaceLocs(0)` | return an empty cell for an empty `VarStr` |
| **BG-30** (medium) | `adigatorForInitialize.m:260-266, 366-372` | a *subfunction* loop over a declared `loopbound` name gets a literal header (`for … = 1:4`) while the main `assert(N <= Nmax)` passes at `n < Nmax` → runtime index error; `adigatorOptions.m:85-87` scopes the option to the main function but nothing refuses the subfunction shape | `main(x,N) → sub(x,N)` with `for k = 1:N` in `sub`: `n = 2` → `out of bound` | refuse (`adigator:loopbound:subfunction`) or apply the runtime header via #213's call-site resolution |
| **BG-31** (low) | `interp2.m:101` | `… && ppknown` — assigned only in commented-out code (`:44, :62`); errors when both `xi` and `yi` carry values | read only | `ppknown = 1` |
| **BG-32** (low) | `mtimes.m:191-197` | a live **`keyboard`** (interactive debugger) on the rolled-loop size-change path for a non-row `x` with derivatives | read only | `error('adigator:mtimes:loopSizeChange', …)` |
| **BG-33** (low) | `adigatorPrintTempFiles.m:78-85` | a user subfunction call inside an `if`/`while` condition is printed raw and never routed through `CheckFunctionCall` (the comment at `:681-687` says such a call "would be an unrecorded site") | `if hlp(x) > 0` → `'hlp' undefined` | actionable `adigator:flow:callInCondition` |
| **BG-34** (low) | `subsasgn.m:241-246, 673-749` | element deletion `y(2) = []` fails loud in both MATLAB (sparse index past the shrunk size) and Octave, with a message naming nothing | — | actionable `adigator:subsasgn:delete` |
| **BG-35** (low) | `cadaunarylogical.m:55-57` | `all` constant-folds `y.func.value = logical(x)` instead of `all(x,dim)` (size and value wrong when the operand has a known value; `any` is right) | read only | `all(x.func.value,dim)` |

### 4.3 Portability, latent and benign

- **BG-07 / BG-08 / BG-09** — the three engine defects §7.3 details (unescaped
  regexp paren, `numel(x)` signature, `rehash` reliance). BG-09 is silent in
  Octave (the second generation in a session differentiates the previous
  function); MATLAB is believed unaffected but the fix is neutral and removes a
  dependency on interpreter cache semantics.
- **BG-36 (low)** `adigatorAssignOvermapScheme.m:290-322` zeroes
  break/continue/error branch counts *positionally* with absolute counts into a
  vector that starts at `Start`, so the removal is a no-op (instrumented run:
  `AllVarCounts` before and after compaction identical); conservative
  over-union today, and the "return at last `IfIterEnd`" path behind it is
  effectively dead. **BG-37 (low)** `:859` `for forLoci = 1:ForLoops` uses only
  `ForLoops(1)` as the colon bound (superset scanned; can only over-union).
  Both become live once BG-27 is fixed; pin the seven passing break/continue
  probe shapes counted under BG-28 first, then correct.
- **BG-38 (low)** `cross.m:174` allocates `fyLtemp = false(FMrow*FNcol)` (an
  `n×n` logical) where its siblings are `n×1`; benign, O(n²) memory.
- **OC-06** (`©`/`ç` emitted as single bytes) is HY-08.

### 4.4 What the bug finders read without finding a defect

For the record, so the next review does not re-read them blind:
`cadamtimesderivvec`, `cadainversederiv` (dense and sparse), `cadamtimesderiv`
(the `sortrows` re-ordering is present), `prod` with zeros, `diag`, `repmat`,
`reshape`, `sparse`, `transpose`, the 42-rule unary table (0 violations in the
Octave FD sweep), `atan2` orientation, `power`/`sqrt` guards, the `abs`/`sign`/
`floor` family; `subsref`/`subsasgn` index translation and the N-D veneer;
`cadaOverMap`/`cadaOverMapTargetNz`/`cadaPrintReMap` (the ADR-0036 prune
gate); `cadaUnionVars`/`cadaunion`; `adigatorIf*`; the B17/B22 `structParse`
marking (constant structs in loops and nested struct-in-struct are fine); the
`@cadastruct` fallback-naming mixture (cross-pass aliasing needs an
unnamed struct intermediate in a generated source, which the printer never
emits, so the §1.3g follow-up is theoretical). A value test is still owed for
all of them (§3). Not read: `adigatorAnalyzeForData.m` beyond grep,
`interp2.m` beyond the sites named, `sparse.m` body.

---
### 4.5 The fork's own layer (`util/`, `embedding/`, `cadaUtils/`)

Read in full by the fork-layer pass: every file under `util/` and
`embedding/`, the `cadaUtils` stamp/header/print helpers, `adigatorOptions.m`,
and `adigator.m`'s option plumbing. The layer is in better shape than the
inherited rules — most defects are in the two *untested* shipped utilities and
in the reverse-mode transformer's text parsing.

**BG-39 (critical, high) — `adigatorUncompressJac` applies the colour
permutation in the wrong direction.** Verified directly (Octave, repository
copy, no engine involved): `util/adigatorUncompressJac.m:19-20`

```matlab
order = nonzeros(sparse(i,c(j),1:length(i),m,n));
J = sparse(i,j,JSnz(order),m,n);
```

`order(p)` is the original entry index sitting at compressed position `p`, so
compressed value `JSnz(p)` belongs to entry `order(p)`; the code gives entry
`k` the value `JSnz(order(k))`, the inverse permutation. The two coincide only
for involutions, which is why small textbook patterns work. `Jpat = [0 1; 1
0; 1 0]`, `Jval = [0 7; 2 0; 3 0]`: `[c,S] = adigatorColor(Jpat)`, `JSnz =
nonzeros(Jval*S)`, `adigatorUncompressJac(Jpat,c,JSnz)` returns `[0 2; 3 0; 7
0]`. Over 236 random patterns without empty columns (generator in Appendix
B, re-run by the orchestrating session) the shipped code is wrong in 122 and
`J = sparse(i(order), j(order), JSnz, m, n)` wrong in 0. This is the utility `CI_PLAN.md:244` claims is round-trip tested
"inside TS-I-01" and no test, example or bench script references either
function (CG-18). *Fix:* the one-line replacement above; **BG-40 (low)**
`adigatorColor.m:54-56` additionally shortens the returned colour vector by
the empty columns when called with two outputs, so `c(j)` is misaligned (an
index error, fail-loud) for any pattern with a non-trailing empty column. *Pin:* a
round-trip test with random patterns including a 3-cycle permutation and an
empty column. `[matlab]` (Octave already demonstrates it)

**BG-41 (critical, *medium*) — the reverse-mode value-tape slicer drops a
one-line plain copy.** The printer emits a user-level copy of a
derivative-carrying variable as one physical line, `u.dz = v.dz; u.f = v.f;`
(`adigatorVarAnalyzer.m:152-157`; e.g. `gen_dialect/slim1/gapfun_Grd.m:46`).
`adigatorParseTape.m:122-127` splits at the *first* `=` only, so the statement's
`lhs` is `u.dz` and the `u.f` assignment is invisible; `adigatorForwardTapeSlice.m:59-61`
then excludes the whole line as "a derivative statement". If `u` has no
earlier `.f` writer the sliced tape fails loud (`adigator:revgrad:exec`,
untested); if it has one (an unrolled loop that reassigns through a copy, or
an output reassigned by a copy) the slice keeps the **old** writer and the
emitted `_RGrd` computes `Fun` and `Grd` from the stale value with no error.
Read from source; not executed (needs the reverse generator, which needs
`readlines`). *Fix:* split compound lines into one statement per
`;`-terminated assignment in `adigatorParseTape` (the printer only ever joins
`<v>.d<vod> = …; <v>.f = …;`), or fail loud when `rhs` contains `=`. *Pin:*
`u = x; y = sum(u.^2)` and an unrolled reassign-through-copy fixture in
`IRevGradTest`. `[matlab]`

**BG-42 (medium, medium) — reverse-mode activity shortcut is unanchored.**
`adigatorGenRevGradFile.m:315-317` marks a statement inactive when its rhs
*starts* with `zeros|ones|eye|size|length|numel(` (no end anchor), so
`ones(2,1)*x.f` is classified passive and emitted **without an adjoint**
instead of hitting the `adigator:revgrad:unsupported` guard at `:400-404`.
Latent (the forward printer names constants through `cadamatprint`), but it
converts a fail-loud path into a silent one. *Fix:* anchor to the full rhs.
`[cloud]` to patch, `[matlab]` to pin.

**BG-43 (medium, high) — the "Reconstruct with:" recipe silently omits a
vector-valued `der_levels`.** `adigatorReconstructCall.m:190-208` renders only
char/scalar/cellstr literals and drops anything else without a marker, so a
file generated with `der_levels = [1 2]` (signature `[Hes, Grd]`) prints a
recipe that regenerates `[Hes, Grd, Fun]`. The option *is* signed by the id
(`adigatorStampOptions` `levelsSig`), the exact "signed but not printed" drift
the file's own comment (`:474-481`) names, and the drift test guards only
`auxdata`. *Fix:* render finite numeric vectors with `mat2str`; add a generic
"every signed non-default option appears in the recipe" assertion. `[cloud]`
+ `[matlab]`

**BG-44 (low, high) — B12 is not fixed in `adigator.m`.** `adigator.m:129`
`opts.(lower(optfields{Fcount})) = varargin{1}.(lower(optfields{Fcount}))`
indexes the *user's* struct with the lower-cased name, the shape ANALYSIS B12
describes and marks "Fixed" (the three generators were fixed; the core entry
point was not). `UOptionsTest` exercises only a generator. *Fix:* index with
`optfields{Fcount}`; extend the test with a direct `adigator(…, struct('ECHO',0))`
call; amend the B12 row. `[cloud]` + `[matlab]`

**BG-45 (low, high) — reverse-mode index tables are named `RIndex%d`, so
`prune_adigator_mat`'s `Index*`-keyed down-cast, range guard and keep-all rule
never apply to them** (embedded as `double`; an empty table would be dropped).
`[matlab]`

**BG-46 (low, high) — the wrappers leak a path entry on an unresolvable
function.** `adigatorGenJacFile.m:183-190` (`GenHesFile.m:185-192` identical):
`addpath(CallingDir)` then `nargout(UserFun)` **outside** the `try` that
restores `path()` (which begins at `:210`); `nargout` throws on an unknown
name. With a user `opts.path` the leaked entry is arbitrary. *Fix:* check
before `addpath` or move inside the `try`; pin with a wrapper-level hygiene
case. `[cloud]` + `[matlab]`

**BG-47 (low, high) — the generation id does not cover the input
specification** (derivative-input sizes, aux values, `loopbound` maximum:
`cadaGenerationStamp.m:50-59` hashes version + options + source only), so
regenerating at `n = 3` and `n = 5` yields different bodies with the same id,
and the docstring's "what it does not detect" list does not say so. *Fix:*
sign a canonical input signature, or document the gap in the header
parenthetical and CHANGELOG. `[cloud]`

**BG-48 (low, high) — the ADR-0023 scan's deny-list is narrower than its
claim.** `adigatorScanEmbedUnsupported.m:40-45, 54-64` detects only `{…}`
literals/indexing and a literal `load` call; `cell(n,1)`, `num2cell`,
`struct2cell`, `cellfun(…,'UniformOutput',false)`, `evalin`/`eval('load …')`,
`feval('load',…)`, `importdata`, `readmatrix`, `fileread`, `fopen`, `matfile`
and `persistent` escape the warning. Advisory only, but C-4 states the gate
warns on "a cell array, user `load`, or user `global`". *Fix:* extend the
deny-list or state the detected forms in ADR-0023/C-4. `[matlab]`

**BG-49 (low, medium) — reverse mode rejects any active statement with a
negative scalar constant** because `cadamatprint` parenthesises it (`(-2)`)
and the reverse atom regexp has no parenthesised form (`adigatorGenRevGradFile.m:302-303`);
fail-loud for an operation the help lists as supported. `[matlab]`

**BG-50 (info)** The deprecated `GenFiles4*` wrappers still print `% Contact:
mweinstein@ufl.edu` (`adigatorGenFiles4Ipopt.m:274-276` and siblings), the
upstream routing #200 removed everywhere else (DD-34). `[cloud]`

---
## 5. Documentation drift and the deferral sweep

All items `[cloud]`. Each names both sides; where this review cannot tell which
side is right it says so.

### 5.1 `CI_PLAN.md` registry vs the tree

| # | Row | Claim | Tree | Correction |
|---|---|---|---|---|
| DD-01 | TS-U-09 (`:120`), REQ-C-10 traceability (`:221`) | `ULintTest` — `checkcode` … | no such class; lint is `tests/ci_lint.m` (a script run by `ci.yml:57`) | name the script; the 2026-07-04 review already flagged this phantom and R28 WS3 (#119/#160) claimed the reconciliation done |
| DD-02 | TS-S-03 (`:190`) | `SReleaseMatrixTest` — full suite on {R2022a, latest}, "nightly only" | no such class; it is the `extended.yml` `release-matrix` job, which TF-01 shows never runs on `master` | describe it as a job; fix the trigger |
| DD-03 | TS-U-06 (`:117`) | golden-file tests with checked-in fixture inputs and expected outputs | `UPatchTest.m:32,69,107` call `writeSyntheticDerivFile()` (in-test input, in-test assertions); no goldens under `tests/fixtures` | describe the synthetic-input design (ANALYSIS §1.5 B3 already does) |
| DD-04 | §2.4a (`:244`) | `adigatorUncompressJac`/`adigatorColor` round-trip "inside TS-I-01" | neither function appears in any test or example | write the test or drop the row (CG-18) |
| DD-05 | REQ-C-02 (`:90`), REQ-C-03 (`:91`) vs TS-U-02/03 | `atan2`, `power`; `repmat`, `mldivide` | not in the named tests (CG-01, CG-03) | widen the tests or narrow the rows |
| DD-06 | TS-I-02 (`:143`) | fixtures incl. "one with a rolled loop" and "an integer-valued constant matrix" | `IEmbedModesTest` fixtures: pipg `gapfun` (subfunctions) and three one-liners; no `for` loop fixture; no integer constant matrix visible in the test text | add the fixtures or correct the row |
| DD-07 | TS-I-01 (`:142`) | input shapes incl. `1×n` | no `[1 n]` derivative input in `IShapeMatrixTest` (`:84,:160,:216` are `[1 1]`, the rest columns) | add it (CG-10) or correct |
| DD-08 | TS-U-05 (`:116`) | "randomized structs … n-d arrays" | `UEmbedMfileTest.m:26-48` builds one fixed 2-D struct | correct, or randomise |
| DD-09 | TS-I-06 (`:147`) | classic `slim_embed` is "a byte-for-byte no-op" | `IEmbedSlimTest.m:169-222` compares modulo timestamp lines (ADR-0038) | "modulo timestamp lines" |
| DD-10 | TS-I-09 (`:150`), TS-I-25 (`:166`) | the `_location` strip proves the slice fired; csc "FD/analytic agreement" | the test itself says #80 subsumed the strip signal; csc is compared to matrix mode (TF-09) | correct both |
| DD-11 | TS-U-08 (`:119`), `UCoreErrorHygieneTest.m:130-156` | `adigator.m:242` / `:775` | now `:246` / `:800` after #200 | refresh or cite by construct |
| DD-12 | §2.1–2.3 | registry of all tests | eight classes have no row: `UMonteCarloTest`, `ISmokeTest`, `IInterprocGapEquivTest`, `IGenFiles4Test`, `IGuideFixturesTest`, `SCodegenShowcaseTest`, `SLoopboundPaddingTest` (prose only), `MCRegressionTest` | register them (R28 WS3 says this was done) |
| DD-13 | §3.1 `ci.yml` sketch (`:266-287`), §3.1 docs-pdf (`:326-343`) | stale step names/ranges; "commits the rebuilt PDF back to the PR branch" | `ci.yml` has the docs-only step and the coverage step; `docs-pdf.yml` builds an artifact on PRs and commits on `master` via a GitHub App token (#149) | refresh |
| DD-14 | §0 (`:51`), §3.4 (`:483`) | bugs B1–B22 / B1–B13 | register goes to B40 | "B1–B40" with B40 open |
| DD-15 | `ci_suiteGuard.m:102`, `ci_gate.m:13`, §3.1 (`:295`) | "64 classdefs"; "16 tests across 5 classes" | 66 classdefs; today 6 gated `AdigatorTestCase` subclasses / 20 tests would vanish under `run-tests` | refresh the count or drop it; keep the roll-call as history |
| DD-16 | `SCscMetadataTest.m:11-12` | "runs in the PR gate" | lives in `tests/system`, never selected by `ci.yml` | move it to `tests/integration` (needs only `bench/` on the path) or fix the comment |

### 5.2 `DESIGN.md`, `REVIEW_CONTEXT.md`, `CLAUDE.md`, `DISCIPLINE_ADOPTION.md`

- **DD-17** `DESIGN.md:103` (C-1) still binds "the pattern exported via the
  `der_output`/`*Locs` family — the default for `k ≥ 3`"; ADR-0030 removed
  `*Locs` and its revisit clause says higher-order native output will be "a
  separately named tensor/coordinate representation, not CSC". The R31 census
  promised a pointer note on forward-looking ADRs; C-1 did not get one. *Which
  side is right:* the contract text is stale; the fix is a pointer, not a
  behaviour change.
- **DD-18** `REVIEW_CONTEXT.md:59` principle 4: "`'l'`/`'i'` files must pass
  MATLAB Coder (`lib` target)" — ADR-0033/REQ-T-10 moved the bar to strict
  Embedded Coder (`adigatorCoderConfig`, no dynamic memory), and ADR-0021
  records that `'l'` does not ERT-codegen. The principle reviewers are asked to
  apply is the pre-ADR-0033 one.
- **DD-19** Ranges and paths: `CLAUDE.md:23` "B1–B22", `REVIEW_CONTEXT.md:7`
  "B1–B26" (actual B40); `CLAUDE.md:22,55` and `DISCIPLINE_ADOPTION.md:32`
  "C-1..C-5" (DESIGN defines C-6; `REVIEW_CONTEXT.md:29` says C-6); the label
  `docs/ANALYSIS.md` for `docs/analyses/ANALYSIS.md` in `CLAUDE.md` (2),
  `CI_PLAN.md` (5), `ROADMAP.md` (5) — link targets are right, labels are not.
  `DESIGN.md:41` lists `tests/{unit,integration,system}` driven by `ci_local`;
  the tree also has `tests/montecarlo`, `tests/offline`, `tests/legacy` and
  `ci_gate`/`ci_prepush`/`ci_ert`/`ci_coverage_folders`.
- **DD-20** The `'l'` embed mode. `adigatorNormalizeEmbedMode.m:38-39` accepts
  `'l'`/`'coderload'`; no deprecation warning exists in code (`grep -i deprecat` over `*.m` finds
  the `GenFiles4*` banners, the deprecated-example headers under
  `examples/optimization/` and an ADR-0037 comment at
  `adigatorGenHesFile.m:273`; none concerns `'l'`); DESIGN C-4 and
  REQ-T-04 say the warning is "planned (R24)" and CHANGELOG lists `'l'` under
  *Deprecated*, but `adigatorOptions.m:59-67` (the help every user reads) still
  says `'l'` is "Suitable for code generation", `DESIGN.md:61-62` calls it
  "codegen-friendly", the README embed-mode table and the guide's option table
  omit it while `docs/README.md:151` names "the same `c`/`l`/`i` pipeline". Four
  documents, three states. *Fix:* one of (a) emit the planned warning now (one
  line in `adigatorNormalizeEmbedMode`, `[matlab]` to pin), or (b) say
  "deprecated, no warning yet" everywhere user-facing.

### 5.3 `ANALYSIS.md`, `ROADMAP.md`, `CHANGELOG.md`, the user guide

- **DD-21** `ANALYSIS.md:1307` B23 names its pin as
  `IOutputModesTest/hessianNonzerosMatrixOfScalar`; the method was renamed
  `hessianCscMatrixOfScalar` in the R31 migration. B5/B6/B14/B15 name no pin
  (B14 is won't-fix, B6 "mitigated by a notice" — a `verifyWarning` on the
  notice would pin it). B7–B10 rows lack the TS-I-01 caveat (TF-02).
- **DD-22** ROADMAP statuses that describe as outstanding work that is in the
  tree: **R14/R9** "the typed expression-tree generator and an FD-Hessian value
  oracle remain" — `mcGenExprTree.m` is a default generator and
  `MCSmokeTest.fdHessianValueOracleIsClean` exists (CI_PLAN TS-S-04 and
  ANALYSIS B32 say so); **R17** "Still outstanding — the comprehensive 4-method
  × 2-environment comparison … a new `bench_interp.tex`" — `bench/SHOWCASE.md`
  carries FD as the fourth method in both tables and `bench_interp.tex` is
  `\input` at `ADiGatorUserGuide.tex:608`; **R17c** "follow-up: `bench_compare.tex`
  refresh to compiled ROM" — already ROM-based; **R27** describes
  `oracleDerOutputInvariance` in the removed `jac_output='nonzeros'`/
  `JacobianLocs` surface (the file uses `csc`/`JacobianCSC`); backlog §2.4(10)
  "stamp generated files with version + options hash" — done by #200. (CG-17
  shows R14's *claim* is also over-stated for what was built.)
- **DD-23** `CHANGELOG.md:187` (user-facing): "the 47 generated artifacts
  committed under `examples/` still carry the old contact until they are
  regenerated" — zero generated files are tracked under `examples/` (gitignored
  since #67/#68; also zero at the commit that wrote the sentence), and no
  example file contains the upstream contact string. `CHANGELOG.md:349-353`
  lists as a known limitation that the *unslimmed* inline Hessian does not
  ERT-codegen, while ROADMAP R20 records Gap A done (#81); and calls the rolled
  form's stack "flat, n-independent", while ANALYSIS B37 measured `96 + 8n`
  and ADR-0035 rejected a flatness rule. One of each pair is stale; the
  CHANGELOG is the user-facing one (needs `[coder]` to settle the first).
  `CHANGELOG.md` also cites ADR-0033/0036/0037 (#233 covers maintainer-only
  text in a release section).
- **DD-24** Principle-8 hits in user-facing docs: `docs/README.md:148` "(C-6
  order)"; `bench/SHOWCASE.md:299` "(issue #192, ADR-0030)". The guide's only
  hit is inside a LaTeX comment.
- **DD-25** User guide: `ADiGatorUserGuide.tex:377` shows
  `adigatorFiles4Fmincon(setup)` under the `adigatorGenFiles4Fsolve`
  subsection and `:449` `adigatorGenFiles4Fmincon(setup)` under
  `adigatorGenFiles4Ipopt` (inherited typos); `adigatorOptions.m:220-235`
  accepts `optoutput` and `genpat`, documented in neither help nor guide; the
  `SLIM_EMBED` scope reads "inline mode (`'i'`)" in the guide (`tex:312`) and
  "`'l'`/`'i'`" in the help (`:153`). The guide's sections that R26/R29 owed
  ("docs on landing": §Restrictions for ADR-0023, §Debugging for ADR-0024)
  exist (`tex:613-741, 852-889`); their text was not checked line by line.
- **DD-26** `tests/montecarlo/README.md` omits `mcGenExprTree`,
  `mcGenParamDelivery`, `oracleFiniteDiff`, `oracleCodegenEquivalence`,
  `oracleParamDeliveryInvariance`, `oracleDerOutputInvariance` from its table
  and still calls the FD-Hessian oracle and the expression-tree generator
  "future work" (`:43, :73-75`).
- **DD-27** `tests/fixtures/guide/lse_cost_RGrd.m` carries no #200 header;
  the reverse generator never emits one (TF-34), so the ADR-0025 guide fragment
  shows a header format different from every other generated file.

### 5.4 The deferral sweep (CONTRIBUTING §"Deferral sweep", run here)

All 38 ADRs were scanned by the word (`revisit|re-evaluate|reconsider|trigger|
until|once … lands`), not by formatting. Result:

| ADR | Condition | Fired? | Evidence / action |
|---|---|---|---|
| ADR-0022 | a DerType needs a third output form | **yes** | handled: ADR-0030 (status marked partially superseded) |
| ADR-0026 | fork drops the upstream drop-in goal | **superseded** | ADR-0037, status updated |
| **ADR-0021 / R24** | "R17 large-data numbers show `'l'`'s compact source wins a real embedded regime" | **never evaluated** | no `'l'` or split-data compiled cell exists anywhere in `bench/` or `SHOWCASE.md`; `split_data` exists only in docs. The `'l'` removal decision has no evidence either way (DD-20). Re-defer with a concrete trigger (a measurement task, `[coder]`) or decide on the ERT-fails-anyway argument. |
| ADR-0004 | test wall-time grows enough that parallel installs beat install cost | **partially** | `CI_PLAN.md` §3.6 measured the full-products job at ~37 min (from 3–11); PR gate unchanged. Re-defer with the number as the trigger. |
| ADR-0028 | n-th derivative lands; guard-emission shape changes | no, but **latent**: the ADR notes its five loop-guard copies "have already drifted textually" | `ULoopboundGuardTest` pins the recogniser shape; nothing pins the five emitters in lockstep against each other. `[matlab]` |
| ADR-0017 | hook runtime makes `--no-verify` routine | no (#240/#245 was an unarmed hook, now surfaced by `ci_gateArmedNotice`) | — |
| ADR-0019 | an embedded target needs reverse mode or hits O(n²) runtime before R21 | no | the ADR's `:60` still says "unrolled O(n²)-stack form"; its status blockquote retracts the figure (#216). Consistent, if clumsy. |
| ADR-0008 | (a) Octave generation; (b) committed-fixture staleness | **(a) now measurable** (§7) | the decision this review recommends surfacing (§9, WP-O2) |
| ADR-0032 | "raised as the value oracles land" | oracles landed (`oracleFiniteDiff`, FD-Hessian, param-delivery, der-output), floor not raised | the floor is in TF-01's workflow and the baseline was written from a PR-branch dispatch; raise after the first `master` run |
| ADR-0007 | (a) property framework; (b) smoke flaky; (c) Phase D wanted | no | — |
| others (0001–0003, 0005, 0006, 0009–0016, 0018, 0020, 0023–0025, 0029–0031, 0034–0038) | — | no | — |

ROADMAP future rows and their gates: **R6** is still "a live maintainer
decision" on numbers the engine-v2 analysis says will change after R21 step 2;
**R15(a)**, **R18**, **R19**, **R21**, **R22**, **R24**, **R25 phase 2/3**,
**R30** planned; nothing in them has a fired trigger. ANALYSIS residual routes:
B36 routes 2/3 (`N` via a struct field; via a local alias) and B39's one-level
indirection remain open as recorded. Issues labelled `deferred`: none carry the
label; the deferred items live in ROADMAP rows and ADR clauses only.

---
### 5.5 Further drift found by the dedicated documentation pass

- **DD-29** `CI_PLAN.md:465-467, :485`: "nightly jobs … informational for the
  first month, then promoted to required-on-master once stable" / Phase 3 exit
  "one week of green nightlies; promote". `extended.yml` was created 2026-06-11;
  the month elapsed 2026-07-11; no promotion exists and the §3.4 Status
  paragraph (`:488`) does not mention Phase 3 at all. Combined with TF-01 the
  jobs cannot even run on `master`. Add Phase 3 to the status and either
  promote or re-defer with a condition.
- **DD-30** ADR-0032's "ratchet now, raise later … as the #38/#103 oracles
  land" fired on 2026-07-30 (`mcGenExprTree` + the FD-Hessian oracle, `bef32e5`;
  `IStructArrayNamingTest` `0dbfcdf`; several classes after), but
  `tests/coverage_baseline_folders.txt` has one commit (`bc07453`, 2026-07-29),
  so every correctness-path floor predates every oracle the ADR named as its
  trigger. ADR-0032 (and ADR-0005, 0012, 0027, 0033) carry no "revisit" word,
  so the documented sweep (`git grep -liE 'revisit'`) cannot see this deferral
  — CONTRIBUTING's own warning that "a clause can be written in prose with no
  markers". Add an explicit clause; widen the scan or list the five by hand.
- **DD-31** ADR-0028 `:84-91` still records the shared loop-guard shape
  constant as "designed on #181 §4, deferred"; `util/adigatorLoopboundGuard.m`
  landed 2026-07-12 (#191) and is consumed by all five sites and pinned by
  TS-U-19. Amend the ADR; keep only the n-th-order re-sweep and the
  vector-output interim as open conditions.
- **DD-32** `REQ-T-10` (`CI_PLAN.md:82`) requires every `'l'`/`'i'` derivative
  to ERT-codegen, with acceptance "every (DerType × `'l'`/`'i'` × `slim_embed`)
  cell exercised by the showcase"; ADR-0021 verified `'l'` fails ERT, C-4
  deprecates it, and the showcase has no embed-mode column (inline only). A
  requirement that contradicts a contract and names a non-existent acceptance
  set: **§4 decision** to amend REQ-T-10 to `'i'` (and split-inline on R24).
- **DD-33** B13 ("`Gfid` never closed in `adigatorGenHesFile`") is mapped to
  TS-U-08 (`CI_PLAN.md:119, :225`), but `UCoreErrorHygieneTest` calls only
  `adigatorGenJacFile` (`:53, :67, :101, :111, :167, :184`) and the
  Monte-Carlo handle check runs no Hessian case; the B13 fix is pinned by
  nothing. Add a Hessian generation (clean and erroring) to the hygiene test.
- **DD-34** `CHANGELOG.md:100-102` "Every generated file now opens with a
  `GENERATED FILE` line …" is an over-claim (TF-34): only `adigator.m`,
  `adigatorGenJacFile` and `adigatorGenHesFile` call
  `cadaPrintGeneratedHeader`; `_RGrd`/`_JtV` files carry none and the
  `GenFiles4*` outputs still print `% Contact: mweinstein@ufl.edu`
  (`adigatorGenFiles4Ipopt.m:274-276` and siblings) — the upstream contact the
  #200 work set out to remove. Route the reverse generators through the header
  (and the deprecated family, or scope the sentence).
- **DD-35** `ISymbolicIndexTest.ifGuardedWhileCounterErrorsSafely` (`:134-136`)
  says a future fix "is caught by this test starting to change"; its only
  assertion is `verifyTrue(threw)`, which an actionable-error fix would not
  change (TF-27). Pin "not `adigator:symbolicIndex`" or reword.
- **DD-36** `docs/decisions/README.md:134-135` lists ADR-0022 as plain
  **Accepted** with the removed surface in its one-liner, while ADR-0022 itself
  (`:12`) is "partially superseded by ADR-0030" and the index convention
  (`:55-56`) says to flip the old entry (ADR-0026's row does carry
  "Superseded by ADR-0037").
- **DD-37** R24 blast radius unrecorded: `IEmbedSlimTest`, `IEmbedSlimRolledTest`
  and `ILevelSelectTest.composesWithEmbedMode` use `'l'` as a *working* fixture
  mode (TS-I-05/06/09 rows say "coderload"), not as the deprecation guard
  ADR-0021 plans; removal would red them. Note it in R24.
- **DD-38** R6: evidence "in" since 2026-07-10, re-measured 07-30, HOW-analysed
  08-02, status "maintainer call" with no decision or re-deferral date; the
  engine-v2 analysis itself says the padding penalty should be re-measured
  after R21 step 2 before being leaned on. Record a decision or a dated
  condition.
- **DD-39** `DESIGN.md:39-41` module table: `GenFiles4*` listed without the
  ADR-0037 deprecation, `adigatorGenRevGradFile`/`adigatorGenJtVFile`/
  `adigatorCoderConfig` absent, tests described as `tests/{unit,integration,
  system}` driven by `ci_local` only; `:310-313` "Future directions" still lists
  "a triplet/CSC output mode" and reverse mode as future after R31 and R4/R16
  shipped them.
- **DD-40** `CHANGELOG.md:354-356` describes the B19 residual as "a narrow
  N-D-indexing edge case"; `ANALYSIS.md:343-367, :1303` describes an
  `if`-guarded `while`-counter index over-approximation on a 1-D subscript.

## 6. Hygiene, licensing, and release readiness

Verified directly unless noted.

- **HY-01 (medium, `[cloud]`) — error identifiers.** 509 `error(` calls in
  `adigator*.m`, `lib/`, `util/`, `embedding/`; 399 have no identifier-shaped
  first argument (python census, comment-stripped; the regexp counts a quoted
  `ns:id` or an id variable as "has id"). Heaviest files:
  `lib/@cada/adigatorAnalyzeForData.m` 23, `lib/@cada/subsasgn.m` 17,
  `lib/@cada/repmat.m` 16, `adigator.m` 16, `lib/@cadastruct/repmat.m` 15,
  `lib/@cada/subsref.m` 13, `lib/@cadastruct/subsasgn.m` 12, `lib/@cada/interp1.m`
  11. Most are upstream refusals ("Cannot do strictly symbolic …"); REQ-T-07
  asks for clean errors and the fork's own refusals (B39, B36, B25) carry ids.
  Two inconsistent namespaces also exist: `adigator:*` (the fork's) and
  bare function-name ids (`adigator_patch_derivative:headerNotFound`,
  `structure_to_embed_mfile:io`, `emit_data_helper_file:unsupported`). *Fix:*
  a namespace rule in `CONTRIBUTING.md`, an `error`-without-id count ratchet in
  `ci_lint` (cheap, `[cloud]` to write as text), opportunistic conversion.
- **HY-02 (low, `[cloud]`) — file modes.** 178 tracked files are mode `100755`,
  including `adigator.m`, `adigatorOptions.m`, `Contents.m`, most of
  `examples/`, and `docs/README.md`. Inherited from upstream; harmless, but a
  `.gitattributes`/`git update-index --chmod=-x` sweep would stop it spreading
  by copy.
- **HY-03 (info) — line endings.** `git ls-files --eol`: 460 files `i/lf w/lf`,
  8 `-text` (binaries). The LF policy (#212, #237) holds.
- **HY-04 (info) — proprietary-content guards work.** `git check-ignore -v`:
  `docs/analyses/new-analysis.md` → `docs/analyses/.gitignore:9 *`;
  `docs/known-bugs/x.md` → `.gitignore:40 **/known-bugs/`;
  `docs/analyses/adigator-bugs.md` → ignored; `examples/x/generated/y.m` →
  ignored; `tests/fixtures/foo_Jac.m` and `tests/fixtures/new/thing_ADiGatorJac.m`
  → **not** ignored (the `!tests/fixtures/**` negation, by design). This
  analysis therefore needs its own whitelist line in `docs/analyses/.gitignore`
  (added with it).
- **HY-05 (medium, `[cloud]`/decision) — generated-code licence and runtime
  dependence (#239, #249).** The emitted header (`cadaPrintGeneratedHeader.m:
  68-72`) says "Produced by ADiGator, distributed under the GNU General Public
  License … in the hope that it is useful", deliberately making no claim about
  the output's licence (the file's own comment, `:32-37`). Runtime dependence
  of generated files on the GPL library is confined to the `interp2` path:
  `lib/@cada/interp2.m:131,210,219,328` print calls to `adigatorGenInterp2pp`/
  `adigatorEvalInterp2pp`; no other emitter prints a call into `lib/` or `util/`
  (grep of the emitters for `adigator[A-Z]`, `cada[A-Z]`, `ADiGator_LoadData`:
  only the classic-mode loader, which is the generated file's own
  subfunction). So #249's scope is one overload. There is no `CITATION.cff`
  and no `NOTICE`. *Decision needed (§4 of CLAUDE.md):* what the output
  licence statement should say; a `CITATION.cff` is free.
- **HY-06 (low) — release machinery.** `release.yml` is tag-gated,
  `permissions: contents: write`, excludes `tests bench CLAUDE.md .github
  .claude docs/analyses docs/decisions docs/papers docs/thesis docs/vv` and the
  four dev docs from the distribution archive (verified in the yaml), and
  validates the tag against the CHANGELOG and `adigator.m`'s `version = '2.0'`
  with `.github/scripts/release_changelog.py`, which reads cleanly (heading
  regexp accepts `—`/`–`/`-`; `[Unreleased]` emptiness ignores HTML comments
  and `###` stubs; link definitions stripped from the extracted body). Known,
  tracked gap: it does not reject maintainer-only blockquotes/comments in a
  dated section (#233), and `CONTRIBUTING.md` admits the workflow does not
  check CI on the tagged commit. The `docs-pdf.yml` auto-commit uses a GitHub
  App token on `master` pushes and builds an artifact on PRs (same-repo only);
  the committed PDF (2026-08-02) post-dates the last `.tex` change (2026-08-02),
  so guide and PDF are in sync.
- **HY-07 (low) — version/branch state.** `adigator.m:85` `version = '2.0'`;
  `CHANGELOG.md` says 2.0 was never tagged; `git tag` is empty; `Contents.m`
  says "Version 2.0 (unreleased)". Three remote branches beyond `master`:
  `embedded` (270 behind, the dead trigger target), `docs/reverse-mode-envelope`
  (#206 draft), `claude/adigator-docs-prs-review-iqv29c`. Deleting `embedded`
  after TF-01 removes the trap permanently.
- **HY-08 (low, `[cloud]`) — Octave-visible hygiene.** `MCSmokeTest.m:218` names
  a variable `do` (an Octave keyword; the only syntax incompatibility in the 375
  files parsed); `cadaPrintGeneratedHeader.m:71-72` writes `©`/`ç` as `char(169)`/
  `char(231)`, which MATLAB encodes as UTF-8 but Octave writes as raw
  ISO-8859 bytes (invalid UTF-8 generated files). `embedding/
  adigatorReferencedIndex.m:54` says Octave does not honour `\b`; the 2026-07-04
  review said the comment "wrongly blames Octave"; measured: Octave 8.4 indeed
  does not honour `\b` in that pattern, the source comment is right.
- **HY-09 (info) — workflow security.** Actions are pinned by major tag
  (`@v2`, `@v4`, `@v1`), not SHA; `docs-pdf.yml` restricts to same-repo PRs
  and reads the App id from a literal; no `run:` block interpolates untrusted
  event text. Nothing actionable beyond the usual SHA-pinning preference.

---
## 7. GNU Octave — measured feasibility and what it unlocks for a cloud session

The premise in `CI_PLAN.md:22-33`, `DESIGN.md:304-306`, `docs/README.md:85-86`
and ADR-0008 is that Octave "is not viable today" because of `arguments`
blocks, `readlines`/`writelines`, string arrays and "heavy `classdef`
`subsref`/`subsasgn` dispatch, an area where Octave's classdef support is
incomplete". It is listed under "Constraints that shape the plan (verified
against the codebase)". It was not measured. This review measured it with
GNU Octave 8.4.0 (commands and outputs in Appendix B).

### 7.1 What runs unmodified today (Tier 0)

- **OC-00** Both licence-free offline cores pass exactly as their headers
  prescribe: `prune_shrink_offline_checks` → `PASS (36 checks)`;
  `gap_interproc_equiv` → `PASS Jac=[17; 27] Fun=238 (slim0==slim1; FD
  |d|=4.0e-08)`. (The relative-path invocation fails because the function
  `cd`s into the fixture folder; the documented absolute form is required.)
- Committed generated fixtures execute: `cf_Jac([1;2;3])` → `eye(3)` exact
  (after rebuilding the gitignored `.mat` the way `IPeepholeDriverTest` does);
  `lse_cost_RGrd(x,w)` → `max|G−Ga| = 5.6e-17`.
- Plain fork functions run: `cadaFnv1a64('foobar')` = `85944171f73967e8`
  (its own documented vector), `adigatorBuildCSC`/`adigatorCSCToLocs` round
  trip, `adigatorResolveDerLevels`, `adigatorNormalizeEmbedMode` (with its
  error ids), `adigatorLoopboundGuard`, `prune_adigator_mat`,
  `adigatorReferencedIndex`. Their unit classes total 68 methods
  (`UBuildCSCTest` 17, `ULoopboundGuardTest` 9, `UPruneMatTest` 21,
  `UGenerationStampTest` 15, `UOptionsTest` 6) — but `matlab.unittest` does
  not exist in Octave, so they cannot run *as written*.
- `__parse_file__` over 375 of the 377 tracked `.m` files (all but the root
  `Contents.m` and `startupadigator.m`): 0 parse failures in
  `adigator*.m`, `lib/`, `util/`, `embedding/`, `bench/`, `examples/`; 65 test
  classes fail only on the unresolvable `matlab.unittest.TestCase` superclass;
  one genuine syntax incompatibility (`MCSmokeTest.m:218` names a variable
  `do`, an Octave keyword, HY-08).

Of the twelve artefacts that run today, two (the offline cores) are wired to
a MATLAB test; none is wired to any cloud-side job.

### 7.2 Where the MATLAB-only features actually live

Census over comment-stripped code: the engine proper (`adigator*.m`, `lib/`)
contains **no** `arguments` block, no `readlines`/`writelines`, no `string()`.
They are confined to `embedding/` and nine `util/` text tools: `arguments` 1
(`structure_to_embed_mfile.m:45`), `readlines` 6, `writelines` 11, `string()`
21 across 12 files, `strings()` 5, `"…" + x` 6, `mtree` 1
(`adigatorScanEmbedUnsupported.m:29`, no Octave equivalent); `contains` 8 in
the engine folders. Important runtime semantics are **silent**, not errors
(OC-10): Octave runs an `arguments` block with validation *and defaults
skipped* (printing a warning) — `structure_to_embed_mfile('f', S)` then dies
on the unset `outPath` default — and `"a" + "b"` is numeric addition (195),
so the six `+`-concatenation sites would miscompute rather than fail.

### 7.3 The transformation engine itself (Tier 2) — measured feasible

On a scratch copy of the engine (the repository was not touched), four small
MATLAB-neutral edits and one shim were enough:

| Blocker | Where | Patch | Octave-only? |
|---|---|---|---|
| **BG-07** unescaped `(` in the only engine regexp: `FunStrChecks{Fcount} = ['\W',CheckName,'(']` | `adigator.m:509`, used at `adigatorPrintTempFiles.m:636` (`regexp`) and reused *raw* as a `strfind` needle at `:649,:657` | escape for the regexp, keep a plain copy for the `strfind`/print sites; escaping alone silently dropped the statement prefix of rewritten calls | MATLAB tolerates the unmatched paren; the latent fragility (a function name with regexp metacharacters) is MATLAB's too |
| **BG-08** `@cada/numel.m` declared `numel(x)`; Octave calls it with index arguments during nested property assignment | dies at `adigatorFunctionInitialize.m:710` | `function y = numel(x, varargin)` (as `@cadastruct/numel` already does) | yes |
| **BG-09** reliance on `rehash` to pick up the rewritten `adigatortempfunc<k>.m` | `adigator.m:664-666` | `clear` the temp functions after `rehash` | yes, but **silent**: in one Octave session the second generation differentiates the *previous* user function (measured: the legacy 42-rule sweep reported 664 violations with `test_sqrt_dx.m` carrying `abs`'s derivative; 0 violations after the patch). Principle-1 relevant for any Octave use. |
| **OC-05** dependency discovery: `verLessThan('matlab')` errors, `matlab.codetools.requiredFilesAndProducts` has no counterpart | `adigator.m:1211,1259` | a recursive identifier-scan walker (`which` → keep `.m` files outside `OCTAVE_HOME` and the engine root) | yes; an entry-file-only shim produces numerically equal but *structurally different* output (subfunctions inlined) |
| **OC-06** `©`/`ç` emitted as `char(169)`/`char(231)` | `cadaPrintGeneratedHeader.m:71-72` | emit UTF-8 bytes or ASCII | yes (Octave writes ISO-8859; every reload warns; `regexprep` refuses the bytes) |

With those in place (verified directly for the first case, re-run from the
patched copy): `adigator('tf1',{x},…)` on `y = sin(x).*x + x(1)*x(2)` yields
the correct seven nonzeros at `[0.3; 1.2; −0.7]`; the finder's runs add:
loop+`if` Jacobian `max|J−Jfd| = 6.3e-11`; Hessian through
`adigatorGenHesFile`'s two-pass re-differentiation `max|H−Hfd| = 1.4e-10`,
symmetric, gradient exact; struct-input Jacobian exact; the legacy 42-rule
unary sweep 0 violations; `examples/jacobians/arrowhead` at `N = 100`
`max|J−Jfd| = 1.7e-9`, `nnz = 298`; and the interprocedural `gapfun`
generation whose full text differs from the committed MATLAB-captured
`tests/fixtures/gen_dialect/slim0/gapfun_Grd.m` **only by the two
`f.dz_size`/`f.dz_location` lines that inline embed mode strips** (verified
directly: `diff oct_full2.txt fix_full.txt` → those two lines). `cada`
`subsref` (`.`, `()`, chained), `subsasgn`, `end`, binary ops and
`cadastruct` were all exercised. The "heavy classdef dispatch" concern did not
materialise.

What does **not** run after Tier 2 without more work: everything in §7.2
(`embedding/` and the slimmer/peephole/parse-tape tools, the reverse-mode
generator's `readlines`), MATLAB Coder/ERT (never), `numjac` in
`arrowhead/main.m`, `matlab.unittest`.

### 7.4 A staged plan (recommendation; each tier is a CLAUDE.md §4 decision)

| Tier | What | Cost | What a cloud session can then verify |
|---|---|---|---|
| **0** `[cloud]` | `tests/offline/octave_tier0.m`: the two cores + collapse/guide fixture numeric checks + plain-assert ports of the `UBuildCSC`/`ULoopboundGuard`/`UPruneMat`/`ResolveDerLevels`/`NormalizeEmbedMode` cases; a 2-minute `octave` job in `ci.yml` (`apt-get install octave`, no licence) | S | the CSC canonicaliser, the prune/strip tools, the loopbound guard shape, the committed derivative fixtures — on every PR, today |
| **1** `[octave]` | rewrite the six `"…" + x` sites and the one `arguments` block to char-based forms (MATLAB-neutral, recommended over a `string` shim); rename `do`; shims for `readlines`/`writelines`/`contains`/`strip`/`import`; a ~300-line `+matlab/+unittest/TestCase.m` handle-class shim with `PathFixture`/`WorkingFolderFixture` and a regexp-based `methods (Test)` discoverer (a probe showed an *unmodified* test method passing under such a shim; `meta.class` introspection does not work, source regexp does). API surface by call count: `verifyEqual` 523, `applyFixture` 288, `verifyTrue` 169, `verifyFalse` 112, `verifyError` 82, `verifyEmpty` 60, `verifySize` 31, … | M | the nine util-only unit classes (78 methods: `UFieldSliceTest`, `UForwardTapeTest`, `UParseBlockTest`, `UPeepholeTest`, `USlimDerivFileTest`, `USlimEngineTest`, `UPatchTest`, `UEmbedMfileTest`, `UStripDeadOutputIndicesTest`) — the family most recent PRs touch — plus the embedded and reverse generators on fixtures |
| **2** `[octave]` | land BG-07/08/09 + OC-06 as MATLAB-neutral fixes; add `lib/adigatorRequiredFiles.m` (MATLAB branch unchanged, Octave branch = the walker, validated by regenerating the three committed fixture families and diffing modulo header/data lines); `tests/offline/octave_regen_fixtures.m` | M | **regenerate** `gen_dialect`, `guide`, arrowhead, pipg in Octave and diff against the MATLAB-captured copies: ADR-0008's revisit conditions (a) *and* (b) — generation and staleness detection — without a licence; most of `tests/unit` and the classic-mode half of `tests/integration` become runnable |

Not in scope at any tier: Coder/ERT (§3.2 of `CI_PLAN.md` stays binding), the
Monte-Carlo codegen oracle, the footprint gates. An Octave leg is a *second*
implementation of the runtime, so per `REVIEW_CONTEXT.md` §"Drift hardening"
it is a check, not a proof: MATLAB-vs-Octave agreement on generated text is
evidence about the engine's determinism, not about correctness; the value
oracles remain the correctness claim.

*Doc consequence (DD-28, `[cloud]`):* reword `CI_PLAN.md` §0, `DESIGN.md`
§Constraints and `docs/README.md` Requirements to the measured boundary ("the
transformation core runs in GNU Octave ≥ 8.4 given …; the embedding layer and
the util text tools need a shim; Coder/ERT are MATLAB-only"), and amend
ADR-0003/ADR-0008 when a tier is adopted.

---
## 8. Potentially publishable parts

Two senses, as asked: scientific publication, and publication of the software
and its artifacts. The literature positioning below is from web searches run
during the review (queries listed in Appendix B); "not found" means not found
by those searches, not absent.

### 8.1 The standing decision

**PB-01** ROADMAP R13(4) records "defer the paper" (issue #18, 2026-06-24) with
the stated condition "once R10–R12 settle" and the go/no-go chained to the R6
gate. R10 and R11 are done, R12's determination is recorded (ADR-0016), R6 is
undecided (DD-38). Since then the fork gained reverse embed parity (R16), the
compiled comparison (R17/ADR-0027), the strict-ERT config and stack-parity gate
(ADR-0033/0035), the B37 63×→1.03× result (ADR-0036), the loopbound Hessian
(ADR-0028), the CSC contract (ADR-0030), the CasADi oracle (ADR-0018), the
born-ERT codegen oracle and the provenance header. The deferral's condition has
fired and `CONTRIBUTING.md` §"Deferral sweep" says silence is the one
prohibited outcome: a decision issue is owed (§9, WP-C8 adds it).

### 8.2 Candidate contributions, positioned

| # | Candidate | Novelty as found | What exists in the tree | What is missing for a credible paper | Effort / env |
|---|---|---|---|---|---|
| **PB-02** | Embeddable static-sparsity AD from MATLAB source under strict Embedded Coder (no heap), with the generator-overhead gate calibrated to hand-written code (ADR-0035) and overmap-directed pruning (ADR-0036) | Real but narrow. CppADCodeGen advertises statically allocatable derivative code for hard real-time loops; CasADi/acados/ACADO generate self-contained C from expression graphs; OpEn/GRAMPC/TinyMPC target MCUs. Not found: AD of *MATLAB source* into Coder/ERT-ready files, or a CI gate bounding generator overhead per case against a hand-written reference | ADR-0035/0036 tables, `SHOWCASE.md` C-level table and figure, `bench_compare.tex`, `SStackScalingTest`, `measureErtFootprint` | every footprint number is a **host MinGW object**, not a target; one Windows host; `n ≤ 64`; four toy anchors; no cross-tool comparison (ADR-0018's "benchmark side" never built) | L, `[coder]` + a cross-compiler |
| **PB-03** | Padded loop-bound semantics: one generated file exact for every `n ≤ Nmax`, inner-exit unions (B27), specialisation guards (B36–B39), and the loopbound Hessian (ADR-0028) | The most AD-specific novelty found. Searches return only Coder's bounded variable-size data and horizon-fixed MPC generators; no AD tool found that emits a size-generic derivative whose sparsity is a trip-count-dependent union | `ILoopboundTest` (753 lines), `IAllocationTest`, ADR-0028, the padding-penalty table, E5/E6 | **its correctness claim is in question until BG-11/12/13 are reproduced in MATLAB and then refused or fixed**; the penalty figures are made of the `Nmax`-sized tables R21 would delete (the engine-v2 analysis says so); no support matrix of matched/refused/out-of-scope loop shapes | M, `[matlab]`; the support matrix is the paper's semantics section |
| **PB-04** | Reverse mode as a transformer over the static forward tape (`_RGrd`, `_JtV`, zero-static-data adjoints) | A design choice rather than a new AD mode (Tapenade/ADIFOR, CppADCodeGen, CasADi, Enzyme all do adjoint source generation); the angle is "a ~30-shape generated dialect as the tape, sizes resolved at generation, no printer change" | ANALYSIS §3.5 table, SHOWCASE convergence result (forward and reverse gradient ROM 208/208; runtime comparable) | rolled-loop reverse (R19), H·v/J·v (R18), the `mrdivide` adjoint (R30), the #206 support matrix (PR #247, open at `a4e24bc`), six adjoints never value-checked (CG-08), BG-41/42 | L; a *section* of the tool paper now, EuroAD-talk ready |
| **PB-05** | N-D parameter veneer; CSC-ordered nonzero output | Not standalone: CSC is CasADi's long-standing convention (ADR-0030 does not cite it); the "~2× metadata" win is measured against the fork's own removed v1 surface | `ICscOutputTest`, `SCscMetadataTest` | — | fold into the tool paper's design section |
| **PB-06** | The V&V methodology: tolerance-free relation oracles, Monte-Carlo fuzzing of an AD tool, CasADi as same-source oracle, the "hollow milestone" (ERT-clean but 63× stack) | Builds on nablaFuzz (ICSE 2023: differential testing of forward/reverse/numeric AD, 173 bugs) and metamorphic-testing prior art; the fork's distinct additions are the *embeddability* oracles (compiled-C ≡ interpreted under strict ERT; stack ≤ K × hand-written) and the cross-tool same-source oracle | ADR-0007/0014/0018, 10 oracles, `MCSmokeTest`, `mcShrink`/`mcPromote` | **the evidence is currently against it**: the battery's catalogued yield is one hygiene bug (B16); `regressions/` is empty; the per-merge smoke never ran on `master` (TF-01); the five-op vocabulary (CG-17) never reached any of §4.1's rule defects, which were found by reading; the CasADi benchmark side is unbuilt | M, `[matlab]`: widen the vocabulary (CG-17), re-run a 10k campaign, report yield per oracle with §4 as ground truth, then ISSTA/ICST industry track or EuroAD |
| **PB-07** | The agentic-development discipline as a software-engineering case study | A credible experience report with a dense public dataset: 417 commits, 179 pull-request merges recorded in that history (`git log --format=%s a4e24bc`: 136 squash subjects ending in `(#n)` plus 43 `Merge pull request` commits), 38 ADRs, mixed human/agent authorship (`git shortlog -sn a4e24bc`: `pdlourenco` 192, `Claude` 89, `Pedro Lourenço` 81, the four upstream authors 55), the evidence-discipline section already proposed upstream (seed #53), the suite-loss guard (#235). Related work: early case studies of LLM agents on scientific computing (arXiv 2602.04445), ADR generation/violation detection by LLMs (ICSE 2026 workshop, arXiv 2602.07609) | the ADRs, `REVIEW_CONTEXT.md` §Evidence discipline with its instances, `DISCIPLINE_ADOPTION.md`, `ci_suiteGuard` | the honest version includes where the discipline drifted: TF-01, TF-02, TF-03, the phantom tests, the 36-day suite loss; the maintainer authoring both the seed and the project is a threat to validity to state | M, `[cloud]`: ICSE-SEIP / FSE industry / CAIN, or an MSR data showcase of the ADR+PR corpus |

**Venue fit (PB-16/17/18).** (a) An **ACM TOMS "Remark on Algorithm 984"** is
the strongest fit for the correctness work and needs no live upstream: a
Remark "corrects or modifies the code" of a published algorithm with
"evidence that illustrates the original problem"; the fork holds the B-series
fixes cherry-pick-ready (ADR-0013) and §4.1 adds upstream rule defects that,
once reproduced, fixed and pinned, are exactly that evidence. (b) A
**software paper** (JOSS, which has published MATLAB toolboxes, or SoftwareX)
fits structurally (OSI licence, public tracker, 384 tests, PDF guide) and is
blocked only by the missing tag/DOI, the absent `paper.md`, the open
output-licence question (#239) and CI claims a reviewer would find false
(TF-01). "Build vs contribute" is pre-written in ADR-0013. (c) An **AD
workshop** talk: EuroAD 29 (September 2026) has passed; the next slot is
EuroAD 30 (2027). (d) The **domain case study** (#18 option 3: embedded
control allocation over time) has its example inputs in the tree but no
closed-loop solver, no target timing and no end-to-end "one file across
`(N,K)`" demonstration beyond interpreter tests (PB-21) — drop it from the
decision unless a real target measurement is planned.

**Evidence inventory (PB-20).** Citable with a regeneration recipe today:
the ADR-0035/0036 tables, the four `SHOWCASE.md` tables and
`showcase_scaling.png`, the ANALYSIS §3.5 static-data series, the two guide
fragments. Prose-only (no committed data or script): the E1–E6 harnesses
("scratch files … not retained"), the `mcCampaign(150)` "150/150" validation
(no `mcReport` output committed), the CasADi agreement values (ADR/issue text
only), the ADR-0036 440-event census (instrumented scratch engine). A
`bench/results/<date>-<machine>/` convention with provenance headers would make
the next measurement citable (WP-K4 extends to this).

### 8.3 Software publication and release readiness

- **PB-08** The v2.0 cut is procedurally fragile: `[Unreleased]` still carries
  the framing blockquote and HTML comment that `extract` publishes verbatim
  (#233, open at `a4e24bc`); `Contents.m`'s "(unreleased)" banner is outside the release
  gate.
- **PB-09** No release checklist exists: the recipe in `CONTRIBUTING.md` never
  runs `tests/ci_ert.m` or the Monte-Carlo campaign that ADR-0007 and the same
  document call "release-checklist runs", and "tag a green `master`" means
  unit + integration only (TF-01).
- **PB-10** Product-level blockers: the output licence is undefined (#239);
  embed-mode output depends on the GPL library at runtime through `interp2`
  (#249, one overload — HY-05); the ADR-0013 upstream courtesy issue was never
  filed.
- **PB-11** Citation infrastructure is absent: no `CITATION.cff`, `codemeta`
  or `.zenodo.json`; the README cites only upstream's 2017 TOMS paper; a Zenodo
  DOI needs a GitHub release; the repository has no topics or homepage.
- **PB-12** Release-archive hygiene: the curated distribution ships
  `docs/README.md` and `docs/DESIGN.md` with 10 and 16 links into stripped
  folders, strips `bench/SHOWCASE.md` that the README sends users to, and the
  publisher-copyrighted PDFs it declines to "redistribute inside its release"
  remain tracked in the public repository and inside GitHub's auto-generated
  source archives attached to every release; the redistribution basis of each
  PDF is recorded nowhere. Add a link-check step over the assembled archive;
  record the basis per PDF or replace them with their DOIs (already in the
  README).
- **PB-13/14/15/19** Independently publishable artifacts: the user guide (as a
  technical report / Zenodo deposit; carries no licence statement of its own
  and derives from upstream's guide); `bench/SHOWCASE.md` (publishable in
  *form*, not yet in substance: one Windows host, host objects, `n ≤ 64`,
  single-sample timings); the evidence-discipline section (already proposed to
  the seed as #53; a short experience report with the analyses README's "a
  recorded command is a claim, not a fact"); the Monte-Carlo harness as a
  reusable AD-testing *pattern* (case contract, relation oracles,
  shrink/promote, coverage tracker), not as a package (bound to adigator
  internals).

**Recommended sequencing** (to be decided under CLAUDE.md §4, WP-C8): tag v2.0
after PB-08..12 → Zenodo DOI → software paper (JOSS/SoftwareX) → TOMS Remark
once §4.1 is reproduced, fixed and pinned → the embedded/tool paper only after
a real-target measurement and the CasADi benchmark side exist.

---
## 9. The plan

Ordered by one rule: **arm the gates before adding to what they gate**, then
correctness, then the documentation that describes both, with the
licence-free work front-loaded so a cloud session is never idle waiting for a
MATLAB machine. Each work package carries its environment, an effort estimate
(S < half a day, M one to three days, L more), what it closes, and whether it
needs a CLAUDE.md §4 decision first (marked **§4**). The two-session workflow
of `CONTRIBUTING.md` applies: a cloud session can *author* every `[matlab]`
test and code change below as a PR; only the verification run and the
"verified, push" step need the licensed machine. ROADMAP rows are not edited by
this review; §9.6 lists the rows the maintainer may want to promote.

### 9.1 Cloud session, now (no MATLAB)

| WP | What | Closes | Effort | §4 |
|---|---|---|---|---|
| **C1** | `extended.yml`: `push: branches: [master]`, drop `embedded` from both workflows, re-add `schedule:` (weekly is enough for drift detection), then dispatch once on `master`; delete the `embedded` branch; correct `CI_PLAN.md:176,190,345,465`, ADR-0032's per-merge wording, `MCSmokeTest.m:4-6`, `SExamplesTest.m:11`, `SCscMetadataTest.m:11` | TF-01, DD-02, DD-16, HY-07 | S | **§4** — the trigger, the schedule cadence and the `embedded` deletion are C8(x); the doc corrections are mechanical |
| **C2** | Doc-drift batch: DD-01, DD-03, DD-04, DD-06..DD-15, DD-19, DD-21, DD-22, DD-23 (the "47 artifacts" sentence; the ERT/stack sentences flagged "to re-measure"), DD-24..DD-31, DD-33..DD-37, DD-39, DD-40; the `norm` wording in TS-U-17 (CG-05); register the eight unregistered classes. Out of the batch as decisions: DD-05 (REQ-C-02/03 vs the tests, C8(xiii)), DD-17 (the C-1 contract text, C8(xi)), DD-18 (`REVIEW_CONTEXT.md` principle 4, C8(xii)), DD-32, DD-38 | §5 | M | — for the batch; its contract and principle items are C8(xi)–(xiii) |
| **C3** | Licence-free gates, in python under `.github/scripts/` and wired into `ci.yml` after the MATLAB steps (they read the JUnit XML the run already uploads) and into a `docs-lint` job for the text checks: (a) **stale-`KnownIssue` detector** — fail when a `KnownIssue`-tagged method appears as *passed* or *failed-not-filtered* (the Phase-2 "planned, not yet implemented" item). MATLAB's documented JUnit format carries no test tags (per the documentation, not checked against a produced file), so membership comes from scanning the test sources for `TestTags = {'KnownIssue'}`; the step needs `if: always()`; Coder-gated `KnownIssue` methods are filtered on the licence on CI and invisible to it, which its output must say. **Lands after M2** has removed the six B7–B10 tags — the only `KnownIssue` block in the tree (`IShapeMatrixTest.m:136`) passes today, so the rule would fail `ci.yml` the day it arrived — or earlier with an explicit, expiring allowlist naming those six methods; (b) **per-method suite ratchet** (#236) — committed `tests/suite_baseline.txt` of `class: method-count`, fail on a drop; (c) **error-without-identifier ratchet** (HY-01); (d) **principle-8 token lint** over `docs/README.md`, `docs/userguide/*.tex`, `bench/SHOWCASE.md` (DD-24); (e) **ADR revisit sweep** printing every clause for the deferral sweep; (f) a markdown link/anchor checker. Each is a few dozen lines; (a) and (b) close the two gate holes this review found that `ci_suiteGuard` cannot | TF-02 (detector half), #236, HY-01 | M | **§4** — new CI gates and a new committed artifact (`tests/suite_baseline.txt`): C8(xiv) |
| **C4** | Engine and utility fixes, **one PR per fix, each with its pin in the same PR** (principle 6; M10 verifies locally): (a) **BG-39** first, in its own PR with the random round-trip test (Appendix B generator) — critical; (b) the crashes and loud defects BG-26 (`NUMvars`), BG-27 (`ErrorLocs`), BG-28 (`OVERMAP`), BG-31 (`ppknown`), BG-32 (`keyboard` → error), BG-38, BG-40, BG-43 (`mat2str` for vector options + the drift assertion), BG-44 (`adigator.m:129`), BG-46 (move the `nargout` check inside the `try`); (c) BG-07 (escape the regexp, keep a plain copy for `strfind`), MATLAB-latent and on its own merit; (d) the Octave-only edits — BG-08 (`numel(x, varargin)`), BG-09 (`clear` temp functions after `rehash`), OC-06 (UTF-8 header bytes; it changes the header bytes of every generated file, so a fixture recapture), HY-08 (`do` → `doi`) — **wait for C8(iv)** | §4.2–4.5, §7.3 | M author / S verify `[matlab]` per PR | (d) waits on C8(iv); (a)–(c) need none |
| **C5** | Octave **Tier 0** job: `tests/offline/octave_tier0.m` (two cores + fixture numeric checks + plain-assert ports of the five util classes), `apt-get install octave` step in `ci.yml` | OC-00, §7.4 | S–M | **§4** (adds an external dependency and a CI leg; amend ADR-0008) |
| **C6** | Author (for `[matlab]` verification) the test-strengthening PRs of §2: TF-02 scaffold removal + B10 pattern asserts, TF-06 `coder.*` assume-in-setup, TF-09 csc FD oracle, TF-10 example asserts, TF-11 `GenFiles4` values, TF-26..TF-34, CG-18 contradictions | §2.3 | M author | — |
| **C7** | Hygiene: `CONTRIBUTING.md` error-id namespace rule; `git update-index --chmod=-x` sweep + `.gitattributes` guard; then, once decided, `CITATION.cff` and the SHA-pinned actions | HY-01/02/05/09 | S | **§4** — `CITATION.cff` authorship/attribution and the SHA-pinning policy are C8(xv) |
| **C8** | **Surface the decisions** this review cannot take, each with the recommendation marked: (i) `'l'` mode — emit the planned deprecation warning now *(recommended)* or document "no warning yet" (DD-20); (ii) ADR-0021's removal gate — re-defer with a measurement task (WP-K2) *(recommended)* or decide on the ERT-fails argument; (iii) tolerance policy — reword `REQ-T-01` to the enforced central-FD `1e-5`/`1e-4` and make analytic the primary oracle where available *(recommended)* or tighten the tests to `1e-6`; (iv) Octave tiers 1–2 (ADR-0003/0008 amendment) *(recommend Tier 0 now, Tier 1 next, Tier 2 after the engine fixes land)*; (v) generated-output licence statement + #249 scope (one overload); (vi) whether BG-01's fix lands as "fix + pin" or "refuse active scalar `mod` divisor until pinned" *(recommend fix + pin; the rule is right, only the guard is inverted)*; (vii) REQ-T-10's `'l'` clause (DD-32) *(recommend: amend to `'i'`)*; (viii) the R6 gate (DD-38) *(recommend: re-defer with the R21-step-2 re-measurement as the dated condition)*; (ix) the paper go/no-go (PB-01, §8.3 sequencing); (x) the Extended trigger — `push: [master]` plus a weekly `schedule:`, and delete the `embedded` branch after the first green `master` run *(recommended; the alternative keeps `embedded` as an archive tag)*; (xi) DD-17, the C-1 contract text in `DESIGN.md:103` *(recommend: a pointer note to ADR-0030, no behaviour change, as the R31 census promised)*; (xii) DD-18, `REVIEW_CONTEXT.md:59` principle 4 *(recommend: restate the bar as strict Embedded Coder per ADR-0033/REQ-T-10)*; (xiii) DD-05, REQ-C-02/03 vs the tests *(recommend: widen the tests, CG-01/CG-03, not narrow the rows)*; (xiv) C3's new licence-free gates and the committed `tests/suite_baseline.txt` *(recommend: land (b)–(f) now and (a) after M2)*; (xv) `CITATION.cff` authorship/attribution and SHA-pinning of actions *(recommend both; the authors line is the maintainer's to write)*; (xvi) the ratchet re-baselining policy for M3 *(recommend: a ratchet moves only upward, in its own commit, citing the run it was read from)*; (xvii) BG-11/13 — refuse the two loop shapes with new error ids, or pad them correctly *(recommend: refuse now with ids and fix later; a wrong gradient outranks a refusal, principle 1)*; (xviii) the M10 policy forks — BG-18 tie semantics *(recommend one-hot, first-argument-wins, matching MATLAB's `max` index)*, BG-20's emitted input guard *(recommend the B36-style assert with `auxdata = 1` opt-out)*, BG-23 NaN-vs-extrapolate *(recommend: document now, mask to `NaN` in a later release)*, BG-47's stamp semantics *(recommend: document the gap now, sign inputs with R21)* | DD-20, DD-32, DD-38, §5.4, TF-05, §7, HY-05, BG-01, PB-01, TF-01, DD-17, DD-18, DD-05, C3, PB-11, HY-09, TF-03/04, BG-11/13/18/20/23/47 | S | **§4** all |

### 9.2 Cloud session with Octave

| WP | What | Closes | Effort | §4 |
|---|---|---|---|---|
| **O1** | Tier 1: char-based rewrite of the six `"…" + x` sites and the `arguments` block (`structure_to_embed_mfile.m`), shims (`readlines`, `writelines`, `contains`, `strip`, `import`, `PathFixture`, `WorkingFolderFixture`), the `+matlab/+unittest/TestCase.m` shim and `tests/octave_run.m` (source-regexp discovery of `methods (Test)`); run the nine util-only unit classes (78 methods) in the Octave job | §7.4 Tier 1 | M | **§4** |
| **O2** | Tier 2: with C4 merged, add `lib/adigatorRequiredFiles.m` (MATLAB branch unchanged; Octave branch = the identifier walker, validated against the three fixture families), `tests/offline/octave_regen_fixtures.m` regenerating `gen_dialect`/`guide`/arrowhead/pipg and diffing modulo header/data lines; run the classic-mode half of `tests/integration` | ADR-0008 revisit (a)+(b); staleness detection without a licence | M | **§4** |
| **O3** | Use Octave to *pre-verify* every `[matlab]` test authored in C6/§9.3 whose fixture avoids `embedding/`: the rule/shape/mask/while/high-level-op classes of §3 run on the Tier-2 engine, so the local MATLAB session receives tests that already pass once, cutting its round trips | §3 | ongoing | — |

### 9.3 Local session, base MATLAB

In priority order; the first three are one session.

| WP | What | Closes | Effort |
|---|---|---|---|
| **M1** | Reproduce the §4.1 critical batch in this order, each with its listed fixture vs `fdcheck`/closed form: **BG-24** (the unparsable `mod`/`rem` y-only file; it blocks BG-01's y-only pin), **BG-01** `mod` guard, **BG-02** `sum(X,2)` order, **BG-06** inline-block zero locations, **BG-05** logical zero masks, **BG-04** overdetermined solve (both entry points), **BG-25** non-square `x/y`, **BG-10** solve-sparsity cancellation, **BG-03** `cross` (both operand kinds; BG-51 first), **BG-11/12/13** the loop shapes — **one PR per bug, each flipping its `KnownIssue` pin to a hard assertion**; the review's R2024a results (§4 preamble) already cover the reproduce half for BG-01/02/03/05/06/10/11/12/13/24/39. The fixes are one to ten lines; whether BG-11/13 are refused or fixed, with their new error ids, is C8(xvii). Enter the confirmed ones in `ANALYSIS.md` with their pins; then land the **binary-rule matrix** of CG-01 in `URulesBinaryTest` | §4.1, CG-01, DD-05 | M + M |
| **M2** | Verify C4 (engine fixes) and C6 (test strengthening) — confirm the six B7–B10 methods pass as hard assertions, drop the `KnownIssue` tag, update ANALYSIS §1.5 / CI_PLAN TS-I-01; confirm the `coder.*` setup assume; run the csc/example/`GenFiles4` value checks | TF-02, TF-06, TF-09..11, TF-26..34 | M |
| **M3** | Ratchets: read the current PR-gate coverage rate and commit it; extend `ci_lint`'s folders and switch it to a finding-set baseline; raise the per-folder floor from the first `master` Extended run — **§4**: the re-baselining policy (what moves a ratchet, when, and who records it) is C8(xvi) | TF-03, TF-04, ADR-0032 | S |
| **M4** | Tolerance policy per C8(iii): polydatafit analytic oracle; `UNormTest` analytic at `1e-12`; `URulesUnaryTest` central FD | TF-05 | S |
| **M5** | Unary shapes + derivative-free family (CG-02); high-level ops + `mldivide`/`mrdivide`/`inv` + `repmat` (CG-03); struct-array ops (CG-04); masks/logicals (CG-06); `norm` cells + `badp` (CG-07); reverse adjoints (CG-08) | §3.1 | L (can be split per class, each S–M) |
| **M6** | `while` loops (CG-09); `complex=1` consistency, `auxdata=1`, row-vector VOD, reverse × csc (CG-10); vectorized Jacobian/Hessian (CG-11); higher-order rules (CG-12); path hygiene (CG-13); publish the option × DerType support matrix | §3.2 | L (split) |
| **M7** | Error ids: the 25 untested ids (`subsOutOfRange` first), identifier for the `sign` warning, the `while` exhaustion error (#246) | CG-16 | M |
| **M8** | Monte-Carlo vocabulary: full `getdydx` table with domain-safe sampling, `./`, `.^`, `atan2`, `mod`/`rem`, `max`/`min`, an `xshape` draw; a committed synthetic reproducer so `MCRegressionTest`'s body executes | CG-17, TF-30, TF-31 | M |
| **M9** | Examples: parameterised smoke over `discoverExamples()` in the Extended job; curate the vectorized mains; `GenFiles4` numeric pins or the ADR-0037 note | CG-14, CG-15 | M |
| **M10** | Reproduce the remaining §4 candidates (BG-14..BG-23, the fork-layer BG-41/42/45/48/49, then §4.2's loud defects BG-26..BG-35 and BG-51, then the latent BG-36/37) with the listed repros; verify the C4 PRs; the policy forks inside this batch are C8(xviii) (BG-18 tie semantics, BG-20's emitted guard, BG-23 NaN-vs-extrapolate, BG-47's stamp semantics); enter confirmed ones in `ANALYSIS.md` with pins; add `IBreakContinueTest` from the eight passing probe shapes and `INestedLoopTest` for the `1:i` inner-bound shapes at first and second order | §4 | per item (most S) |

### 9.4 Local session, MATLAB + Coder / Embedded Coder / gcc

| WP | What | Closes | Effort |
|---|---|---|---|
| **K1** | `built` flag in `measureErtFootprint`/`measureStackScaling`/`loopboundPaddingPenalty` and `assertTrue(all built)` before the toolchain `assume`; `ci_ert` non-zero exit on PARTIAL/ABSENT; Linux-capable `gcc`/`size` probe (or document Windows-only) | TF-07, TF-08, TF-35 | S–M |
| **K2** | The measurement ADR-0021 is gated on: compiled ROM/RAM/stack of `'l'` vs `'i'` vs (a prototype) split-inline on the data-heavy showcase cells; record in `SHOWCASE.md`; then decide R24 | §5.4, DD-20 | M |
| **K3** | Re-measure the two CHANGELOG limitation sentences (unslimmed inline Hessian under ERT; rolled-form stack law) and correct whichever document is stale | DD-23 | S |
| **K4** | After any engine fix (M1, M10, C4): `tests/ci_ert.m` attestation + `SStackScalingTest` recorded in the PR; start a `bench/results/<date>-<machine>/` convention so the next measurement is citable (PB-20) | §4, PB-20 | S each |
| **K5** | ADR-0028: a lockstep test over the five loop-guard emission sites (text equality of the emitted guard across sites, or one shared emitter) | §5.4 | S |

### 9.5 Sequencing

1. **Week 1, cloud:** C8 first (C1, C3, C7, M1 and M3 each wait on one of
   its items; C2's batch does not, its three decision items do), then C1, C2,
   C3 except its (a), C7. Author C4 (a)–(c), C5,
   C6 as PRs. Nothing here needs MATLAB and everything later benefits from it.
   A MATLAB session need not wait for week 1: M1 can run in parallel with
   C1/C2, one PR per bug, and the review's R2024a results already supply the
   reproduce half.
2. **MATLAB session:** M1 (the critical candidates, per-bug PRs) → M2 → C3(a)
   → M3 → M4,
   verifying C4/C6 on the way; run `ci_ert` once (K4) and attach it.
3. **Then in parallel:** cloud O1→O2→O3 (as decided in C8(iv)); MATLAB M5–M9
   split into per-class PRs, each pre-verified in Octave where the fixture
   allows; Coder K1–K3, K5 when the licensed machine is free.
4. **M10 / §4 candidates** are interleaved by severity as reproductions
   confirm or refute them; a refuted candidate is recorded as refuted in the
   PR that tried it, so the next review does not re-find it.
5. **Publishing (§8)** waits for 2–3 to settle: the value-oracle widening of
   M5–M8 and the armed gate are what make the V&V claims citable. The release
   blockers PB-08..PB-12 are all `[cloud]` and can run alongside week 1.

### 9.6 ROADMAP rows the maintainer may want to promote (not edited here)

- a **"Gate integrity" row** covering C1 + C3 + M3 (the ratchet-and-detector
  set), because the suite-loss incident (#235) and TF-01 are the same failure
  class and both were invisible until someone counted;
- a **"Rule-table value coverage" row** (M1, M5, M8) with the explicit goal that
  every `getdydx`/`getdzdx`/`getdzdy` entry has a value oracle at two shapes
  and two orders, which is the measurable version of REQ-C-01/02;
- an **"Octave tiers" row** tied to the ADR-0003/0008 amendment;
- a **"Support matrix" row** (CG-10) that R25 phase 2 already promises.

---
## Appendix A — Finding register

One row per finding, in section order; the body carries the evidence. Severity and environment as stated there ("-" where the body gives them in prose; for TF-12..TF-25 the Severity column carries the §2.2 verdict); a finding whose first sentence is long is clipped at a word boundary ("…"). OC- numbers follow the Octave finder's list and have gaps: the three engine defects became BG-07..09, the header-bytes, `do`-keyword, `\b`-regexp and construct-census items were folded into HY-08 and §7.2, and the staged plan and example census into §7.4 and §7.1.

| ID | Severity | Finding | Env |
|---|---|---|---|
| TF-01 | high | the Extended workflow does not run on the default branch | cloud |
| TF-02 | high | the B7–B10 "regression guards" filter on their own failure modes | matlab |
| TF-03 | medium | the PR-gate coverage ratchet is a one-time floor | cloud,matlab |
| TF-04 | low | the lint ratchet tolerates 423 findings and scans a subset of the tree | cloud,matlab |
| TF-05 | medium | the tolerance policy in `REQ-T-01` is enforced nowhere, and one tolerance is set by the oracle rather than the derivative | matlab |
| TF-06 | medium | the `coder.*` catch idiom filters a class of embed-pipeline regression on every runner | matlab |
| TF-07 | medium | the footprint gates convert a failed build into "toolchain absent". `bench/loopboundPaddingPenalty.m:86` initialises `fp = struct('rom',-1,'ram',-1,'stack',-1)` and `:118-120` catches the … | coder |
| TF-08 | medium | `ci_ert` prints `PARTIAL` but exits 0 | coder |
| TF-09 | medium | csc-mode tests compare against the matrix mode of the same generator and call it an FD check | matlab |
| TF-10 | medium | two of the five "numeric-assertion" examples assert nothing | matlab |
| TF-11 | medium | `IGenFiles4Test` pins text shape only | matlab |
| TF-12 | lapsed | extended trigger → `push: [embedded]`, cron dropped | - |
| TF-13 | wrongful | B7 fixed and B8–B10 fixed with the pins left as `KnownIssue` self-healers | - |
| TF-14 | questionable | polydatafit `RelTol 1e-3 → 5e-3` + oracle swapped to test-side FD | - |
| TF-15 | questionable | `ILoopboundTest` exact padded-tail assertion wrapped in `if numel(vm.f) == Nmax … else verifySize(vm.f,[n 1])`; the padding-unsafe pin fixture changed `zeros(N,1) → zeros(6,1)` | - |
| TF-16 | wrongful (test bent to the implementation, against C-6) | `IEmbedModesTest` expected `'Grd(['` changed to `'Jac(['` to match the generator | - |
| TF-17 | low | `UNormTest.matrixNormErrors` accepts `MATLAB:norm:unknownNorm` alongside the C-5 id for `p = -Inf` | - |
| TF-18 | low | `SLoopboundPaddingTest` ROM-ratio floor at `n = Nmax` `≥ 0.95 → > 0.75` | - |
| TF-19 | low | `SCodegenShowcaseTest` dropped `rev < fwd` and `ana ≤ fwd` source-byte asserts | - |
| TF-20 | wrongful at the time (silent no-op on Coder-only runners) | `SCodegenTest` ERT lib build wrapped in a silent `if license('test','RTW_Embedded_Coder')` | - |
| TF-21 | maintainer-decided | B16 hygiene invariant weakened strict → populated-only | - |
| TF-22 | low | three "update fixtures" golden regenerations with empty commit bodies (`56bc8f6` deletes 2 `.m` + 2 `.mat`) | - |
| TF-23 | policy, tracked | embed gate `verifyError → verifyWarning` | - |
| TF-24 | low | `hessians/logsumexp` example added to `discoverExamples`' Coder-required skip list | - |
| TF-25 | conformant (one hollow pin, healed) | `KnownIssue` tripwires added for live bugs (B27 silent-wrong, #173, #217 63.4× stack) | - |
| TF-26 | - | `IEmbedSlimTest.m:160` asserts `pinfo.count >= 0` (a tautology) and `:71` `verifyLessThanOrEqual(nB, nA)` accepts a no-op slim; the slim-vs-noslim text assertions no longer discriminate … | - |
| TF-27 | - | `ILoopboundTest.m:121` `verifyError(@() lb_guard_dx(x,Nmax+1), ?MException)` accepts any exception while its input has only `Nmax` entries, so an index-out-of-bounds error satisfies it even … | - |
| TF-28 | - | `IRolledOvermapWidthTest.pruneGateStaysInStepWithTheRemapGate` is a token-presence regexp: it passes if the two gate tokens appear anywhere in each file, not that they gate the same … | cloud |
| TF-29 | - | `IEmbedSlimRolledTest` and `IConcatLoopLiteralTest` fixtures never assert that the generated file actually contains a rolled `for cadaforcount` loop, so a silently-unrolled generation would … | cloud |
| TF-30 | - | `MCRegressionTest` has never executed its body: `regressions/` holds only a README, so the sentinel `'__none__'` (`:44`, `:82`) reports one *Filtered* result per run and the … | cloud,matlab |
| TF-31 | - | `MCSmokeTest.derOutputInvarianceIsClean` draws from `{Affine, Quadratic}` but the oracle is Jacobian-only, so half its cases skip by construction; `codegenEquivalenceIsClean` runs … | - |
| TF-32 | - | `IInterprocGapEquivTest`'s header describes "a genuinely sliced interprocedural file"; the committed `slim0`/`slim1` derivative *code* is byte-identical (the diff is the header stamps and … | cloud |
| TF-33 | - | `UTestPathHygieneTest` scans `tests/unit` and `tests/integration` only; `tests/system` and `tests/montecarlo` classes are unguarded for path-setup presence | cloud |
| TF-34 | - | Reverse-gradient and JtV wrappers carry no #200 generation stamp (`adigatorGenRevGradFile`/`adigatorGenJtVFile` never call `cadaPrintGeneratedHeader`), although `UGenerationStampTest` … | matlab |
| TF-35 | low | the gcc/size footprint probe is Windows/MinGW-only, so the stack and ROM gates can be established on a Windows machine only (§2.4) | cloud,coder |
| CG-01 | high | six of the eleven binary rules have no value oracle | matlab |
| CG-02 | high | unary coverage is scalar-only | matlab |
| CG-03 | medium | fourteen shipped `@cada` overloads have no value oracle in any test: `interp1`, `interp2`, `ppval`, `adigatorEvalInterp2pp`, `cross`, `inv`, `mrdivide`, `prod`, `nnz`, `sub2ind`, `isequal`/ … | matlab |
| CG-04 | medium | `@cadastruct` struct-array overloads | matlab |
| CG-05 | medium | the surface inventory is file-granular, so the 94 methods inside `cada.m` are invisible to the V&V denominator | cloud |
| CG-06 | medium | comparison/logical overloads and derivative flow through masks are untested | matlab |
| CG-07 | low | `UNormTest` covers fewer cells than TS-U-17 claims: row orientation only for `p = 2`; general `p` (`cada.m:697` `sum(abs(x).^p).^(1/p)`) and vector `p = -Inf` never value-checked … | matlab |
| CG-08 | low | reverse-mode adjoints for `tan`, `sqrt`, `sinh`, `cosh`, `asin`, `acos` are whitelisted and emitted (`adigatorGenRevGradFile.m:304-305, 700-716`) but never value-checked: `IRevGradTest` … | matlab |
| CG-09 | medium | no test or example ever differentiates a `while` loop successfully | matlab |
| CG-10 | medium | option/DerType cells with no value-checked test: `complex = 1` (switches real code paths in `abs`, `ctranspose`, `dot`, `norm`: `cada.m:119, 594, 617, 654, 690`; the only occurrence in … | matlab |
| CG-11 | medium | vectorized (`Inf`-dimension) mode has one value-checked fixture (`IAllocationTest`, Jacobian/gradient only) and no vectorized Hessian check; the nine GPOPS-II vectorized example entry … | matlab |
| CG-12 | medium | third order is value-checked by exactly one fixture (`ISpecializedTripCountTest.guardSurvivesToThirdDerivative`, a loop of `x^3`) | matlab |
| CG-13 | low | platform/path handling | cloud,matlab |
| CG-14 | medium | 21 of 26 example entry points run in no test, and the sweep script is wired to nothing | matlab |
| CG-15 | low | the deprecated `GenFiles4*` family: parse/ field/banner pins only (TF-11); `adigatorGenFiles4Fsolve` and `adigatorGenFiles4gpops2` have no test at all; four `adigator:genfiles4*:io` ids … | matlab |
| CG-16 | medium | 25 of 68 `adigator:*` error identifiers have no test that triggers them, and ~400 `error(` sites carry no identifier at all | cloud,matlab |
| CG-17 | medium | the Monte-Carlo vocabulary is far narrower than its description | matlab |
| CG-18 | low | two contradictions inside `CI_PLAN.md` itself: `REQ-C-02` requires every rule incl | cloud |
| BG-01 | critical | `mod(x, y)` with an active *scalar* divisor applies the `d/dy` rule only when `y == 0` | matlab |
| BG-02 | critical | `sum(X, 2)` on a matrix emits the derivative in the wrong order when a variable touches a non-monotone set of entries | matlab |
| BG-03 | critical | `cross(X, Y, 1)` on a `3×N` matrix with `N ∉ {1, 3}` applies the row permutation in the wrong direction | matlab |
| BG-04 | critical | overdetermined `A\b` with constant `A` and active `b` emits no derivative at all | matlab |
| BG-05 | critical | `cadabinarylogical` builds the *second* operand's known-zero mask from the *first* operand's zero locations | matlab |
| BG-06 | critical | an inline numeric block in a concatenation records its *nonzero* `(row, col)` pairs as `func.zerolocs` | matlab |
| BG-07 | - | unescaped `(` in the only engine regexp: `FunStrChecks{Fcount} = ['\W',CheckName,'(']` (`adigator.m:509`, used at `adigatorPrintTempFiles.m:636` (`regexp`) and reused *raw* as a `strfind` … | octave |
| BG-08 | - | `@cada/numel.m` declared `numel(x)`; Octave calls it with index arguments during nested property assignment (dies at `adigatorFunctionInitialize.m:710`; §7.3) | octave |
| BG-09 | - | reliance on `rehash` to pick up the rewritten `adigatortempfunc<k>.m` (`adigator.m:664-666`; §7.3) | octave |
| BG-10 | critical | solve sparsity pruned by *numeric* cancellation | matlab |
| BG-11 | critical | `loopbound`: a matched loop whose loop-variable *values* depend on the bound is padded wrongly | matlab |
| BG-12 | critical | Hessian of a counter-dependent inner loop prints `for c = 1:<vector>` | matlab |
| BG-13 | critical | `loopbound` at second order matches a counter-dependent inner loop to the bound | matlab |
| BG-14 | high | B36 residual: a verbatim numeric statement keeps a main input by name | matlab |
| BG-15 | high | B36 residual: a local alias of the trip count | matlab |
| BG-16 | high | `interp1` with a multi-column `Y` prints the index table in place of `xi`'s derivative | matlab |
| BG-17 | high | Hessian wrong for a sparse-patterned symbolic `6×6` `A` through `inv`/`mldivide` combined with `sum(sum(Z.^2))` | matlab |
| BG-18 | medium | `max`/`min` at ties emit the *sum* of all tied branches | matlab |
| BG-19 | medium | `nonzeros(x)` on an array without a static zero pattern returns `x(:)` | matlab |
| BG-20 | medium | known numeric inputs are read *by name* while their generation-time values are baked into sparsity and branch tables | matlab |
| BG-21 | medium/low | zero-propagation flags for `atan2`, `power`, `ldivide` are wrong or swapped | matlab |
| BG-22 | low | `x.^y` with an active exponent at `x == 0` emits `NaN` (`log(0).*0.^y.*dy` unguarded, `:673-674`; the `dx` term is guarded at `:328`) | matlab |
| BG-23 | low | generated `interp1`/`interp2` code extrapolates with the end polynomial where MATLAB returns `NaN` outside the breakpoints (`interp1.m:243-245` prints `ppval` … | matlab |
| BG-24 | high | the y-only arm sets `Xstr = []; Ystr = []` for `mod`/`rem` too, but their `getdzdy` needs both, so the file contains `z.dx = -floor(./).*…` — adigator reports success and the file does not … | - |
| BG-25 | critical | non-square `x/y` prints its three temporaries under one name and returns a silently wrong *value* through `adigator()` | matlab |
| BG-26 | medium | multi-output numeric branch uses undefined `NUMvar` (the variable is `NUMvars`) and overmaps the last output into every slot | - |
| BG-27 | medium | `error()` in a branch that also assigns: the compaction tests `BreakLocs` twice instead of `ErrorLocs`, leaving zeros used as `LASTOCC` indices | - |
| BG-28 | medium | `ADIGATORVARIABLESTORAGE.OVERAMP{OverLoc}` (field is `OVERMAP`) on the break-inside-loop-inside-`if` path whose exit variable is read after the loop and assigned in the other branch | - |
| BG-29 | medium | zero-argument subfunction call `P = mkp();` → `SpaceLocs(end) = 0` on an empty vector | - |
| BG-30 | medium | a *subfunction* loop over a declared `loopbound` name gets a literal header (`for … = 1:4`) while the main `assert(N <= Nmax)` passes at `n < Nmax` → runtime index error … | - |
| BG-31 | low | `… && ppknown` — assigned only in commented-out code (`:44, :62`); errors when both `xi` and `yi` carry values | - |
| BG-32 | low | a live `keyboard` (interactive debugger) on the rolled-loop size-change path for a non-row `x` with derivatives | - |
| BG-33 | low | a user subfunction call inside an `if`/`while` condition is printed raw and never routed through `CheckFunctionCall` (the comment at `:681-687` says such a call "would be an unrecorded … | - |
| BG-34 | low | element deletion `y(2) = []` fails loud in both MATLAB (sparse index past the shrunk size) and Octave, with a message naming nothing | - |
| BG-35 | low | `all` constant-folds `y.func.value = logical(x)` instead of `all(x,dim)` (size and value wrong when the operand has a known value; `any` is right) | - |
| BG-36 | low | `adigatorAssignOvermapScheme.m:290-322` zeroes break/continue/error branch counts *positionally* with absolute counts into a vector that starts at `Start`, so the removal is a no-op … | - |
| BG-37 | low | `:859` `for forLoci = 1:ForLoops` uses only `ForLoops(1)` as the colon bound (superset scanned; can only over-union) | - |
| BG-38 | low | `cross.m:174` allocates `fyLtemp = false(FMrow*FNcol)` (an `n×n` logical) where its siblings are `n×1`; benign, O(n²) memory | - |
| BG-39 | critical | `adigatorUncompressJac` applies the colour permutation in the wrong direction | matlab |
| BG-40 | low | `adigatorColor.m:54-56` additionally shortens the returned colour vector by the empty columns when called with two outputs, so `c(j)` is misaligned (an index error, fail-loud) for any … | matlab |
| BG-41 | critical | the reverse-mode value-tape slicer drops a one-line plain copy | matlab |
| BG-42 | medium | reverse-mode activity shortcut is unanchored | cloud,matlab |
| BG-43 | medium | the "Reconstruct with:" recipe silently omits a vector-valued `der_levels` | cloud,matlab |
| BG-44 | low | B12 is not fixed in `adigator.m` | cloud,matlab |
| BG-45 | low | reverse-mode index tables are named `RIndex%d`, so `prune_adigator_mat`'s `Index*`-keyed down-cast, range guard and keep-all rule never apply to them (embedded as `double`; an empty table … | matlab |
| BG-46 | low | the wrappers leak a path entry on an unresolvable function | cloud,matlab |
| BG-47 | low | the generation id does not cover the input specification (derivative-input sizes, aux values, `loopbound` maximum: `cadaGenerationStamp.m:50-59` hashes version + options + source only), so … | cloud |
| BG-48 | low | the ADR-0023 scan's deny-list is narrower than its claim | matlab |
| BG-49 | low | reverse mode rejects any active statement with a negative scalar constant because `cadamatprint` parenthesises it (`(-2)`) and the reverse atom regexp has no parenthesised form … | matlab |
| BG-50 | info | The deprecated `GenFiles4*` wrappers still print `% Contact: mweinstein@ufl.edu` (`adigatorGenFiles4Ipopt.m:274-276` and siblings), the upstream routing #200 removed everywhere else (DD-34) | cloud |
| BG-51 | medium | `xvec` is undefined on the path where the constant operand is an inline literal: `cross(X, [1 4;2 5;3 7])` with `X = [x(1:3), x(4:6)]` fails at generation with … | matlab |
| DD-01 | - | `ULintTest` — `checkcode` … | - |
| DD-02 | - | `SReleaseMatrixTest` — full suite on {R2022a, latest}, "nightly only" | - |
| DD-03 | - | golden-file tests with checked-in fixture inputs and expected outputs | - |
| DD-04 | - | `adigatorUncompressJac`/`adigatorColor` round-trip "inside TS-I-01" | - |
| DD-05 | - | `atan2`, `power`; `repmat`, `mldivide` | - |
| DD-06 | - | fixtures incl. "one with a rolled loop" and "an integer-valued constant matrix" | - |
| DD-07 | - | input shapes incl. `1×n` | - |
| DD-08 | - | "randomized structs … n-d arrays" | - |
| DD-09 | - | classic `slim_embed` is "a byte-for-byte no-op" | - |
| DD-10 | - | the `_location` strip proves the slice fired; csc "FD/analytic agreement" | - |
| DD-11 | - | `adigator.m:242` / `:775` | - |
| DD-12 | - | registry of all tests | - |
| DD-13 | - | stale step names/ranges; "commits the rebuilt PDF back to the PR branch" | - |
| DD-14 | - | bugs B1–B22 / B1–B13 | - |
| DD-15 | - | "64 classdefs"; "16 tests across 5 classes" | - |
| DD-16 | - | "runs in the PR gate" | - |
| DD-17 | - | `DESIGN.md:103` (C-1) still binds "the pattern exported via the `der_output`/`*Locs` family — the default for `k ≥ 3`"; ADR-0030 removed `*Locs` and its revisit clause says higher-order … | - |
| DD-18 | - | `REVIEW_CONTEXT.md:59` principle 4: "`'l'`/`'i'` files must pass MATLAB Coder (`lib` target)" — ADR-0033/REQ-T-10 moved the bar to strict Embedded Coder (`adigatorCoderConfig`, no dynamic … | - |
| DD-19 | - | Ranges and paths: `CLAUDE.md:23` "B1–B22", `REVIEW_CONTEXT.md:7` "B1–B26" (actual B40); `CLAUDE.md:22,55` and `DISCIPLINE_ADOPTION.md:32` "C-1..C-5" (DESIGN defines C-6 … | - |
| DD-20 | - | The `'l'` embed mode | matlab |
| DD-21 | - | `ANALYSIS.md:1307` B23 names its pin as `IOutputModesTest/hessianNonzerosMatrixOfScalar`; the method was renamed `hessianCscMatrixOfScalar` in the R31 migration | - |
| DD-22 | - | ROADMAP statuses that describe as outstanding work that is in the tree: R14/R9 "the typed expression-tree generator and an FD-Hessian value oracle remain" — `mcGenExprTree.m` is a default … | - |
| DD-23 | - | `CHANGELOG.md:187` (user-facing): "the 47 generated artifacts committed under `examples/` still carry the old contact until they are regenerated" — zero generated files are tracked under … | coder |
| DD-24 | - | Principle-8 hits in user-facing docs: `docs/README.md:148` "(C-6 order)"; `bench/SHOWCASE.md:299` "(issue #192, ADR-0030)". The guide's only hit is inside a LaTeX comment | - |
| DD-25 | - | User guide: `ADiGatorUserGuide.tex:377` shows `adigatorFiles4Fmincon(setup)` under the `adigatorGenFiles4Fsolve` subsection and `:449` `adigatorGenFiles4Fmincon(setup)` under … | - |
| DD-26 | - | `tests/montecarlo/README.md` omits `mcGenExprTree`, `mcGenParamDelivery`, `oracleFiniteDiff`, `oracleCodegenEquivalence`, `oracleParamDeliveryInvariance`, `oracleDerOutputInvariance` from … | - |
| DD-27 | - | `tests/fixtures/guide/lse_cost_RGrd.m` carries no #200 header; the reverse generator never emits one (TF-34), so the ADR-0025 guide fragment shows a header format different from every other … | - |
| DD-28 | medium | reword `CI_PLAN.md` §0, `DESIGN.md` §Constraints and `docs/README.md` to the measured Octave boundary (§7.4) | cloud |
| DD-29 | - | `CI_PLAN.md:465-467, :485`: "nightly jobs … informational for the first month, then promoted to required-on-master once stable" / Phase 3 exit "one week of green nightlies; promote". … | - |
| DD-30 | - | ADR-0032's "ratchet now, raise later … as the #38/#103 oracles land" fired on 2026-07-30 (`mcGenExprTree` + the FD-Hessian oracle, `bef32e5`; `IStructArrayNamingTest` `0dbfcdf`; several … | - |
| DD-31 | - | ADR-0028 `:84-91` still records the shared loop-guard shape constant as "designed on #181 §4, deferred"; `util/adigatorLoopboundGuard.m` landed 2026-07-12 (#191) and is consumed by all five … | - |
| DD-32 | - | `REQ-T-10` (`CI_PLAN.md:82`) requires every `'l'`/`'i'` derivative to ERT-codegen, with acceptance "every (DerType × `'l'`/`'i'` × `slim_embed`) cell exercised by the showcase"; ADR-0021 … | - |
| DD-33 | - | B13 ("`Gfid` never closed in `adigatorGenHesFile`") is mapped to TS-U-08 (`CI_PLAN.md:119, :225`), but `UCoreErrorHygieneTest` calls only `adigatorGenJacFile` … | - |
| DD-34 | - | `CHANGELOG.md:100-102` "Every generated file now opens with a `GENERATED FILE` line …" is an over-claim (TF-34): only `adigator.m`, `adigatorGenJacFile` and `adigatorGenHesFile` call … | - |
| DD-35 | - | `ISymbolicIndexTest.ifGuardedWhileCounterErrorsSafely` (`:134-136`) says a future fix "is caught by this test starting to change"; its only assertion is `verifyTrue(threw)`, which an … | - |
| DD-36 | - | `docs/decisions/README.md:134-135` lists ADR-0022 as plain Accepted with the removed surface in its one-liner, while ADR-0022 itself (`:12`) is "partially superseded by ADR-0030" and the … | - |
| DD-37 | - | R24 blast radius unrecorded: `IEmbedSlimTest`, `IEmbedSlimRolledTest` and `ILevelSelectTest.composesWithEmbedMode` use `'l'` as a *working* fixture mode (TS-I-05/06/09 rows say … | - |
| DD-38 | - | R6: evidence "in" since 2026-07-10, re-measured 07-30, HOW-analysed 08-02, status "maintainer call" with no decision or re-deferral date; the engine-v2 analysis itself says the padding … | - |
| DD-39 | - | `DESIGN.md:39-41` module table: `GenFiles4*` listed without the ADR-0037 deprecation, `adigatorGenRevGradFile`/`adigatorGenJtVFile`/ `adigatorCoderConfig` absent, tests described as … | - |
| DD-40 | - | `CHANGELOG.md:354-356` describes the B19 residual as "a narrow N-D-indexing edge case"; `ANALYSIS.md:343-367, :1303` describes an `if`-guarded `while`-counter index over-approximation on a … | - |
| HY-01 | medium | error identifiers | cloud |
| HY-02 | low | file modes | cloud |
| HY-03 | info | line endings | - |
| HY-04 | info | proprietary-content guards work | - |
| HY-05 | medium | generated-code licence and runtime dependence (#239, #249) | cloud |
| HY-06 | low | release machinery | - |
| HY-07 | low | version/branch state | - |
| HY-08 | low | Octave-visible hygiene | cloud |
| HY-09 | info | workflow security | - |
| OC-00 | - | Both licence-free offline cores pass exactly as their headers prescribe: `prune_shrink_offline_checks` → `PASS (36 checks)`; `gap_interproc_equiv` → … | - |
| OC-01 | medium | "Octave is not viable today" is an unmeasured claim and is measured false for the transformation core (§7.3) | octave |
| OC-05 | - | a recursive identifier-scan walker (`which` → keep `.m` files outside `OCTAVE_HOME` and the engine root) | - |
| OC-06 | - | `©`/`ç` emitted as `char(169)`/`char(231)` by `cadaPrintGeneratedHeader.m:71-72`; folded into HY-08 | octave |
| OC-10 | low | Octave runs `arguments` blocks with validation and defaults skipped, and `"a" + "b"` is numeric addition: six such sites in `embedding/` (§7.2) | octave |
| PB-01 | - | ROADMAP R13(4) records "defer the paper" (issue #18, 2026-06-24) with the stated condition "once R10–R12 settle" and the go/no-go chained to the R6 gate | - |
| PB-02 | - | Real but narrow. CppADCodeGen advertises statically allocatable derivative code for hard real-time loops; CasADi/acados/ACADO generate self-contained C from expression graphs … | coder |
| PB-03 | - | The most AD-specific novelty found. Searches return only Coder's bounded variable-size data and horizon-fixed MPC generators; no AD tool found that emits a size-generic derivative whose … | matlab |
| PB-04 | - | A design choice rather than a new AD mode (Tapenade/ADIFOR, CppADCodeGen, CasADi, Enzyme all do adjoint source generation); the angle is "a ~30-shape generated dialect as the tape, sizes … | - |
| PB-05 | - | Not standalone: CSC is CasADi's long-standing convention (ADR-0030 does not cite it); the "~2× metadata" win is measured against the fork's own removed v1 surface | - |
| PB-06 | - | Builds on nablaFuzz (ICSE 2023: differential testing of forward/reverse/numeric AD, 173 bugs) and metamorphic-testing prior art; the fork's distinct additions are the *embeddability* … | matlab |
| PB-07 | - | A credible experience report with a dense public dataset: 417 commits, 179 pull-request merges recorded in that history (`git log --format=%s a4e24bc`: 136 squash subjects ending in `(#n)` … | cloud |
| PB-08 | - | The v2.0 cut is procedurally fragile: `[Unreleased]` still carries the framing blockquote and HTML comment that `extract` publishes verbatim (#233, open at `a4e24bc`); `Contents.m`'s … | - |
| PB-09 | - | No release checklist exists: the recipe in `CONTRIBUTING.md` never runs `tests/ci_ert.m` or the Monte-Carlo campaign that ADR-0007 and the same document call "release-checklist runs", and … | - |
| PB-10 | - | Product-level blockers: the output licence is undefined (#239); embed-mode output depends on the GPL library at runtime through `interp2` (#249, one overload — HY-05); the ADR-0013 upstream … | - |
| PB-11 | - | Citation infrastructure is absent: no `CITATION.cff`, `codemeta` or `.zenodo.json`; the README cites only upstream's 2017 TOMS paper; a Zenodo DOI needs a GitHub release; the repository has … | - |
| PB-12 | - | Release-archive hygiene: the curated distribution ships `docs/README.md` and `docs/DESIGN.md` with 10 and 16 links into stripped folders, strips `bench/SHOWCASE.md` that the README sends … | - |
| PB-13 | info | the user guide is independently publishable but carries no licence statement of its own (§8.3) | cloud |
| PB-14 | info | `bench/SHOWCASE.md` is publishable in *form*, not yet in substance: one Windows host, host objects, `n ≤ 64`, single-sample timings (§8.3) | coder |
| PB-15 | info | the evidence-discipline section as a short experience report; already proposed to the seed as #53 (§8.3) | cloud |
| PB-16 | info | strongest scientific venue for the correctness work: an ACM TOMS "Remark on Algorithm 984" once §4.1 is reproduced, fixed and pinned (§8.2) | matlab |
| PB-17 | info | a software paper (JOSS or SoftwareX) fits structurally but is blocked by the missing tag/DOI, the absent `paper.md`, the open output-licence question (#239) and CI claims a reviewer would find false (TF-01) (§8.2) | cloud |
| PB-18 | info | an AD-workshop talk: EuroAD 29 (September 2026) has passed; the next slot is EuroAD 30 (2027) (§8.2) | - |
| PB-19 | info | the Monte-Carlo harness as a reusable AD-testing *pattern* (case contract, relation oracles) (§8.3) | matlab |
| PB-20 | info | paper-grade evidence inventory: E1–E6 harnesses, the 150/150 campaign and the CasADi values exist only as prose (§8.2) | coder |
| PB-21 | info | the domain case-study paper has inputs in the tree but no closed-loop solver, target timing or end-to-end (N,K) demonstration (§8.2) | coder |
## Appendix B — How the measurements were taken

Reproducible from a clone of `a4e24bc` on a Linux box with `git`, `python3`,
GNU Octave 8.4 and read access to the GitHub Actions API.

**Workflow-run history (TF-01).** GitHub REST, `GET
/repos/pdlourenco/adigator-embedded/actions/workflows/extended.yml/runs`
(2026-10-04): `total_count = 15`; `event`/`head_branch` per run as quoted in
§2.1. `…/workflows/ci.yml/runs?branch=master`: 157 runs, latest 31162145852
on `a4e24bc`. Default branch: `git remote show origin | grep 'HEAD branch'`.
Branch distance: `git log --oneline origin/embedded..origin/master | wc -l`
(270) and the reverse (0).

**Test inventory.** Every `tests/**/*.m` read in full; assertion kinds
classified per method (multi-label); tolerances by `grep -oE "'(Abs|Rel)Tol',
*[0-9.e-]+"` then de-duplicated per site; `assume*`/`KnownIssue` sites listed
with their predicate. Tolerance token census (whole suite): `AbsTol 1e-12`
×100, `AbsTol 0` ×72, `RelTol 1e-12` ×51, `AbsTol 1e-5` ×22, `AbsTol 1e-14`
×19, `RelTol 1e-5` ×19, `AbsTol 1e-10` ×11, `AbsTol 1e-4` ×9, `RelTol 1e-4`
×7, `AbsTol 1e-9` ×5, `AbsTol 1e-6` ×5, `AbsTol 1e-13` ×3, `RelTol 1e-13` ×3,
`RelTol 1e-6` ×2, `RelTol 1e-14` ×2, `RelTol 1e-10` ×2, `RelTol 5e-3` ×1,
`RelTol 1e-9` ×1, `AbsTol 1e-3` ×1.

**Test-history census.** `git rev-parse --is-shallow-repository` → `false`
(after `git fetch --unshallow`); `git log --format='%h %ad %s' --date=short
-- tests/ .github/ .githooks/` (153 commits); `git log -p --follow` per file;
hunks containing a removed `verify*`/`assert*` line, a tolerance token, or an
added `assume*`/`KnownIssue` read line by line (171 of 301). Commit bodies
quoted verbatim where cited.

**Doc-claims inventory.** For every `TS-*` row: `ls tests/*/` for the class,
`grep -n` for each method or key phrase the row names. For every `Bnn` in
§1.5: `git grep -n <pin method>`. ADR clauses: `git grep -niE
'revisit|re-evaluate|reconsider|trigger|until|once .* lands' -- docs/decisions/`
(by the word, per CONTRIBUTING). Ranges: `grep -oE '\bB[0-9]{1,2}\b'
docs/analyses/ANALYSIS.md | sort -uV | tail -1` → B40.

**Fixture-string coverage scans (§3).** Python over `tests/**/*.m`,
`examples/**/*.m`, `bench/**/*.m`: comment lines stripped, string literals
that are fixture bodies (`writeFixture`, `writeFcn`, `mcCase('body', …)`,
`fprintf(fid, …)` payloads) extracted, then op names searched inside them
and every hit read to exclude harness/oracle uses. Negative claims enumerate
the forms searched (`atan2(`, `mod(`, `rem(`, `.\`, `ldivide(`, `max(`/`min(`
with two arguments, `interp1(`…).

**Error-identifier census (HY-01, CG-16).** Python over `adigator*.m`,
`lib/**`, `util/**`, `embedding/**`: `error(` calls counted after stripping
trailing comments; "has id" = first argument matches `'[A-Za-z]\w*:[\w:]+'`
or an identifier variable. 509 total, 110 with, 399 without; the per-file
counts in HY-01. The 68 distinct `adigator:*`-style ids were then each
`grep`'d over `tests/`.

**`.gitignore` guards (HY-04).** `git check-ignore -v <path>` for the seven
representative paths listed.

**Octave (§7).** All commands ran with `octave --no-gui --quiet --eval "…"`
from the repository root on a *scratch copy* of `adigator*.m`, `lib/`,
`util/`, `embedding/` (no tracked file was modified):

- offline cores: `addpath(fullfile(pwd,'tests','offline')); prune_shrink_offline_checks` / `… gap_interproc_equiv`;
- parse census: `__parse_file__(<abs path>)` over 375 of the 377 tracked `.m` files (all but the root `Contents.m` and `startupadigator.m`), with positive (`y = x +* 2` → parse error) and negative (a `disp` side effect never printed) controls;
- construct probes: ~100 builtins/constructs called directly (`string`, `strings`, `compose`, `readlines`, `writelines`, `contains`, `mtree`, `onCleanup`, `containers.Map`, `inputParser`, `"a" + "b"` → 195, an `arguments` block with a default → `'x' undefined`);
- engine: the four patches of §7.3 applied to the scratch copy, plus shims `verLessThan`, `matlab.codetools.requiredFilesAndProducts` (recursive identifier walker) and `coder.const`; transformations of `tf1` (scalar/vector Jacobian; re-run directly: `adigator('tf1',{x},'tf1_dx_mine', adigatorOptions('overwrite',1,'echo',0))` on `y = sin(x).*x + x(1)*x(2)` at `[0.3;1.2;−0.7]` → nonzeros `1.7821 1.2 1.2 0.3 1.6669 0.3 −1.1796` at locations `(1,1)(2,1)(3,1)(1,2)(2,2)(3,2)(3,3)`, checked by hand), `tf2` (loop + `if`), `tf3` (Hessian via `adigatorGenHesFile`), `tf4` (struct input), `gapfun` (interprocedural; `diff` of the generated text against `tests/fixtures/gen_dialect/slim0/gapfun_Grd.m` after normalising header/data-load lines → only `f.dz_size = 2;` and `f.dz_location = Gator1Data.Index7;`), `tests/legacy/test_unarymath_rules.m` (0 violations after the `rehash` patch; 664 before, with the stale-function symptom described in BG-09), `examples/jacobians/arrowhead` at `N = 100`;
- bug-candidate re-runs (§4): BG-02, BG-06 and BG-11 regenerated and evaluated on the scratch engine copy with the inputs and outputs quoted in their entries (`sum(X,2)` on a `3×3` input with one variable touching a non-monotone entry set; `[R*v; 1]` with `R` the rotation block; `for k = N:-1:1` under `loopbound 'N'`, `Nmax = 4`, `n ∈ {4,3,2}`); BG-39 on the unmodified `util/adigatorUncompressJac.m` and `util/adigatorColor.m` with the generator below (seed 7, 400 draws, 236 without an empty column; shipped code wrong in 122, proposed fix in 0);
- polydatafit band (TF-05): the example's `fit.m` at `m = 8`, `n = 100`, seeds 1–3; analytic normal-equation Jacobian three ways vs central FD at `h ∈ {1e-6, 1e-5}` and the test's two bands.

The BG-39 generator (Octave 8.4; `rand('seed',7)` selects Octave's legacy
generator, so the exact counts are specific to it; the wrong/right split is the
finding):

```matlab
addpath('util'); rand('seed',7); nbad = 0; nfix = 0; ntr = 0;
for t = 1:400
  m = 2+floor(rand*6); n = 2+floor(rand*6);
  Jpat = sparse(rand(m,n) < 0.4);
  if any(~any(Jpat,1)), continue; end      % adigatorColor's 2-output c drops empty columns
  ntr = ntr+1;
  Jval = Jpat .* sparse(1+floor(rand(m,n)*50));
  [c,S] = adigatorColor(Jpat);  JSnz = nonzeros(Jval*S);
  J = adigatorUncompressJac(Jpat,c,JSnz);
  if ~isequal(full(J),full(Jval)), nbad = nbad+1; end
  [i,j] = find(Jpat); order = nonzeros(sparse(i,c(j),1:length(i),m,n));
  Jfix = sparse(i(order),j(order),JSnz,m,n);
  if ~isequal(full(Jfix),full(Jval)), nfix = nfix+1; end
end
printf('%d trials; shipped wrong in %d; fix wrong in %d\n', ntr, nbad, nfix);
```

**`mod` guard (BG-01).** Read `lib/@cada/cadabinaryarraymath.m:405-425` and
`:580-600` at HEAD; `git blame -L 411,417` → `5855f6a` (upstream import);
Octave emulation of the literal emitted text for `x = [2.3;5.7;−1.2;9.9]`,
`y = 1.7`: rule `−floor(x./y).*dy` = `[−1;−3;1;−5]` matches central FD to
`5e-9`; the emitted scalar-`y` form yields `[0;0;0;0]`.

**Overdetermined solve (BG-04).** Read `lib/@cada/mldivide.m:215-228` (square
branch) and `:230-384` (tall branch) at HEAD: the tall branch's only derivative
arm is the `x`-active `if`, with no `y`-only arm. The Octave run quoted in the
entry (`A = [1 2;3 4;1 1]`, `b = [x1;x2;3]` → `J = zeros(2,2)`) was the
structural finder's; the orchestrating session re-read the source only.

**Logical zero masks (BG-05).** Read `lib/@cada/cadabinarylogical.m:100-120`
at HEAD; `git blame -L 108,112` → `5855f6a` (upstream import); the `elseif`
builds `ytemp` from `x.func.zerolocs`. Source read only; the Octave runs quoted
in the entry were the rules finder's.

**Literature positioning (§8).** Web searches run by the publishability pass
(summaries read, not full papers): "CppADCodeGen static memory allocation hard
real-time", "CasADi generated C code no dynamic memory allocation", "ACADO code
generation sensitivities", "static sparsity automatic differentiation code
generation microcontroller MPC", "derivative code generation variable problem
size upper bound one generated function runtime dimension", "source
transformation AD fixed-size loops static memory bounded stack", "automatic
differentiation tool verification random testing oracle fuzzing",
"differential testing automatic differentiation tools", "metamorphic testing
automatic differentiation", "Tapenade/Enzyme/CppADCodeGen adjoint source
generation", "case study LLM coding agents scientific software maintenance
architecture decision records", the JOSS submission criteria, the ACM TOMS
algorithms policy (Remarks), and the EuroAD workshop schedule. Upstream
repository state read through the GitHub API (last issue 2022-07-31).
