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
- **Before assigning a number, scan both merged and in-flight ADRs.** A rebase
  only reveals what has *merged*; an open PR on another branch can still hold
  the next number. Take `NNNN = 1 + max(merged, in-flight)`:
  ```sh
  git ls-tree --name-only origin/master docs/decisions/ | grep ADR-   # merged
  gh pr list --state open --search 'ADR- in:files'                    # in-flight
  ```
  (e.g. ADR-0011 was taken precisely because master held 0001–0009 *and* an open
  PR already claimed 0010). If you must pick before an in-flight neighbour
  merges, leave its number reserved and take the one after.
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
- [ADR-0010](ADR-0010-prune-shrink-referenced-index-scan.md) — Prune-shrink drops
  a `Gator*Data.Index*` only when a static scan proves the slimmed code cannot
  reference it; keep-all on any doubt (issue #21, R7b data half).
- [ADR-0011](ADR-0011-adigator-error-path-cleanup.md) — `adigator.m` releases
  transformation state on every exit: globals cleared in-frame, temp dir / file
  handles via a by-value `onCleanup` (issue #38, bug B16).
- [ADR-0012](ADR-0012-embedded-generator-default-inline-slim.md) —
  `adigatorGenDerFile_embedded` defaults to inline + slim via an unset
  `embed_mode`/`slim_embed` sentinel; the classic generators still resolve to
  classic / off.
- [ADR-0013](ADR-0013-fork-versioning-over-upstream.md) — Release from this repo
  (fork-versioning) rather than upstreaming the dormant Algorithm-984 lineage;
  keep the B-series fixes cherry-pick-ready (issue #18 item 3).
- [ADR-0014](ADR-0014-matlabtest-codegen-equivalence.md) — Adopt MATLAB Test
  `matlabtest.coder.TestCase` codegen-equivalence into the V&V suite: re-base
  `SCodegenTest` (hand-rolled fallback kept) and add a sampled, skip-clean
  `oracleCodegenEquivalence` to the #38 campaign (issue #64).
- [ADR-0015](ADR-0015-cada-benign-read-global-hygiene.md) — `@cada` benign read
  methods (`subsref` `.`-access, `size`/`length`, `isempty`) declare the
  transformation globals only on the paths that use them, so reading a returned
  cada object no longer re-registers an empty `ADIGATOR`; the B16 hygiene asserts
  tighten to strict-absent (R11, issue #54).
- [ADR-0016](ADR-0016-matrix-free-products-efficiency-path.md) — measured
  determination: matrix-free products (J·v, J'·v, H·v) are the embedded-efficiency
  path (zero-ROM, density-independent); forward+sparsity stays for assembled
  matrices (dense O(n²) is intrinsic); the re-vectorization peephole is shelved.
  Ties #56 (direction) / #73 (all-axes comparison to C) / #64 (codegen-equivalence
  infra); new `_Hvp`/`_Jv` generators follow the `[deriv…, Fun]` convention
  (R12 reframed; R16–R19).
- [ADR-0017](ADR-0017-prepush-clean-path-testing.md) — pre-push testing runs the
  suite the way CI does (clean path, not `genpath`/`startup`); the
  `AdigatorTestCase` base + `UTestPathHygieneTest` meta-test guard against the
  dirty-path "works on my machine" trap (R20-adjacent, issue #82).
- [ADR-0018](ADR-0018-casadi-independent-oracle.md) — adopt CasADi (symbolic
  expression graph — a method independent of source transformation) as a
  **dev-only, skip-clean** independent correctness oracle + codegen benchmark;
  binaries not committed (issue #87, supports the #80 v2 engine work).
- [ADR-0019](ADR-0019-rolled-embeddable-path-scatter-deferred.md) — the **rolled**
  (`unroll=0`) form is the embeddable path (ERT-safe de-dup via a local temp in
  `structure_to_embed_mfile`); the O(n²) fixed-size-scatter efficiency rewrite is
  deferred to R21 (issue #80 Gap B, Path A).
- [ADR-0020](ADR-0020-nth-derivative-output-conventions.md) — **Accepted**:
  higher-order (n-th) derivative output conventions — native nonzeros/`*Locs`
  form (default for k≥3) + a dense `[M·Nᵏ⁻¹ × N]` fold generalizing the Hessian
  rule; symmetry dedup deferred; staged scalar→matrix. Convention binds C-1;
  implementation is roadmap R22 (issue #85, needs #84).
- [ADR-0021](ADR-0021-deprecate-coderload-split-inline-data.md) — **Accepted**:
  deprecate the coderload `'l'` mode (fork-only, fails ERT, footprint converges
  with `'i'`) and add a split-inline (derivative + data) form so large-data
  source size is no reason to keep it; binds C-4 (deprecation + split-form
  invariants), removal R17-gated; implementation roadmap R24 (issue #83).
- [ADR-0022](ADR-0022-generalized-der-output-nonzeros.md) — **Accepted**:
  a canonical `der_output ∈ {matrix, nonzeros}` option + a `*Locs` family across
  DerTypes (`jac_output` kept as a level-1 alias); binds C-6 (a fourth facet) +
  extends C-2. Phase 1 shipped (Hessian-nonzeros/`HessianLocs`, `Jac→Grd` fix,
  R25/#99; `der_output` flips each generator's top output only — no cross-sync,
  "decision b"); the option×DerType×mode matrix + per-level selection are
  deferred to R25 phase 2 (issue #84; prerequisite for R22/#85).
- [ADR-0023](ADR-0023-embed-source-scan-gate.md) — **Accepted** (embed-mode
  source-scan gate for cells / `load` / `global`; adds an embed facet to C-4;
  B21/B22-in-embed, issues #101, R26), **revised 2026-07-04**: the disposition
  changes from a hard **error** to a **warning + verbatim emission** (embed is
  no more restrictive than classic) — realignment pending in #123 / R29 (until
  then the tool still errors).
- [ADR-0024](ADR-0024-data-dependent-index-actionable-error.md) — **Accepted**:
  data-dependent (symbolic) indexing stays unsupported — a **limitation policy**
  (not a contract change); the fix is *error quality* (an actionable error
  pointing to the logical-weight-sum rewrite), never a wrong derivative
  (B19/B20; issues #101/#108; pinned by `ISymbolicIndexTest`).
