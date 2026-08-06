<!-- See docs/CONTRIBUTING.md for the conventions this template references. -->

## What & why

<!-- One or two sentences: what this PR changes and the motivation. Link the
     issue or ANALYSIS.md bug ID (Bn) it addresses. -->

## Contracts & decisions

<!-- Does this touch a contract in docs/DESIGN.md §Contracts or
     adigatorDerivativeConventions.m? If so, confirm both sides were updated in
     this PR. Link any ADR (docs/decisions/) this implements or adds. -->

## Tests

<!-- What pins the change? A bug fix must flip its KnownIssue test to a hard
     assertion (or add a new test) in this same PR — see CI_PLAN.md. -->

## Checklist

- [ ] Pre-push review: <!-- "no findings" or "flagged X, fixed in <sha>" — docs/CONTRIBUTING.md §Pre-push self-review -->
- [ ] Local CI (`tests/ci_local.m`) / relevant `tests/` run: <!-- result, or N/A for docs-only -->
- [ ] Contract change (if any) updated DESIGN.md §Contracts + every implementation side
- [ ] ADR added/linked if a non-obvious decision sticks
- [ ] Major bug fix or major feature: unbounded Monte-Carlo campaign run and failures triaged <!-- tests/montecarlo, CI_PLAN.md REQ-T-09; N/A otherwise. The campaign is deliberately non-gating, so this row is the only thing that makes it run -->
- [ ] Deferral sweep if this closes a ROADMAP row: triggers that fired are wired in or re-deferred with a new trigger <!-- docs/CONTRIBUTING.md §Deferral sweep; N/A otherwise -->
- [ ] Local test counts, if quoted, name the environment they came from <!-- REVIEW_CONTEXT.md §Evidence discipline tell 3 -->
- [ ] Seed flow-down or backport, if any, recorded in DISCIPLINE_ADOPTION.md
