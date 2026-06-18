# ADR-0004 — PR CI is a single MATLAB install with sequential steps

## Status

Accepted — 2026-06-18. Back-filled from [`../CI_PLAN.md`](../CI_PLAN.md) §3.1.

## Context

CI runs on GitHub Actions with `matlab-actions/setup-matlab`. Every GitHub
Actions *job* runs on a fresh runner and pays the MATLAB install/license
handshake again; *steps* within one job share a single install. MATLAB
installation is the dominant fixed cost of every job.

The intuitive layout — one job per check (lint, unit, integration) so they run
in parallel — would pay the install cost three times for checks that together
take less time than a single install.

## Decision

The PR pipeline is a **single job** with sequential steps (lint first, fail-fast,
then unit, then integration) on one MATLAB install. Parallel jobs are reserved
for the nightly workflow, split only along axes that genuinely need separate
installs (different MATLAB releases, or a product set such as Coder /
Optimization Toolbox).

## Consequences

- The PR gate pays the MATLAB install once; `cache: true` further amortizes it
  across runs of the same release.
- Steps are ordered by leverage: cheap lint fails before the expensive test
  steps run.
- **Revisit** if test wall-time grows enough that parallelism across multiple
  installs would beat the install cost, or if self-hosted runners with a
  persistent install change the cost model.

## Alternatives considered

- **One job per check (parallel).** Rejected — triples the install cost (the
  dominant cost) for checks that are individually short.
- **A matrix over OSes for the PR gate.** Rejected — the toolbox is OS-agnostic
  MATLAB code and historical `filesep` issues are covered by tests running
  through `fullfile`; a single Linux runner suffices until an OS-specific issue
  appears (`CI_PLAN.md` §3.5).
