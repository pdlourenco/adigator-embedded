# Contributing to ADiGator-embedded

ADiGator-embedded is a small, largely agent-developed fork of the ADiGator
source-transformation AD tool. The thing that matters is that the **generated
derivative is correct**; these conventions exist to defend that cheaply. CI
strategy, requirements, and test traceability are owned by
[`CI_PLAN.md`](CI_PLAN.md) — this document covers the contributor mechanics
around it.

## Pre-push self-review

Before **every** `git push` on a PR branch, launch a reviewer subagent on the
local diff, seeded with [`REVIEW_CONTEXT.md`](REVIEW_CONTEXT.md) (principles +
red flags) alongside [`DESIGN.md`](DESIGN.md) and [`ANALYSIS.md`](ANALYSIS.md),
and act on what it flags before pushing. This catches the "I'd have caught that
if I'd thought harder" class of bug before it burns a (MATLAB-licensed) CI
round-trip or reviewer attention.

Ask the reviewer to check the diff for: (1) the principles in
`REVIEW_CONTEXT.md` cited by number; (2) contract drift vs. `DESIGN.md`
§Contracts; (3) the dimension-branch / path-leak / `Data*`-down-cast red flags;
(4) a bug fix landing without flipping or adding its pinning test; (5) scope
drift from the PR's stated purpose; (6) a decision that deserves an ADR.

**Exceptions** — one-line typo fixes, formatting-only changes, pure reverts.
The ceremony costs more than the signal. Note the outcome in the PR description:
`pre-push review: no findings` or `pre-push review flagged X, fixed in <sha>`.

## Local development & pre-push CI

The code requires real MATLAB (R2022a+, [ADR-0003](decisions/ADR-0003-r2022a-minimum-release.md)).
The license-free way to get the CI verdict before pushing is to run the suites
in your existing MATLAB session — `CI_PLAN.md` §3.3 specifies a `ci_local.m`
entry point (lint + unit + integration) for exactly this, optionally wired as a
git pre-push hook. Today the finite-difference rule tests live in
`unit_tests/` (`test_unarymath_rules.m`, `test_norm_rules.m`); run those at
minimum.

Note: the MATLAB suite **cannot** run in a Claude-Code-on-the-web container
(MATLAB is licensed and not provisioned there) — it runs in GitHub Actions
(`CI_PLAN.md` §3.1) and in local MATLAB sessions. Web sessions can still author,
review diffs, and edit docs.

## Design decisions (ADRs)

Non-obvious tactical choices live in [`decisions/`](decisions/) — see
[`decisions/README.md`](decisions/README.md) for when to write one and the
numbering convention (including the parallel-track rebase rule). Link the ADR
from the PR description; reference it inline beside the value it explains.
Contracts and architecture themselves belong in `DESIGN.md`, not an ADR.

## Commit & branch conventions

- Feature branches: `claude/<topic>-<short-hash>` for agent work,
  `<user>/<topic>` for humans.
- Commits: imperative subject line, ≤70 chars; follow the existing `git log`
  style. One topic per commit where practical — it keeps CI failures
  diagnosable.

## PR lifecycle

Per [`../CLAUDE.md`](../CLAUDE.md) §5:

- **Opening a PR is free for already-planned work** — implementing an
  already-approved item does not need separate approval; the pre-push
  self-review (and local CI, once it lands) run first. Unplanned work follows
  `CLAUDE.md` §4 (surface it, wait for go-ahead) before the PR opens.
- **Merging always requires explicit maintainer approval** — never on an
  agent's own initiative, not even a green PR.

## Two-session authoring / review workflow

For parallel agentic development the default topology is **two sessions per
track**: one authors, one reviews. They never share the three verbs below. See
[ADR-0009 in the seed](https://github.com/pdlourenco/disciplined-project-seed/blob/main/meta/decisions/ADR-0009-agent-pr-lifecycle-and-two-session-workflow.md)
for the rationale; the open/merge authorization this assumes is set in
[`../CLAUDE.md`](../CLAUDE.md) §5.

### Roles

- **Authoring session** — implements a planned item, opens the PR, pushes
  fixes, and **merges on the maintainer's *"merge and proceed."*** Owns the
  code. Its only review duty is the **pre-push self-review of its own diff**
  (above) — *not* the same verb as reviewing a PR.
- **Reviewing session** — **only reviews** (on *"review PR X"*) and follows
  through. It never edits or pushes code, and **never merges** — not even a
  clean, approved PR.

At a glance:

| Session | Authors / edits | Reviews open PRs | Merges |
|---|---|---|---|
| **Authoring** | yes | no — only the pre-push self-review of its *own* diff | yes, on `merge and proceed` |
| **Reviewing** | no | yes | no |

### The loop

1. **Authoring** implements and **opens the PR** — no separate approval for
   in-plan work; the pre-push self-review runs first.
2. **Reviewing** reviews on *"review PR X"*. Never touches code.
3. Maintainer tells authoring *"reviews posted"*; it analyses the comments and
   pushes any fixes.
4. Repeat 2–3 until the review is clean.
5. Maintainer tells authoring *"merge and proceed"*; it merges (squash / rebase
   for linear history) and starts the next item.

### Command vocabulary

| Phrase | Session | Means |
|---|---|---|
| `review PR X` | reviewing | review PR X against `REVIEW_CONTEXT.md` |
| `reviews posted` | authoring | analyse the posted review, push fixes |
| `merge and proceed` | authoring | merge the open PR, then start the next item |

When two authoring sessions run in parallel and share a contract surface, prefer
**one shared reviewer** over one-per-author — cross-track contract drift is
exactly what a single reviewer holding both contexts catches and two siloed
reviewers each miss.

The kickoff collapses to one line: *"you are the authoring / reviewing session
for <work item>, per `CONTRIBUTING.md` §Two-session authoring / review
workflow."* Only role + work-item are seeded per session.

## Warnings are actionable

CI warnings, deprecation notices, and MATLAB `checkcode` warnings should be
addressed, not tolerated — ignored only when triggered on purpose, with a
narrow suppression plus a one-line comment saying why. `CI_PLAN.md` treats the
`checkcode` warning count as a ratchet (REQ-C-10); don't grow it.
