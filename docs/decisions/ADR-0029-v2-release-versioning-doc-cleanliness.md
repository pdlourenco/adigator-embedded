# ADR-0029 — Release as v2.0; user-facing docs are state-based and release-relative

## Status

Accepted — 2026-07-11 (issue #179). Extends [ADR-0013](ADR-0013-fork-versioning-over-upstream.md)
(fork-versioning) with the concrete version number + scheme, and
[ADR-0025](ADR-0025-guide-code-snippets-from-fixtures.md) (emitted fragments are
user-facing). The exact copyright/attribution *notice text* (Decision 3) is to be
finalized with maintainer sign-off before it touches the branding files.

## Context

The embedded fork releases from this repo (ADR-0013) but has never cut a
release. Internally it is labelled **v1.5** — as if it were a patch of upstream
ADiGator 1.x — in the version constant (`adigator.m`), in ~83 `% v1.5 …` code
comments, and in the docs' "Version 1.5 fork" framing. Two problems
(issue #179):

1. **The label undersells the work.** The fork adds embed modes, reverse mode +
   matrix-free products, the N-D parameter veneer, `loopbound`, `der_output`/
   `*Locs`, struct inputs, and more — new capability, not a 1.x patch.
2. **User-facing docs track in-fork development.** The guide, README, and
   `bench/SHOWCASE.md` carry "ADR-XXXX / PR #Y / roadmap Rnn / rev-date / Bnn
   did this" — useful for developers, noise for a user of the toolbox, who cares
   only what the current release does and what changed since the last one. The
   showcase is the worst case: a *new* doc that shouldn't track changes at all.

The upstream toolbox front matter is also stale: root `Contents.m` still reads
`Copyright 2011-2015 Weinstein & Rao` / `website: matt-weinstein/adigator` with
no `% Version` line, and `startupadigator.m`'s banner points at sourceforge.

## Decision

1. **Release as v2.0.** The fork's first release is ADiGator **v2.0** — a major
   version reflecting the new capability, superseding the dormant upstream 1.x
   lineage (ADR-0013). Versioning follows semantic versioning going forward.
2. **Canonical version + generated-file stamp.** The version is defined once
   (`adigator.m`, `version = '2.0'`) and stamped into every generated file. A
   bump therefore propagates to generated output and to the committed golden
   fixtures, which are regenerated (or their version line normalized in the
   comparison) as part of the bump.
3. **Attribution / branding.** Preserve the upstream copyright (Weinstein & Rao)
   and GPLv3; **add** the fork's attribution (GMV / P. Lourenço). The toolbox
   front matter is updated: root `Contents.m` gains a `% Version 2.0 <date>`
   line and the fork URL; `startupadigator.m`'s banner drops the stale
   sourceforge pointer. *(The exact notice wording is signed off by the
   maintainer before the branding edit — GPL requires the upstream notice be
   preserved, so this is finalized deliberately, not guessed.)*
4. **User-facing docs are state-based and release-relative.** The user guide,
   README, `bench/SHOWCASE.md`, and the ADR-0025 emitted fragments describe
   **current behavior**; a behavior change is referenced **release-relative**
   ("new in v2.0", "deprecated in v2.0"), never by in-fork dev tracking
   (`ADR-xxxx` / `PR #x` / `#issue` / roadmap `Rnn` / rev-date / `Bnn`, or an
   inline dev-doc section citation such as `ANALYSIS §` / `DESIGN §Contracts` —
   as distinct from a navigation *link* to those docs, which is allowed). The
   release-to-release change history lives in a user-facing **`CHANGELOG.md`**;
   user docs point there instead of carrying inline change notes. User docs may
   still *link* to dev docs as clearly-marked navigation ("development plan: see
   ROADMAP").
5. **Dev docs and code comments keep the full audit trail.** ADRs, `ANALYSIS.md`,
   `ROADMAP.md`, `CI_PLAN.md`, and `DESIGN.md` rationale keep tracking as they
   do. **Code comments keep full traceability**: the diff-annotations that
   justify why upstream code was touched, and the `Bxx` / `Rnn` / `#issue` /
   `ADR-` / `ANALYSIS` references, are correct and continue as convention. The
   **only** rule is that a change's **version tag names the release it ships
   in** — so the one-time correction is `v1.5` → **`v2.0`** across the code
   comments and `Changelog` header blocks; future changes tag their own release
   (v2.1, …).

## Consequences

- A user-facing `CHANGELOG.md` is added ("v2.0 — first release of the embedded
  fork", listing the headline features). It becomes the single change record the
  clean docs point to.
- Cutting v2.0 is a discrete step touching four surfaces: the `adigator.m`
  constant, the committed-fixture regeneration/normalization, the
  `Contents.m`/banner branding, and the docs framing. The code-comment tag sweep
  (`v1.5`→`v2.0`) rides with it.
- The pre-push review (CONTRIBUTING §Pre-push, REVIEW_CONTEXT principle 8) gains
  two checks: user-facing docs carry no dev-tracking refs, and code-comment
  version tags read the shipping release.
- The ADR-0025 emitted fragments must stay clean (`bench_compare.tex` already is;
  the new `bench_interp.tex` and any regenerated `SHOWCASE.md` must be too — a
  producer-side obligation on the bench code).
- **Revisit when:** the next release increments the version (per semver); the
  doc-cleanliness and version-tag conventions are standing.

## Alternatives considered

- **v1.5 (the fork's current internal label).** Rejected: the accumulated
  capability is a major version, not a patch of upstream 1.x. Maintainer's call
  (#179).
- **Strip dev-tracking from code comments too.** Rejected: the diff-annotations
  justify why upstream code was touched and complement the per-file changelog;
  the `Bxx`/`Rnn`/`#issue`/`ADR` refs are valuable in-code traceability. Only the
  version *tag* was wrong, not the comments.
- **Keep inline change-tracking in user docs (status quo).** Rejected: that is
  exactly #179 — a user does not need "how it was and when it changed", only the
  current behavior and the release-to-release delta (which the CHANGELOG holds).
- **A REVIEW_CONTEXT principle alone, no ADR.** Rejected: the versioning scheme +
  attribution is a sticky release decision worth an ADR; the policy is recorded
  in all three places (ADR + principle + CONTRIBUTING) per the #179 decision.
