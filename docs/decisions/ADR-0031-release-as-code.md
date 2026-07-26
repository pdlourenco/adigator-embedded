# ADR-0031 — Release-as-code: a tag-gated release workflow

## Status

Accepted — 2026-07-25. Enforces the release-versioning discipline of
[ADR-0029](ADR-0029-v2-release-versioning-doc-cleanliness.md) (a `CHANGELOG.md`
is the user-facing change record; the version *tag* marks the ship-release).
Adapted from `pdlourenco/disciplined-project-seed`'s release workflow.

## Context

ADR-0029 established that user-facing change history lives in `CHANGELOG.md` and
that cutting a git tag is what marks a release. But nothing *enforced* the link:
a maintainer could tag `v2.0` while the CHANGELOG's `[2.0]` section was missing,
undated, or while `[Unreleased]` still held un-cut entries — producing a release
whose notes don't match its contents. With v2.0 about to be the fork's first
tagged release, the convention needs to become a structural check rather than a
discipline-only promise, and the release ceremony (notes, artifact) should be
mechanical and reproducible rather than a hand-run sequence.

## Decision

Add a **tag-triggered GitHub Actions release workflow** that treats *pushing a
`vX.Y[.Z]` tag as the human release decision* and does the mechanical ceremony,
**gated** on the CHANGELOG:

- `.github/workflows/release.yml` — on a `v*` tag push it (1) **validates** the
  tag against `CHANGELOG.md` (a dated `## [X.Y] — YYYY-MM-DD` section exists,
  `[Unreleased]` is empty) **and** against `adigator.m`'s `version = '…'`
  constant, so a tag can't disagree with either (mismatch → the run fails, no
  release); (2) **extracts** that version's section as the release body; (3)
  assembles a **curated runtime distribution** archive (below); (4) creates the
  GitHub release with the archive attached.
- `.github/scripts/release_changelog.py` — the `validate` / `extract` gate,
  kept out of inline workflow one-liners so it is runnable locally without
  pushing a tag. Accepts the fork's two-part version scheme (`2.0`) and
  three-part semver; `--source-file` adds the source-version cross-check.
- **Curation of the distribution archive** (the accepted non-obvious calls): it
  is the tagged tree with (a) every dot-entry stripped at any depth (no
  `.github`/`.gitignore`/… ships); (b) the test/bench harnesses and dev-process
  docs (ROADMAP/CI_PLAN/REVIEW_CONTEXT/CONTRIBUTING/`decisions`) removed; (c) the
  user guide shipped as its **built PDF only** (its LaTeX source dropped); (d)
  the **third-party reference publications** (`docs/papers`, `docs/thesis` —
  publisher-copyrighted ACM/AIAA/dissertation works) **NOT shipped**, since this
  fork may not redistribute them inside its release; `docs/README.md` carries
  their citation/DOIs and links to the source repo instead. `docs/README.md` is
  also copied to the archive root so the unpacked dist shows a top-level readme.
  The legacy `unit_tests/` harness was folded into `tests/legacy/` (one test tree).
- `CHANGELOG.md` gains a `## [Unreleased]` section (the home for changes between
  releases); the release process (`docs/CONTRIBUTING.md` §"Cutting a release")
  is: move `[Unreleased]` into a dated `## [X.Y] — <date>` section, commit, then
  push `vX.Y`.

Human triggers, machine executes and validates.

## Consequences

- A release cannot be published whose notes don't match the CHANGELOG — the gate
  is the same posture as the pre-push review and the contract tests: a convention
  turned into a check. Release notes and the distribution artifact are
  reproducible from the tag alone.
- The maintainer must keep `[Unreleased]` current and cut the dated section
  before tagging; a forgotten step fails the run with an actionable message
  rather than shipping a mismatched release.
- The curated archive's exclusion list (`ARCHIVE_EXCLUDES`) is a tuning surface,
  not a contract; it strips `tests/`, `bench/`, internal docs, and the reference
  publications. The proprietary GMV reports under `docs/analyses` are gitignored
  per-file (never tracked), and `docs/analyses` is excluded outright — so even
  if the list drifts, `git archive HEAD` already omits untracked/gitignored
  files and nothing proprietary can leak.
- **The gate does NOT enforce that the tagged commit is green.** `ci.yml` runs
  on branch pushes, not tags, and the release job requires no passing check on
  the tagged commit. Tagging a **green `master`** is therefore the human's
  responsibility (`docs/CONTRIBUTING.md` §"Cutting a release"): tag the merge
  commit whose CI already passed, not an arbitrary or red commit. The gate
  covers the CHANGELOG↔tag↔source-version consistency, not CI status.
- **Revisit when:** the version scheme changes (two-part `2.0` → three-part
  semver — the gate already accepts both, but the `adigator.m` `version`
  constant and the tag convention would move together); or a fully-automatic
  release-on-merge is ever wanted (deliberately not adopted here).

## Alternatives considered

- **Fully-automatic release on merge to `master`.** Rejected: a release is a
  human decision (which commits, which version, when). Automating it removes the
  deliberate gate ADR-0029 established and makes an accidental merge a public
  release.
- **A hand-run release checklist (no automation).** Rejected: it re-introduces
  the discipline-only gap this ADR closes — nothing stops a tag whose CHANGELOG
  section is missing or whose `[Unreleased]` is non-empty.
- **Attach only GitHub's auto "Source code" archives (no curated artifact).**
  Rejected as the *sole* artifact: the tool is a MATLAB library a user
  `addpath`s, and the full tree carries the ~300-test suite, the bench harness,
  and internal docs. The curated `*-dist` archive is the clean "download and
  use" path; the auto archives remain available as the everything-included
  variant.
- **Gate on a machine-readable release manifest instead of the CHANGELOG.**
  Rejected: the CHANGELOG is already the single user-facing source of truth
  (ADR-0029); a second manifest would be a redundant copy to drift.
