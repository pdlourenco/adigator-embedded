# ADR-0014 — Adopt MATLAB Test codegen-equivalence testing into the V&V suite

## Status

Accepted — 2026-06-24. **Amended 2026-07-01** (#80 R20c): the campaign oracle
and the re-based `SCodegenTest` are **born ERT** — the build targets Embedded
Coder (`coder.config('lib','ecoder',true)`), not plain MATLAB Coder `lib` — so
the whole codegen-equivalence surface exercises the strict target per REQ-T-10.
(`SCodegenTest`'s ERT lib build landed in PR #92; see Decision 1 / 2.)

## Context

Issue [#64](https://github.com/pdlourenco/adigator-embedded/issues/64) (an
external suggestion) proposes using **MATLAB Test**'s code-generation
equivalence testing — `matlabtest.coder.TestCase`, with the
**Build → Execute → Qualify** workflow (`build` / `execute` /
`verifyExecutionMatchesMATLAB`) and the
`matlabtest.coder.plugins.GeneratedCodeCoveragePlugin` for coverage on the
*generated C* — to test that the C generated from our embedded-mode derivative
files is equivalent to the MATLAB source, with code coverage on the generated
code as a bonus.

Two facts make this a natural fit rather than a new direction:

1. **It is the supported version of code we already hand-roll.**
   `tests/system/SCodegenTest.m` (TS-S-02) already does the Build→Execute→Qualify
   dance manually: `codegen('gapfun_Grd', …)` → run `gapfun_Grd_mex` →
   `verifyEqual(Gx, Gm)`. `matlabtest.coder.TestCase` is exactly that pattern
   behind a supported API, plus generated-C coverage.

2. **It closes a real gap in the #38 Monte-Carlo campaign.** Today the campaign's
   cross-mode oracle (`tests/montecarlo/oracles/oracleCrossMode.m`) compares
   `'c'/'l'/'i'` **all interpreted in MATLAB** — the `'l'/'i'` path runs the
   wrapper (containing `coder.load`/`coder.const`) *in the interpreter* via
   `mcEval`; it never invokes Coder. So across the entire randomized battery
   nothing is ever compiled. The only place generated C is exercised is the
   single `pipg` fixture in TS-S-02. A codegen-equivalence oracle adds
   **compiled-C ≡ MATLAB over randomized functions** — the embedded-target trust
   #38 exists to build.

The constraints that shape the decision:

- **New product dependency.** MATLAB Test is a separate licensed product *on top
  of* MATLAB Coder. This is a §4 external-dependency decision.
- **Release floor.** The MATLAB Test codegen-equivalence feature dates to
  ~R2023a, above this repo's R2022a floor (ADR-0003). The new checks cannot run
  on the floor leg.
- **Per-build cost.** Each `codegen` build is seconds-to-minutes, so a
  per-random-case C build cannot run on every seed like the tolerance-free
  oracles do.

Surfaced per CLAUDE.md §4 with options and a recommendation; the maintainer
approved adopting it into #38 (issue #64, 2026-06-24, *"both"* — re-base
`SCodegenTest` **and** add the campaign oracle).

## Decision

Adopt MATLAB Test codegen-equivalence testing in two places, both **non-gating**
and **skip-clean** wherever MATLAB Test, MATLAB Coder, or R2023a+ is absent:

1. **Re-base the deterministic codegen test (TS-S-02 / `SCodegenTest`)** on
   `matlabtest.coder.TestCase` (Build→Execute→`verifyExecutionMatchesMATLAB`)
   where MATLAB Test is licensed, **keeping the hand-rolled `codegen` +
   `verifyEqual` path as the fallback** for Coder-only / R2022a runners. Gains:
   a supported API and generated-C coverage on the `pipg` fixture. This is the
   lowest-risk adoption and de-risks the API before the campaign oracle.

2. **Add a campaign oracle `oracleCodegenEquivalence(c)`** to
   `tests/montecarlo/oracles/`, with the *same* return contract
   (`struct('name','pass','skipped','message')`) and the *same* skip-clean
   discipline `oracleCrossMode` already uses for `coder.*`. Per case: generate
   the `'i'` (or `'l'`) wrapper for case `c`, then Build→Execute→
   `verifyExecutionMatchesMATLAB` over `c.x0` plus a few random inputs. **Born
   ERT** (amended 2026-07-01, #80 R20c / REQ-T-10): the oracle's build targets
   **Embedded Coder** (`coder.config('lib','ecoder',true)` — configure
   `matlabtest.coder.TestCase` with the `ecoder` config, or pass it to the
   fallback `codegen`) from the start, so the Monte-Carlo campaign compiles
   through the strict ERT target, never plain `lib` — which tolerates ERT-illegal
   struct-field patterns and was masking real embedded-codegen gaps. The skip
   is gated on `license('test','MATLAB_Test')` (and the R2023a+ check); it is
   wired into `mcCampaign` as an opt-in oracle.

   - **Sampling, not per-seed.** Because each build is expensive, the oracle runs
     on a *sampled* subset (every Nth case or a small dedicated `codegenEquiv`
     subset), never on every random case. The sampling stride is a tunable
     campaign parameter; the default keeps a full `mcCampaign` run within the
     existing release-checklist time budget.
   - **Coverage** via `GeneratedCodeCoveragePlugin` feeds the existing
     `mcReport` as a release-checklist artifact — *complementary* to the
     Cobertura coverage, which is on the **MATLAB source** (`embedding/` +
     `util/`); the plugin answers "does the random battery exercise the breadth
     of generated C the emitter emits?".

Both surfaces stay **non-gating**: they extend the opt-in / release-checklist
campaign (TS-S-04) and the license-gated nightly codegen job (TS-S-02), and skip
cleanly on the PR gate, the R2022a floor leg, and Coder-only machines, so the
new dependency adds *reach* on a fully-provisioned machine without raising the
bar anywhere it is absent.

Lands as: roadmap row R15 (a sub-item of #38 / R14's campaign substrate);
`CI_PLAN.md` REQ-T-05 / REQ-T-09 / TS-S-02 / TS-S-04 wording updates. The oracle
and `SCodegenTest` code itself are authored/verified in a MATLAB-capable session
(they cannot be run here).

## Consequences

- **Easier:** the embedded-codegen equivalence claim is verified over the whole
  randomized battery rather than one fixture; TS-S-02 sheds hand-rolled
  build/compare plumbing for a supported API; generated-C coverage becomes
  available for the release checklist.
- **Harder / constrained:** a full campaign run now wants a machine with MATLAB
  Test **and** Coder on R2023a+; the oracle is sampled, so it gives breadth over
  many functions but not every seed; the new dependency must be documented in
  the campaign README and the CI license story.
- **Revisit if:** MATLAB Test becomes unavailable in the maintainer's
  environment (fall back to the retained hand-rolled TS-S-02 path and drop the
  oracle to skip); or the per-build cost proves cheap enough to widen the
  sampling; or a future fully-C-emitting path (vs. MEX) changes what "equivalent"
  should compare.

## Alternatives considered

- **Keep the hand-rolled codegen test only; do not adopt MATLAB Test.** Zero new
  dependency, but leaves the randomized campaign with *no* compiled-C check
  (cross-mode stays interpreter-only) and forgoes generated-C coverage. Rejected:
  the campaign's whole point is scale, and compiled equivalence at scale is
  exactly the embedded-target assurance the hand-rolled single-fixture test
  cannot give.
- **Re-base `SCodegenTest` only (no campaign oracle).** Gains the supported API
  and fixture coverage but not the #38 adoption the issue actually asks for.
  Folded in as step 1 rather than chosen alone.
- **Run the codegen-equivalence oracle on every random case.** Maximal coverage,
  but per-build cost makes a campaign of any size impractical and would push the
  release checklist out of its time budget. Rejected in favour of sampling.
- **Make the new checks gating (PR or required-on-master).** Rejected on the same
  grounds ADR-0007 made the whole campaign non-gating: license-gated, slow, and
  above the R2022a floor; a green gate cannot depend on a product the PR runners
  lack.
