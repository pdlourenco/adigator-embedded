# Monte-Carlo V&V harness

Randomized robustness battery for the derivative generators (issue #38,
[ADR-0007](../../docs/decisions/ADR-0007-montecarlo-vv.md), `CI_PLAN.md`
REQ-T-09 / TS-S-04). **Opt-in and non-gating**: this folder is selected by the
*extended* (per-merge) workflow and run locally on demand; the PR gate
(`ci.yml`) and the `ci_local` sweep deliberately do not select it.

## Run it locally

```matlab
addpath(genpath('tests'));            % or just tests/montecarlo + helpers
report = mcCampaign('nIters', 10000, 'seed', 0);
```

Each iteration `i` is seeded from `seed+i`, so a failure replays exactly.
Failures are shrunk (`mcShrink`) to a minimal reproducer and promoted
(`mcPromote`) into `regressions/`, where `MCRegressionTest` re-checks them
deterministically.

## Pieces

| Layer | Files |
|-------|-------|
| Driver / contract | `mcCampaign`, `mcCase`, `mcRunCase`, `mcReport`, `mcCoverage` |
| Generators (positive) | `generators/mcGen{Affine,Quadratic,ShapeFuzz,Elementwise,ScalarSum}` |
| Generators (negative) | `generators/mcGenNegative` |
| Oracles (tolerance-free first) | `oracles/oracle{KnownDeriv,SparsitySuperset,CrossMode,HessSymmetry,FwdRev}` |
| Oracle (robustness) | `oracles/oracleHygiene` |
| Failure → fixture | `mcShrink`, `mcPromote`, `regressions/` |
| Smoke (per-merge) | `MCSmokeTest` |

## Oracles

- **knownDeriv** — exact value check vs the closed form the generator emits
  (affine → `J = A`; quadratic → gradient `Qx+c`, Hessian `Q`; elementwise →
  diagonal `diag(a.*g'(a.*x+b))`, with each `g'` mirroring `cadaunarymath`'s
  emitted form). Tight tolerance (1e-9), not FD.
- **sparsitySuperset** — `find(|D|>0) ⊆ find(Structure)` (REQ-T-03).
- **crossMode** — `embed_mode` `c`/`l`/`i` static invariants (REQ-T-04) plus
  bit-identical results; the `l`/`i` numeric check needs MATLAB Coder and
  skips cleanly otherwise.
- **hessSymmetry** — `H == H'` for scalar Hessian cases (skips otherwise).
- **fwdRev** — for scalar costs, the reverse-mode gradient
  (`adigatorGenRevGradFile`) equals the forward `Grd` wrapper and the closed
  form. Skips non-scalar cases, and skips (does not fail) when reverse mode
  declines a construct at generation time (an `adigator:revgrad:*` /
  `adigator:fwdtape:*` rejection) — a tool-scope limit is not a derivative bug.
- **hygiene** — for *negative* cases (malformed fixtures from `mcGenNegative`,
  `tags.negative = true`), generation must error AND leave the session
  hygienic: no stray transformation globals, the path restored, no open file
  handles (REQ-T-07, pins the B16 `adigator.m` onCleanup fix). Run it as its
  own campaign — negative cases must never be fed to the value oracles:
  `mcCampaign('generators',{'mcGenNegative'},'oracles',{'oracleHygiene'})`.

The `mcGenElementwise` / `mcGenScalarSum` rule-table generators exercise
`cadaunarymath` (and the reverse adjoint rules) under randomization. The
finite-difference oracle and the typed expression-tree generator are later
phases (ROADMAP R9 C–D).
