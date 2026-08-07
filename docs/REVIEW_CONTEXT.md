# ADiGator-embedded — Reviewer Context

Seeds a reviewer (agent or human) with what this project actually cares about,
so a review is judgment against principles and contracts — not surface lint.
Point the reviewer at [`DESIGN.md`](DESIGN.md) (architecture + Contracts),
[`CI_PLAN.md`](CI_PLAN.md) (requirements/tests), [`ANALYSIS.md`](analyses/ANALYSIS.md)
(known bugs B1–B26 and optimization notes), and this file before a review.

## Project in one paragraph

ADiGator-embedded is the embeddable-codegen fork of ADiGator, a MATLAB tool that
differentiates a MATLAB function by **source transformation via operator
overloading**: it runs the user's function once with overloaded objects that
record operations and *print a standalone derivative file* with statically known
sizes and sparsity. The fork's reason to exist is that this static file can be
stripped of runtime dependencies (`global`, `load`, `.mat`) and compiled with
MATLAB Coder for embedded targets. The thing that matters above all is that the
**generated derivative is correct** — a silently-wrong derivative is the worst
outcome, worse than an error. Architecture is locked (overloading + generation,
the `@cada`/`@cadastruct` classes, the three embed modes `c`/`l`/`i`); the work
is correctness, embeddability, and code-size/runtime fitness of the generated
code.

## Verification vs. validation

Two review modes; the reviewer can run either or both.

- **Verification — *did we build it right?*** Does the diff match the binding
  contracts in [`DESIGN.md`](DESIGN.md) §Contracts (C-1..C-6), the conventions
  in `adigatorDerivativeConventions.m`, and the `Verified by:` tests in
  `CI_PLAN.md`? Findings are mechanical: a rule said X, the diff did Y.
- **Validation — *did we build the right thing?*** Does the diff honour the
  principles below and the PR's stated scope? Findings are judgment calls.

A bundled review covers both. Narrow with "review in verification mode" /
"validation mode" for tighter findings at lower cost.

## Core principles (review against these)

1. **A wrong derivative is worse than an error.** When a rule cannot be
   computed correctly (e.g. the SVD-based matrix-induced norm, ADR-0002), the
   tool must raise a clear error, never emit a plausible-but-wrong derivative.
   Flag any change that lets an unsupported case fall through to a generic path.
2. **The tool introduces no runtime dependencies into `'l'`/`'i'`.** The
   *generator* adds no `global` and no runtime `load` to `'l'`/`'i'` code; `'i'`
   additionally no `.mat` and no `coder.load` (contract C-4). A PR that makes the
   *tool* reintroduce any of these into the restricted modes breaks the fork's
   reason to exist. A **user's own** `global`/`load`/cells in the differentiated
   source are a different matter: embed is *no more restrictive than classic*, so
   they pass through **verbatim (as classic) with a warning** (ADR-0023 rev
   2026-07-04) — flag reduced embeddability, don't flag the pass-through itself as
   fork-breaking. Still flag any change that would let the *tool* emit its own
   `global`/`load`/`.mat`/`coder.load`, or that suppresses the user-source
   warning.
3. **Cross-mode numeric identity.** `'c'`, `'l'`, `'i'` must return
   bit-identical results — they are the same arithmetic, only the data-delivery
   mechanism differs. Flag anything that could make a mode diverge numerically.
4. **Codegen compatibility is a constraint, not an afterthought.** Generated
   `'l'`/`'i'` files must pass MATLAB Coder (`lib` target). Watch for constructs
   that break codegen (dynamic growth, unsupported builtins, non-`coder.const`
   constant reads).
5. **Index vs. Data is a hard distinction.** `Index*` fields are index vectors
   (down-castable to integer); `Data*` fields are arithmetic constants (stay
   `double`) — contract C-3, ADR-0001. Flag any code that conflates them or
   down-casts `Data*`.
6. **Correctness is defended by tests, not assertion.** A bug fix flips its
   `KnownIssue` test (`CI_PLAN.md`) to a hard assertion in the *same* PR; a new
   rule/branch comes with an FD or analytic check. Flag fixes that land without
   their pinning test.
