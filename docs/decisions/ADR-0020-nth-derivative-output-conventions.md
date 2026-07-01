# ADR-0020 — Higher-order (n-th) derivative output conventions

## Status

Accepted — 2026-07-01 (issue #85). Ratified by the maintainer; the order-`k`
convention below now **binds** `DESIGN §Contracts C-1` and
`adigatorDerivativeConventions.m` (the binding restatement lands in this PR). The
row order is *derived* from derivative-vector/matrix **multiplication
compatibility** (Decision 2 + 6), not free-chosen. Implementation — the
`'nth-derivative'` `DerType` + `n` option, the `Der{k}` outputs, and the
host-side `dvp`/`unfold` utilities — is roadmap **R22**: the convention binds
now and each staged slice lands its `Verified by:` test as it is built
(Decision 5).

## Context

The fork exposes only 1st order (`jacobian`/`gradient`) and 2nd order
(`hessian`). Issue #85 asks for arbitrary order via a new `DerType`
`'nth-derivative'` + an order option `n`. Per the maintainer's decision
(#85, 2026-07-01) the **specification comes first**: define the order-`n`
output convention, then implement.

Two facts frame the decision:

- **The mechanism already exists.** The Hessian is built by *re-differentiating
  the gradient* (`adigatorGenHesFile`: `adigator(fn,…,ADiGrd)` then
  `adigator(ADiGrd,…,ADiHes)`, gradient kept re-differentiable, B6). So order-`n`
  = chain `n` re-differentiation passes. The embed/strip side is already
  order-generic (PR #81 strips the *recursive* `_size`/`_location` metadata for
  any order — verified on a synthetic 3rd-order pattern). **The gating item is
  the convention, not the machinery.**
- **The native representation already generalizes.** A generated file returns
  the *vector of possible nonzeros of the unrolled derivative*, with
  `y.dX_location` carrying **one column per dimension** (C-2). Each derivative
  order simply adds a dimension. So the *native* order-`n` form needs no new
  theory; the open question is the **wrapper's user-facing shape**.

Current conventions (`adigatorDerivativeConventions.m` + C-1) define shapes only
through 2nd order: gradient `N×1`, Jacobian `M×N`, Hessian `N×N`, vector-function
Hessian `[M·N × N]` with row `(x₁−1)·M + y`, and the generalized
matrix-function-of-matrix-variable table (1st order). Order `n` has no fold, and
the difficult mixed cases (derivative of a vector function of a matrix variable,
etc.) have no convention.

Notation below — **`n` is the requested top order** (the `'nth-derivative'`
option) and **`k` a general order `1..n`**; `x` is the variable of
differentiation with `N = numel(x)` unrolled elements (`N = n·m` for a matrix
variable, `n·m` here being the variable's *shape*, not the order); `f` has
`M = numel(f)` unrolled elements (`M = r·c` for a matrix output). The `k`-th
total derivative `Dᵏf` has entries indexed by `(i; j₁,…,j_k)` — output
`i ∈ 1..M`, derivative variable `j_ℓ ∈ 1..N` — and is **symmetric** under any
permutation of `j₁,…,j_k`.

## Decision

**1 — Native (default) form: nonzeros + exported pattern, generalizing C-2.**
The order-`n` derivative is returned as the vector of possible nonzeros of the
unrolled order-`n` derivative, with `y.dX_location` carrying `n+1` columns (output
+ `n` derivative dims) and a pattern exported once via the `der_output='nonzeros'`
/ `*Locs` family (issue #84). This is the **default for `k ≥ 3`**, because the
dense object has `M·Nᵏ` entries — impractical to materialize. (This ties #85 to
#84: nonzeros-for-all is a hard prerequisite for usable higher order.)

**2 — Dense fold, defined by vec-in / unvec-out.** Requiring the emitted
derivative to support a multiplication by a vectorized operand whose result
unvectorizes to the function's shape fixes: the variable is consumed
**column-major** (`vec(x)` = the `N = numel(x)` index, `N = p·q` for a `p×q`
variable) indexing the **columns**; the output is produced **column-major** (the
`M = numel(f)` output block in `vec(f)` order, `M = r·c`) so
`reshape(result, size(f))` recovers `f`. The `k`-th derivative folds by
**column-major linearization of `T[i, j₁,…,j_k]` with `i` fastest and the last
derivative dim as columns**:

>   **size = `[M·Nᵏ⁻¹ × N]`,  `col = j_k`,  `row = i + (j₁−1)·M + (j₂−1)·M·N + … + (j_{k−1}−1)·M·Nᵏ⁻²`**
>   (equivalently `row − 1 = (i−1) + Σ_{ℓ=1..k−1} (j_ℓ−1)·M·Nˡ⁻¹`).

Reductions (unchanged): `k=1` → `row = i` → `[M×N]` **Jacobian**; `k=2` →
`row = (j₁−1)·M + i` → `[M·N × N]` **vector-Hessian**; scalar `f` → `[N×N]`
**Hessian**; scalar-function **gradient** keeps `N×1`. The ordering is chosen
(Decision 6) so contracting `col` is a plain `G·V` and the residual is the
next-lower fold under a bare `reshape` — no permutation.

**3 — Symmetry is an efficiency follow-on, not a correctness requirement.** `Dᵏf`
is symmetric in `j₁,…,j_k`, so only `C(N+k−1, k)` distinct index-tuples exist
(vs `Nᵏ`). The nonzeros form **may** deduplicate to the unique upper-simplex
tuples; the dense form materializes the full symmetric object. Deduplication is
a later optimization — the first cut emits the full (redundant) set.

**4 — C-6 naming.** The `k`-th derivative output variable is `Der{k}` for
`k ≥ 3` (`Grd`/`Jac` keep `k=1`, `Hes` keeps `k=2`); an `'nth-derivative'` file
returns `[Der{n}, …, Hes, Grd, Fun]` — highest order first, `Fun` last —
`der_levels`-selectable, consistent with C-6. (The exact spelling `Der3` vs a
generic accessor is a ratification detail.)

**5 — Staged operand coverage** (build in this order; each stage locks its slice
of the convention + a `Verified by:` test):
1. **scalar `f`, scalar `x`** (`N=M=1`): `Dᵏ = 1×1` for all `k` — validates the
   chain end-to-end.
2. **any `f`, scalar `x`** (`N=1`): the variable dim is always 1, so `Dᵏ` keeps
   `f`'s shape (`[M×1]`).
3. **scalar `f`, vector `x`** (`M=1`): gradient `N×1`, Hessian `N×N`,
   `Dᵏ = [Nᵏ⁻¹ × N]` dense / nonzeros-default for `k ≥ 3`. First place the fold
   and symmetry bite.
4. **vector `f`, vector `x`**: `[M·Nᵏ⁻¹ × N]`.
5. **matrix variable / matrix output** — *derived, not bespoke*: inputs enter as
   `vec(x)` (column-major `p·q → N`), outputs return by `unvec` to `f`'s `r×c`,
   per Decision 2. Only the *cosmetic* human display of a folded block is open,
   not the indexing.

**6 — Derivative–vector/matrix multiplication + N-D unfold (host utilities).** The
convention must support multiplying an *emitted* derivative by a vectorized
operand and recovering `f`'s dimensions — motivated by the Taylor step
`F(x₀+dx) = Σ_k (1/k!)·Dᵏf·(dx)^{⊗k}`, stated generally as **multiplication
compatibility**, not pinned to Taylor.
- **`dvp(D, V)`** — derivative–vector/matrix product; `V` is `N×s` (`s=1` vector,
  `s>1` batched directions). Contracts the trailing (`col`) dim:
  `G·V = [M·Nᵏ⁻¹×N]·[N×s] → [M·Nᵏ⁻¹×s]`, order drops by one. Under Decision 2's
  ordering the residual **for a single direction (`s=1`)** is the order-`(k−1)`
  fold via a bare `reshape`, so repeated `dvp` is a **permute-free
  multiply→reshape** recursion (the `s>1` result is a batch, not one fold). Callers: Taylor
  term = `dvp` ×k with the same `V` scaled `1/k!`; directional derivative = `dvp`
  on the Jacobian; Hessian·vector = `dvp` on the Hessian. `unvec` =
  `reshape(·, size(f))` (output block stays `vec(f)`-ordered throughout).
- **`unfold(D)`** — N-D inspection view: `reshape`+`permute` to `[M×N×…×N]` so
  individual `∂fᵢ/∂x_{j₁…j_k}` are addressable; nearly free given #84's `*Locs`.
- **Storage stays the flat fold** (Embedded-Coder-clean); `dvp`/`unfold` are
  host-side only — no N-D-tensor cost on target.
- **vs R18:** `adigatorGenHvpFile`/`adigatorGenJvFile` (ADR-0016) are *matrix-free*
  (never form the derivative). `dvp` contracts an **already-emitted** object —
  companion, not duplicate.

Lands as: this ADR (the specification). On acceptance (now), `C-1` +
`adigatorDerivativeConventions.m` gain the binding order-`n` restatement (this
PR). The `'nth-derivative'` `DerType` + `n` option, the `Der{k}` C-6 names, the
host-side `dvp`/`unfold` utilities (Decision 6), and per-stage tests (analytic
n-th-derivative of a scalar polynomial + FD + shape asserts) are the
implementation, roadmap **R22** (issue #85). The dense fold and nonzeros default depend on #84
(the `der_output`/`*Locs` generalization); Hessian-nonzeros (#84 phase 1) is the
concrete prerequisite.

## Consequences

- **Easier:** order-`n` reuses the existing re-differentiation chain + the
  order-generic embed/strip; the native nonzeros form needs no new theory; the
  dense fold is a strict generalization of shipped rules (no re-spec of 1st/2nd
  order); staging keeps each cut small and test-pinned.
- **Harder / constrained:** the dense form is `M·Nᵏ` — nonzeros is mandatory in
  practice for `k ≥ 3`, so #84 is a hard dependency; symmetry dedup is deferred,
  so early higher-order output is redundant; the matrix-variable/output fold at
  order `n` is only fully specified as staging reaches it (Decision 5 stage 5) —
  deliberately, to avoid over-specifying ahead of a test.
- **Revisit if:** the row order is now *derived* from multiplication
  compatibility (Decision 6), so the earlier "different fold" divergence is
  closed; revisit only if a consumer needs a contraction other than "trailing
  dim = the multiplied dimension," or if symmetry dedup should become the default.

## Alternatives considered

- **Dense `[M × Nᵏ]` (output rows, all derivative dims as columns).** Rejected:
  it does *not* match the shipped Hessian (`[M·N × N]`, not `[M × N²]`), so it
  would re-spec 2nd order and break C-1 continuity. The chosen "last dim =
  columns, rest fold into rows" is the unique generalization consistent with both
  Jacobian and vector-Hessian.
- **Full symmetric tensor materialization as the default.** Rejected as the
  default: `Nᵏ` is impractical; nonzeros-primary (Decision 1) is the only
  scalable default. Dense stays available for small cases.
- **Symmetry-deduplicated nonzeros as the *first* cut.** Deferred, not rejected:
  correct output first (full set), dedup as a measured optimization — avoids a
  subtle index bug in the load-bearing derivative path (REVIEW_CONTEXT
  principle 1) before there is a passing baseline to diff against.
- **A single generic `Dn` accessor instead of `Der{k}` names.** Left as a
  ratification detail under Decision 4; the `[highest … Fun]` order and
  `der_levels` selection are fixed regardless.
