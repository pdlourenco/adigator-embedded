# ADR-0030 — CSC as the sole sparse-pattern contract (`der_output ∈ {matrix, csc}`)

## Status

Accepted — 2026-07-24 (maintainer proposal, issue
[#192](https://github.com/pdlourenco/adigator-embedded/issues/192)). A
**pre-v2.0-release breaking change**: v2.0 is cut in-repo ([ADR-0029](ADR-0029-v2-release-versioning-doc-cleanliness.md),
CHANGELOG 2026-07-11) but not tagged or announced, so the API may still break
without compatibility aliases. **Partially supersedes [ADR-0022](ADR-0022-generalized-der-output-nonzeros.md)**: the
`'nonzeros'` form spelling, the `*Locs` family, the `*Structure` public
fields, and the `jac_output` alias are replaced; ADR-0022's "decision b"
(top-order-output selection, no cross-sync) and the C-2/C-3 data/pattern
split are **unchanged**. Binds `DESIGN §Contracts C-6` (output-form facet),
restates `REQ-T-03` and respells `REQ-T-11`'s form clause **when the implementation PR lands** (roadmap
**R31**) — until then the shipped behavior is the ADR-0022 `'nonzeros'`
surface and the docs continue to describe it (the no-misdescription rule,
per the ADR-0023-revision precedent). Contract-first in one PR per
`CLAUDE.md` §3: `DESIGN`/`adigatorDerivativeConventions.m`/`CI_PLAN` flip
together with the code and tests.

## Context

The v2.0 sparse output surface exposes the same structural pattern three
ways: an `nnz×2` coordinate array (`output.JacobianLocs`/`HessianLocs`), a
MATLAB `sparse` pattern matrix (`output.JacobianStructure`/
`HessianStructure`), and the implicit ordering of the `der_output='nonzeros'`
runtime value vector. Three representations of one fact invite drift (the
value order silently diverging from the exported pattern is a principle-1
hazard), cost `2·nnz` indices plus a duplicate sparse object where
`nnz + ncols + 1` suffice, and none of them is what an embedded sparse
solver consumes. Embedded consumers want compressed sparse column:
`col_ptr[ncols+1]` + `row_idx[nnz]` constant at generation time, `values[nnz]`
at runtime — mappable straight into CSC kernels or a generated KKT matrix
with no coordinate expansion, no `sparse()` construction, and no runtime
sorting.

The native value order is already CSC-compatible. The documented raw
Jacobian stream is the possible-nonzeros vector ordered by ascending MATLAB
linear index of the unrolled Jacobian — i.e. column-major with rows
ascending within each column: exactly CSC value/row order. The only missing
artifact is the column-pointer vector.

**Ordering status per DerType** (verified by code reading; the canonicalizer
still validates rather than assumes, per the Decision):

- **Jacobian** — identity by the documented linear-index ordering of
  `deriv.nzlocs`.
- **Gradient** — the `'Grd'` path stores the derivative as the `1×n`
  Jacobian of a scalar (locs `(1, j)`, sorted by `j`); the returned `Grd` is
  `n×1` (C-1). `GradientCSC` maps `(1,j) → (j,1)`: a single column,
  `ColPtr = [1, Nnz+1]`, `RowIdx` = the old column indices — ascending by
  the same ordering, so identity on the value order. This removes the
  current indirection where a column-vector gradient's positions are read
  through Jacobian *column* coordinates.
- **Hessian (incl. the `[m·n × n]` vector fold)** — identity, by this
  chain: `dydxdxlocs = adiout2.d<vod>.deriv.nzlocs` is sorted by the linear
  index of the `[nnz1×n]` second-derivative unroll — the C-2
  ascending-linear-index ordering applied to the second differentiation
  pass (a documented contract, not an independently checked fact; the
  canonicalizer validates it), i.e. by `(dydxdxlocs(:,2),
  dydxdxlocs(:,1))` = (Hessian column, first-derivative-nonzero index); and
  `HesRow = (HesLocs1(:,2)-1)·m + HesLocs1(:,1)` is precisely the Jacobian
  linear index at `dydxdxlocs(:,1)`, which is ascending in that index
  because `dydxlocs` is itself linear-index-sorted. Hence within each
  Hessian column, `HesRow` is strictly increasing: native order is CSC
  order. The remap cases (B23 territory: matrix-of-scalar via `HesOutSize`,
  scalar-of-matrix) must be *validated*, not assumed — they are exactly
  where ordering assumptions have broken before.

## Decision

1. **One option, two values.** `der_output ∈ {'matrix', 'csc'}` for every
   supporting generator. `'nonzeros'` and the `jac_output` alias are
   **removed** (no public compatibility spelling; a private in-repo alias
   may exist only transiently inside the migration PR). `der_output` keeps
   ADR-0022's decision-b semantics: it selects the **top-order output**
   only; a Hessian file's `Grd` companion is unaffected.

2. **CSC is the sole public pattern representation, in both modes.** The
   generation result exposes, per derivative role:

   ```matlab
   output.JacobianCSC | output.GradientCSC | output.HessianCSC
       .Size      = [nrows, ncols]      % the returned derivative's shape (C-1)
       .ColPtr    = uint32[ncols+1]     % ColPtr(1)==1, ColPtr(end)==Nnz+1, monotone
       .RowIdx    = uint32[Nnz]         % in [1,nrows]; strictly increasing per column
       .Nnz       = double scalar       % structurally possible nonzeros
       .IndexBase = 1
   ```

   Binding invariants: column `j`'s entries occupy
   `k = ColPtr(j):ColPtr(j+1)-1` with `rows = RowIdx(k)`; locations unique;
   empty columns are adjacent equal pointers; runtime values may be zero
   (structural pattern is a superset — the REQ-T-03 property restated).
   `JacobianLocs`/`HessianLocs`/`JacobianStructure`/`HessianStructure` are
   **removed as public fields**. In `'matrix'` mode the CSC metadata
   describes the returned matrix's structure; in `'csc'` mode it
   additionally defines the returned value order.

3. **CSC mode returns values only.** `[Jac, Fun] = f_Jac(x, …)` returns the
   `Nnz×1` value vector in CSC order (C-6 role names unchanged; generated
   help text states the representation). The generated procedure must not
   return `ColPtr`/`RowIdx` per call, call `sparse`, allocate a dense
   derivative, scatter through locations, or sort/search coordinates at
   runtime.

4. **Index class policy.** `uint32` for `ColPtr`/`RowIdx`, guarded by an
   explicit range check (`Nnz+1` and `nrows` ≤ `intmax('uint32')`) — the
   same 2³²-assumption-with-a-guard posture ANALYSIS §1.5 adopted for the
   `Index*` down-cast (and the M7 guard precedent): silent saturation is a
   principle-1 wrong-gather, so out-of-range falls back to `double` with a
   warning rather than saturating.

5. **Canonicalizer, used by every generator.**
   `[csc, perm, isIdentity] = adigatorBuildCSC(size_, locations)` in
   `util/`: validates integer in-range locations, rejects duplicates,
   orders by (column, row), builds `ColPtr` (empty columns included) and
   sorted `RowIdx`, and returns the generation-time permutation from the
   native value order to CSC order plus an identity flag. Generators
   **validate** ordering through it; where a non-identity permutation
   arises (expected: none for Jacobian/gradient/Hessian per Context; the
   remap cases are the watch item) the wrapper applies a **constant
   gather** — never runtime sorting. Longer term the printer should emit
   values directly in CSC order so even the gather disappears.

6. **Host-only reconstruction helpers** (convenience, never embedded
   dependencies): `adigatorCSCToLocs(csc)`,
   `adigatorCSCToSparse(csc, values)` (pattern via
   `adigatorCSCToSparse(csc, ones(csc.Nnz,1))`).

7. **Orientation.** `GradientCSC.Size = [n,1]` (the returned convention,
   not the internal `1×n`). `HessianCSC` describes the full existing output
   (scalar `n×n`; vector `[m·n, n]` fold; remap cases the documented
   displayed shape). **No** silent switch to triangular storage — symmetric
   compression is a future, separately-contracted option.

## Alternatives considered

- **Add CSC alongside `'nonzeros'`/`*Locs`/`*Structure`.** Rejected: leaves
  v2.0 with four overlapping pattern contracts forever; the pre-release
  window exists precisely to avoid permanent aliases.
- **CSR.** Rejected: MATLAB's native order (and the generated value stream)
  is column-major; CSC gets the identity permutation, CSR would force a
  permutation everywhere; MATLAB's own sparse internals are CSC.
- **0-based `IndexBase` (C-friendly).** Rejected for the MATLAB-facing
  contract; `IndexBase` is exported explicitly so a C consumer can shift
  once at integration time, and a future direct-C emitter can negotiate
  base without changing this contract.
- **Triangular symmetric Hessian now.** Rejected: needs its own
  derivative-computation and symmetry contract; scoped out to keep the
  break minimal.
- **Keeping `*Structure` as a derived convenience field.** Rejected:
  reconstruction is one helper call; a second exported copy is exactly the
  drift channel being closed.

## Consequences

- **Breaking (pre-release only):** option values `{matrix, nonzeros}` →
  `{matrix, csc}`; `jac_output` removed; `*Locs`/`*Structure` removed;
  `*CSC` metadata added in both modes. Every consumer migrates in the same
  PR (census in the R31 row / issue #192 plan): `adigatorOptions`,
  `adigatorGenJacFile`, `adigatorGenHesFile`, `IOutputModesTest` (TS-I-12),
  `IShapeMatrixTest` structure assertions, `oracleSparsitySuperset`
  (REQ-T-03 oracle — reconstructs via the helper), `oracleDerOutputInvariance`
  (R27 axis), `MCSmokeTest`, `mcGenClassic`, `SExamplesTest`, the
  arrowhead/brusselator/burgers examples, README + user guide + PDF,
  `REVIEW_CONTEXT` terminology, the C-6 text here and in
  `adigatorDerivativeConventions.m`, the **CHANGELOG `[2.0]` output-forms
  bullet** (v2.0 is untagged — the entry must describe the CSC surface), and
  a dev-doc terminology sweep (e.g. ANALYSIS §2's live `jac_output` mention).
- `REQ-T-03` is restated onto CSC (superset property + placement
  consistency, now via reconstruction); `REQ-T-11`'s form clause is
  respelled. New tests: `UBuildCSCTest` (TS-U-20, canonicalizer + invariants)
  and `ICscOutputTest` (TS-I-25, end-to-end incl. the acceptance-criteria
  shape coverage and loopbound-at-`n<Nmax`).
- Scope follows issue #192 §Scope verbatim (in: Jacobians/gradients/Hessians
  incl. the vector fold, classic + inline modes, `der_levels` interplay,
  fixed structural sparsity with runtime zeros, empty/degenerate patterns,
  the shape-matrix conventions; out: triangular symmetric compression,
  **runtime-changing sparsity**, runtime MATLAB-sparse construction in embed
  mode, direct C output, k≥3 tensors without a defined 2-D fold).
- The Coder acceptance item (fixed-size outputs, no dynamic allocation in
  `'csc'` mode) rides REQ-T-05/TS-S-02's existing codegen gate; the bench
  acceptance item (evaluation cost vs metadata size vs downstream assembly)
  is R31 phase C.
- R25 phase 2's *form* axis is subsumed by this ADR; its **per-level
  selection** and option×DerType×mode matrix remain deferred, unchanged.
- The R27 `oracleDerOutputInvariance` axis becomes the regression harness
  for the migration (matrix-vs-csc reconstruction equality at fuzz scale).

**Revisit when:**

- Symmetric (triangular) Hessian storage is wanted — new ADR: symmetry
  contract + unique-triangle ordering.
- Higher-order (k≥3, ADR-0020) native output lands — a separately named
  tensor/coordinate representation, not "CSC" for an arbitrary tuple list.
- A direct-C emitter negotiates `IndexBase = 0`.
- The printer learns to emit values natively in CSC order (retires the
  constant-gather fallback path).