7. **GPLv3 hygiene.** The project is GPLv3 (root `LICENSE`). A new
   dependency's licence must be compatible and declared.
8. **Docs are state-based and release-relative.** User-facing docs — the user
   guide, `README`, `bench/SHOWCASE.md`, and the ADR-0025 emitted fragments —
   describe *current* behavior; a behavior change is referenced release-relative
   ("new in v2.0", "deprecated in v2.0"), never by in-fork dev tracking
   (`ADR-xxxx` / `PR #x` / `#issue` / roadmap `Rnn` / rev-date / `Bnn`, or an
   inline dev-doc section citation like `ANALYSIS §` / `DESIGN §Contracts` —
   distinct from a navigation *link* to those docs, which is fine). That
   tracking belongs in the dev docs (ADR / ANALYSIS / ROADMAP / CI\_PLAN) and in
   **code comments** — which keep the full audit trail (diff-annotations +
   `Bxx`/`Rnn`/`#issue`/`ADR`/`ANALYSIS` refs); the only rule there is that a
   change's version *tag* names the release it ships in. Release-to-release
   change history lives in the user-facing `CHANGELOG.md`. See
   [ADR-0029](decisions/ADR-0029-v2-release-versioning-doc-cleanliness.md).
   **Within the dev docs, kind decides:** a *record* (an adoption table, an
   index, a status log) states what is — correct it in place; *guidance* (this
   file, `CONTRIBUTING.md`, `decisions/README.md`) may keep history, and should
   where the wrong version was plausible enough that the rule alone would not
   stick. The test is whether the history changes what the reader **does**;
   flag narration that does not. See `CONTRIBUTING.md` §"Documentation".

## Evidence discipline — fact, or artifact of the measurement?

The principles above are about the **artifact**; this one is about **method**.
It is a failure this project has repeatedly paid for, in reviews as well as in
PRs. What makes it catchable is that the unverified thing is usually **the
instrument, not the subject** — the number is real, but it measures something
other than what the sentence says.

**Prefer a mechanical guard to vigilance** — principle 6 applied to claims
rather than to code. Where a claim can be pinned, pin it. This is for the rest.

**Tells that a measurement is an artifact rather than a result:**

1. **stderr discarded** where stdout is treated as data.
   `git show missing:path 2>/dev/null | tr -cd '\r' | wc -c` returns `0` — so
   does a genuine LF file. Worse than one bad number: a *set* of these can look
   coherent while some entries are failures, and that coherence is what stops
   the question being asked.
2. **unchecked tool state** — the tool is not showing what you assume. A
   shallow clone's boundary commit behaves exactly like a root commit
   (`git rev-parse --is-shallow-repository`); a stale working tree answers for
   a revision you did not ask about (`git show <ref>:<path>`, not `grep` over
   the checkout).
3. **"CI is green"** — a claim about *what ran*; a suite that silently shrank
   still reports `0 Failed`. **"It passes locally"** is the same tell mirrored:
   a test count without an environment is a claim about what ran with the
   *where* left out. A local harness broader than the real one — a `startup.m`,
   an `addpath` of the repo root, `genpath` — answers a question the gate never
   asks.
