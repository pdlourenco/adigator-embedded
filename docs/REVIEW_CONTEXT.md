# ADiGator-embedded — Reviewer Context

Seeds a reviewer (agent or human) with what this project actually cares about,
so a review is judgment against principles and contracts — not surface lint.
Point the reviewer at [`DESIGN.md`](DESIGN.md) (architecture + Contracts),
[`CI_PLAN.md`](CI_PLAN.md) (requirements/tests), [`ANALYSIS.md`](analyses/ANALYSIS.md)
(known bugs B1–B14 and optimization notes), and this file before a review.

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
7. **GPLv3 hygiene.** The project is GPLv3 (`docs/COPYING.txt`). A new
   dependency's licence must be compatible and declared.

## Terminology (enforce consistency)

- **Embed mode `c` / `l` / `i`** — classic / load / inline. Not to be confused
  with derivative *order* or with the `DerType` (`jacobian` / `gradient` /
  `hessian`).
- **`y.dX` / `y.dX_location` / `y.dX_size`** — the generated-file derivative
  outputs (contract C-2), distinct from the *wrapper* outputs (`Jac`, `Grd`,
  `Hes`) and from the sparsity metadata (`JacobianStructure` /
  `HessianStructure`).
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

## What to be lenient about

- Naming and prose polish in rationale docs (they're not contracts).
- Style inconsistencies inherited from the upstream codebase where the
  substantive behaviour is right — this is a fork of mature academic code.
- Missing tests on throwaway exploration; the bar is on shipped rules/branches.

## What to be strict about

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
