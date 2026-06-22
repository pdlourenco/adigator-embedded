# Architecture Decision Records

Short records of non-obvious decisions in adigator-embedded, with enough
context that a future contributor (human or agent) understands *why* and *when
to revisit*. ADRs are the tactical layer beneath [`DESIGN.md`](../DESIGN.md)
(architecture) and its Contracts section (binding surfaces).

## What an ADR is — and isn't

**Write one** when a choice will stick and a future PR might reasonably want to
revisit it: a fallback ordering, a threshold, an error-handling policy, a
backwards-compat seam, a supported-version floor. The "Alternatives considered"
section is the part that earns its keep six months later.

**Don't write one** for choices that belong in `DESIGN.md` (architecture) or its
Contracts section (binding conventions), or for purely mechanical choices
(formatter settings, internal naming).

## Conventions

- Filenames: `ADR-NNNN-kebab-case-title.md`, `NNNN` zero-padded, assigned
  sequentially as ADRs merge. Numbers are never reused or reordered.
- **Parallel tracks: rebase before finalizing the number.** When two sessions
  run a track in parallel (the two-session workflow in
  [`../CONTRIBUTING.md`](../CONTRIBUTING.md) §"Two-session authoring / review
  workflow") and both append an ADR, a number assigned off a shared merge-base
  collides at the *second* merge. Reserve a per-track band and **rebase onto
  the base branch before finalizing the number** — the rebase surfaces the
  in-flight neighbour the merge-base hid. The same rule applies to any
  identifier drawn from a sequence parallel tracks both append to.
- Use the shape in [`ADR-TEMPLATE.md`](ADR-TEMPLATE.md).
- Link the ADR from the PR description; reference it inline beside tactical
  values (`% see ADR-NNNN` next to a magic number or a policy branch).
- If an ADR supersedes another, reference the old one in its Status section and
  flip the old one to "Superseded by ADR-NNNN".

## Index

- [ADR-0001](ADR-0001-downcast-index-fields-only.md) — Down-cast only `Index*`
  fields; keep `Data*` as `double`.
- [ADR-0002](ADR-0002-norm-matrix-induced-errors.md) — Matrix-induced norms
  raise an error rather than mis-differentiating.
- [ADR-0003](ADR-0003-r2022a-minimum-release.md) — Minimum supported release is
  R2022a.
- [ADR-0004](ADR-0004-single-install-ci-pipeline.md) — PR CI is a single MATLAB
  install with sequential steps.
- [ADR-0005](ADR-0005-der-levels-output-selection.md) — `DER_LEVELS` selects
  which derivative levels a generated wrapper returns (roadmap R7a, issue #21).
- [ADR-0006](ADR-0006-r7b-closure-gate.md) — R7b slimming is gated by an
  eval-free dependency-closure check, not a numeric round-trip (issue #21).
- [ADR-0007](ADR-0007-montecarlo-vv.md) — Randomized / Monte-Carlo V&V:
  non-gating, tolerance-free oracles, fixture-promoting (issue #38).
- [ADR-0008](ADR-0008-offline-fixture-equivalence-tests.md) — License-free
  equivalence tests run committed generated fixtures via a plain-assert core +
  matlab.unittest wrapper (issue #44 part 1b).
- [ADR-0009](ADR-0009-interprocedural-field-slice-worklist.md) — Interprocedural
  field-slice via an assembled-file worklist over `(function, demanded-field-set)`
  (issue #44 item 1).