4. **an inferred relationship between two verified facts** — both line numbers
   right, the execution order between them never checked; the error identifier
   real, the overload it implied never confirmed to exist (#230, §1.3n).
5. **a statistic whose population was never stated** — "median 2, 52% wider
   than one" counted every overmapped variable, accumulators included, which is
   not the quantity the sentence claimed (#234, §2.5(c)).
6. **a negative result whose search space was narrower than the claim.**
   "I grepped and found nothing" answers the question you *typed*, not the one
   you asked. Distinct from tell 4 (there is one fact, not a relationship) and
   from tell 2 (the tool answered honestly — the *query* was under-specified).
   Before concluding *X is absent*, enumerate the forms X could take and check
   the pattern covers them: a dependency can be a filesystem call, a function
   that has to resolve on the path, or ambient state, and a pattern list built
   for one of those cannot express the others. Where the set can grow, prefer a
   **deny-list with a drift test** to an allow-list — an allow-list omits
   silently, which is the same failure with a longer fuse. (This is about
   *search coverage*, not about deliberate allow-lists: a deny-by-default
   security control like `docs/analyses/.gitignore` is correctly an allow-list.
   The tell there is different — it fails silently on the entry you forgot to
   write, so it needs a note saying so, which it now has.)

**A claim that will outlive the PR** — quoted into a document, a ROADMAP row, an
ADR — carries how it was measured, so the next reader can re-run it instead of
trusting it. `ANALYSIS.md` §2.5's *"To reproduce:"* is the shape.

### Instances (this project)

- **ADR-0019's O(n²) unrolled-stack figure**: quoted un-attributed into
  `CI_PLAN.md` REQ-T-10 and ADR-0033 §Context, did not reproduce, retracted from
  both (#216). `IScatterPrototypeTest` / `SGenericBoundFoldingTest` are live
  tests rather than `bench/` scripts so their figures cannot go the same way.
- **16 tests across 5 classes absent from the hosted gate**, across several PRs
  that treated them as covered because they were license-free (#235).
  `tests/ci_suiteGuard.m` is the mechanical answer.
- **A missing file read as an LF file** (tell 1) and **a shallow clone's
  boundary read as a root** (tell 2) produced opposite wrong conclusions about
  the same question in one review round (#237) — one author-side, one
  reviewer-side.

- **Tell 6, three times in one PR series (#240).** A reviewer grepped
  `adigatorReconstructCall.m` for `pwd`/`filesep`/`fullfile`/`exist` and
  concluded the CI failure was release-dependent rather than path-dependent —
  but the dependence was *function resolution* (`adigatorNormalizeEmbedMode`
  lives in `util/`, which the test never declared), which no pattern in that
  list could express. The same PR's signed-option **allow-list** silently
  omitted `auxdata` and `optoutput`: "the options I enumerated" is not "the
  options that exist". And "`adigator.m` is the tree's only CRLF file" survived
  several PRs because the per-PR checks were sound while the *global* claim was
  never searched for at all (`git ls-files --eol`, #237).
  `adigatorStampOptions`' inversion to a deny-list, plus the signed/printed
  drift test beside it, is this repo's own mechanical answer to that reasoning.
- **Tell 3 mirrored, and then the mirror itself misread (#240).** Unit and
  integration reported green locally while the hosted gate was red. The
  explanation given at the time — a `startup.m` supplying a path the test class
  had not declared, an `addpath(root)` harness masking it the way `genpath`
  does — was **wrong, and was never measured**: `util/` does not resolve under a
  plain `matlab -batch` in that tree, `ci_lint` leaks nothing, fixtures tear
  down cleanly, and restoring the pre-fix code reproduces the failure locally.
  The real cause was that the suite was not re-run after the final edits and
  the pre-push gate (ADR-0017) had never been armed in that clone — an unarmed
  hook is silent, so nothing said so (#245 makes `ci_lint` say it). Two true
  facts (a `startup.m` exists; an earlier local run was green) with an
  unverified relationship asserted between them: **tell 4 wearing tell 3's
  clothes**, and it survived a review round because it named a failure this
  repo really has had.

Review caught some of these, but late — after the claim had reached a merged
document or the PR body. A measurement is cheapest to check where it is taken.

## Terminology (enforce consistency)

- **Embed mode `c` / `l` / `i`** — classic / load / inline. Not to be confused
  with derivative *order* or with the `DerType` (`jacobian` / `gradient` /
  `hessian`).
- **`y.dX` / `y.dX_location` / `y.dX_size`** — the generated-file derivative
  outputs (contract C-2), distinct from the *wrapper* outputs (`Jac`, `Grd`,
  `Hes`) and from the exported CSC pattern metadata (`JacobianCSC` /
  `GradientCSC` / `HessianCSC`, the sole sparse-pattern representation — ADR-0030).
- **Unrolled Jacobian** — the `[prod(ysize) × prod(xsize)]` layout `y.dX`
  indexes into, distinct from the user-facing `m×n` Jacobian shape (C-1).
- **`Bn`** — a numbered bug in `ANALYSIS.md`. Reference fixes by `Bn`.

## Red flags

- **Contract drift** — wrapper output shape, `y.dX` layout, or Gator data
  semantics diverging from `DESIGN.md` §Contracts / `adigatorDerivativeConventions.m`.
  Those artifacts are authoritative; when code and contract disagree, *stop and
  ask* (don't pick a side).
- **Dimension-branch changes in `adigatorGenJacFile.m` / `adigatorGenHesFile.m`**
  — this is exactly where B7–B10 lived. Any edit here needs the shape-matrix
  test (`tests/integration/IShapeMatrixTest.m`, TS-I-01) exercised, including the
  `m ≠ n` vector-output Hessian and the remapped matrix-of-scalar /
  scalar-of-matrix cases.
- **Path / file-handle / global leaks** in the generators — `path()` must be
  restored on success *and* failure, all `fopen` handles closed (B13), no stray
  globals.
- **Silent behavioural breaks** — e.g. a gradient orientation change (`1×n` →
  `n×1`) that breaks existing caller code without a prominent note.
- **Down-casting `Data*`, or treating `embed_mode` with brittle char comparison**
  (`== 'c'` errors on `'classic'`; use `strncmpi`) — recurring bug shapes
  (B1, B11).
- **A bug fix without its regression test**, or a `KnownIssue` tag left on a
  test that now passes.
- **Dev-tracking in user-facing docs** (principle 8) — an `ADR-xxxx` / `PR #x` /
  `#issue` / roadmap `Rnn` / rev-date / `Bnn` / inline `ANALYSIS §` / `DESIGN §`
  citation woven into the user guide, `README`, `SHOWCASE.md`, or an emitted fragment; or a code-comment
  version tag that names a release other than the one the change ships in.

- **A guard whose failure direction is documented but not asserted** — a
  fallback that says which way it should fail when it cannot decide, with no
  test that puts it in that state. The happy path passing says nothing about
  the `catch`. Pin the *undeterminable* input, not just the good and the bad
  ones. This project has a lot of fail-direction reasoning — B39's refusal,
  #226's fail-closed declines, HZ-1's fallback, `cadaOverMapTargetNz`'s gate —
  and only some of it is asserted. The instance: #200's embed-mode guard stated
  in its own docstring that "a missing recipe is an inconvenience, a recipe that
  rebuilds a different file is the failure this whole header exists to avoid",
  and
  then implemented `catch → print the recipe`. It was not latent; it fired on
  CI and reproduced a defect that had already been fixed on the happy path, via
  the error path. Nothing tested the direction until an `'!!unrecognisable'`
  input was added.

## What to be lenient about

- Naming and prose polish in rationale docs (they're not contracts).
- Style inconsistencies inherited from the upstream codebase where the
  substantive behaviour is right — this is a fork of mature academic code.
- Missing tests on throwaway exploration; the bar is on shipped rules/branches.

## What to be strict about

- **A measurement asserted without its method** — especially one destined for a
  durable document (§Evidence discipline). Ask how it was taken, not just what
  it says.

- Anything touching a contract in `DESIGN.md` §Contracts or
  `adigatorDerivativeConventions.m`.
- Correctness of generated derivatives (principle 1) and cross-mode identity
  (principle 3).
- Embeddability invariants C-4 (principle 2).
- A fix landing without flipping/adding its pinning test (principle 6).

## Review output format

1. **Summary** — what the PR does; right direction? ready to merge?
2. **What works well** — brief.
3. **Issues to address before merge** — numbered; file/line; blocker vs.
   non-blocker; concrete suggested change; cite the contract (C-n) or principle
   (n) it touches.
4. **Follow-up suggestions** — non-blocking.
5. **Verdict** — approve / approve with changes / request changes. If CI didn't
   (or couldn't) run, say so: a review that didn't verify is validation-only and
   must be labelled as such.

## Tone

Small fork of mature academic code, developed largely by agents. Reviews are a
conversation, not a gate — "I'd do this differently but yours works too" is
legitimate. Be direct about blockers (anything under "strict" above); be
explicit about what's a nit. Quote the problematic text and propose concrete
replacement wording rather than just flagging.
