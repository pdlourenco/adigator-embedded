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
- [ ] Local CI / relevant `unit_tests/` run: <!-- result, or N/A for docs-only -->
- [ ] Contract change (if any) updated DESIGN.md §Contracts + every implementation side
- [ ] ADR added/linked if a non-obvious decision sticks
