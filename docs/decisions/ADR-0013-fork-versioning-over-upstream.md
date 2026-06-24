# ADR-0013 — Fork-versioning over upstreaming for the embedded ADiGator fork

## Status

Accepted — 2026-06-24

## Context

ADiGator is a published algorithm (Weinstein & Rao, *Algorithm 984*, ACM TOMS);
the upstream Weinstein/Rao repository has been dormant since ~2017. This fork has
diverged structurally, not cosmetically: a new `embedding/` subsystem (the
`c`/`l`/`i` embed modes plus the pruning / inline-data codegen path), new options
(`EMBED_MODE`, `PATH`, `LOOPBOUND`, `DER_LEVELS`, `SLIM_EMBED`, …), *changed
observable output conventions* (the B7/B9 wrapper-layout fixes), a V-model
CI/test harness, and semantic extensions (the N-D parameter veneer R2, runtime
loop bounds R3, reverse-grad / `J'·v` R4/R5). GPLv3 fully permits independent
releases here as long as attribution is preserved (already done in the file
headers, #16).

Issue #18 item (3) asked whether the fork's changes should be sent upstream or
released from this repo. The choice was surfaced per CLAUDE.md §4 with options
and a recommendation; the maintainer settled it on the fork option (issue #18,
2026-06-24: *"Agree with the fork option (we've essentially already done
that)"*).

## Decision

Release from **this repository** (fork-versioning): tags + GitHub Releases + an
aggregated changelog, under this repo's own version lineage, with an explicit
divergence notice in the README/`NOTICE` stating what the fork adds and how it
differs from upstream 1.5. Keep the GPLv3 attribution intact. Do **not** drive
the work as upstream pull requests.

Keep the B-series bug fixes cherry-pick-ready so a future upstream contribution
is cheap if upstream ever revives, and (per the issue's D4) file one *courtesy
issue* upstream pointing here.

Lands as: the roadmap R13(3) status; the README divergence section; and the
first-release mechanics (roadmap D3 — `CHANGELOG.md`, the `adigator.m` version
string, a tag/Release). The concrete release *number* (e.g. whether the B7/B9
output changes warrant a 2.0.0 semver bump) is a separate downstream choice and
is **not** fixed by this ADR.

## Consequences

- **Easier:** ship on our own cadence with no dependence on an unresponsive
  upstream; the embedding subsystem and the changed conventions live coherently
  in one place.
- **Harder / constrained:** no community reach *through* upstream; we carry the
  maintenance and the standing obligation to keep attribution visible and the
  divergence documented, so users are never misled about provenance. The
  B-series fixes should stay isolated enough to cherry-pick.
- **Revisit if:** upstream revives or a maintainer there signals willingness to
  merge; or a downstream consumer needs the canonical Algorithm-984 lineage
  rather than this fork. The cherry-pick-ready fixes make a courtesy PR cheap at
  that point.

## Alternatives considered

- **Upstream PRs (contribute back).** High community value *if* upstream were
  alive, but there is no evidence it is (dormant since ~2017), so the realistic
  outcome is PRs sitting unmerged indefinitely. It would also force untangling
  the clean B-series fixes from the fork-specific architecture (the embedding
  subsystem, the changed conventions) for little return. Rejected as likely dead
  effort.
- **Dual track** — maintain the fork *and* proactively prepare/maintain an
  upstream-able patch series. The valuable half of this is folded into the
  decision (keep the B-series fixes cherry-pick-ready; file a courtesy issue)
  without paying the standing cost of maintaining a parallel patch series
  against a repo that may never respond.
