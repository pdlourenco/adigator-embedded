# CLAUDE.md — Agent operating rules

Binding rules for Claude (and any other coding agent) working on
ADiGator-embedded. The workflow rules below are **active from day one**; the
contract gate in §3 binds as soon as a change touches a surface in
[`docs/DESIGN.md`](docs/DESIGN.md) §Contracts (which is now — those contracts
already exist). This file is a short index; the linked documents are
authoritative.

Source-of-truth documents:

- [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) — contributor mechanics:
  pre-push review, ADR policy, commit conventions, PR lifecycle, the
  two-session workflow.
- [`docs/CI_PLAN.md`](docs/CI_PLAN.md) — CI strategy, requirements, test
  traceability (the V-model left/right legs).
- [`docs/DESIGN.md`](docs/DESIGN.md) — architecture rationale **and** the
  binding output Contracts (C-1..C-5).
- [`docs/ANALYSIS.md`](docs/ANALYSIS.md) — known bugs B1–B14 and optimization /
  reverse-mode analysis.
- [`docs/REVIEW_CONTEXT.md`](docs/REVIEW_CONTEXT.md) — principles and red flags
  to review against.
- [`adigatorDerivativeConventions.m`](adigatorDerivativeConventions.m) — the
  authoritative derivative-shape conventions.

## 1. Follow `docs/CONTRIBUTING.md`

It is authoritative for the pre-push review, ADR conventions, commit/branch
naming, the PR lifecycle, and the two-session workflow. Read it before opening a
PR. Deviations need an explicit note in the PR description and, if structural,
an ADR.

## 2. Pre-push self-review is mandatory

Before **every** `git push` on a PR branch, launch a reviewer subagent on the
local diff using `docs/CONTRIBUTING.md` §"Pre-push self-review", seeded with
`docs/REVIEW_CONTEXT.md` plus `docs/DESIGN.md` / `docs/ANALYSIS.md`. Act on
findings before pushing; record the outcome in the PR description. The narrow
exceptions (one-line typo, formatting-only, pure revert) are listed there.

## 3. Implementation is bound to the derivative contracts

The binding cross-surface conventions are in [`docs/DESIGN.md`](docs/DESIGN.md)
§Contracts (C-1..C-5) and [`adigatorDerivativeConventions.m`](adigatorDerivativeConventions.m):
derivative output shapes, the `y.dX` generated-file interface, the
`Index*`-vs-`Data*` Gator-data layout, the embed-mode invariants, and the
`norm` policy. Implementations must match them and they must match the
implementations. Concretely:

- To change a contract, update `docs/DESIGN.md` §Contracts (and
  `adigatorDerivativeConventions.m` where the shape tables live) **first**, then
  update every implementation side in the same PR.
- The `Verified by:` tests named per contract are not optional; don't weaken
  them to make a PR green.
- If the contract and implementation drift and you cannot tell which is correct,
  **stop and ask** — a wrong derivative is worse than an error
  (`REVIEW_CONTEXT.md` principle 1); do not pick a side unilaterally.

## 4. Discuss major decisions before deciding; ADR if it sticks

A "major decision" is anything that:

- changes a contract in `docs/DESIGN.md` §Contracts,
  `adigatorDerivativeConventions.m`, `docs/CI_PLAN.md` (requirements/tests), or
  `docs/REVIEW_CONTEXT.md` (whose principles are load-bearing for every review);
- introduces a new external dependency or a new on-disk/generated artifact;
- locks in a trade-off a future PR could reasonably want to revisit (thresholds,
  fallback ordering, error-handling policy, down-cast/precision choices);
- materially changes the scope or shape of the work being done.

For any of the above:

1. **Pause and surface the decision** — describe the choice, the alternatives,
   and the trade-off. Wait for an explicit go-ahead before implementing.
   **Recommend, don't decide:** lay out the options and mark the one you'd
   choose with a one-line why, then let the maintainer choose. This posture
   applies to *every* question put to the maintainer, including
   `AskUserQuestion` prompts — not only §4 decisions.
2. **If the decision is accepted and non-obvious, write an ADR** in
   `docs/decisions/` per `docs/decisions/README.md`. Link it from the PR.
3. **Tactical/mechanical choices don't need this** — formatter settings, import
   ordering, internal naming, obvious refactors. When in doubt, ask; a question
   is cheaper than an unwanted commit.

## 5. Opening a PR is free for planned work; merging needs approval

Opening a PR for work that implements an already-approved item does **not** need
separate approval — open it once the work is ready and the §2 pre-push
self-review (plus local CI, once it lands) pass. Work that is **not** part of an
approved plan follows §4: surface it and wait for the go-ahead before opening
the PR.

**Merging always requires explicit maintainer approval.** Never merge on your
own initiative, not even a green PR. A §4 major decision discovered
*mid-implementation* is still surfaced, even though opening the PR was
pre-authorized.

The full loop and the authoring-vs-reviewing roles live in
`docs/CONTRIBUTING.md` §"Two-session authoring / review workflow". Note this is
repo *policy*: the binding per-session authorization still comes from how the
session is launched, so the standing grant must be given there too — this
document does not override a session instruction.
