# ADiGator-embedded — Design

The *rationale* half of the documentation set: why the tool is shaped the way
it is. The binding output **contracts** are in [§Contracts](#contracts) below;
the requirement/test discipline is in [`CI_PLAN.md`](CI_PLAN.md); the bug and
optimization analysis is in [`ANALYSIS.md`](ANALYSIS.md). For the user-facing
manual see [`userguide/ADiGatorUserGuide.pdf`](userguide/ADiGatorUserGuide.pdf)
and the TOMS/CALGO papers in [`papers/`](papers/).

> Positioning: this file answers *"why is it shaped this way?"*. It is **not**
> a contract — when it touches a binding surface it links to [§Contracts](#contracts)
> rather than restating it. Below ~300 lines, the contracts live here as a
> section rather than in a separate `SPEC.md`; the project has a single
> implementation and no cross-language/process boundaries, so a standalone spec
> would be overhead (see [`SEED_ADOPTION_ANALYSIS.md`](SEED_ADOPTION_ANALYSIS.md) §3.2).

---

## Overview

ADiGator differentiates a MATLAB function by **source transformation via
operator overloading**. It runs the user's function once with the input
variables replaced by overloaded objects that, instead of computing numbers,
*record* each elementary operation and *print* the corresponding derivative
statement to a new `.m` file. The generated file, when later evaluated on real
numeric data, returns the function value together with the (sparse) derivative.

The result is a standalone derivative function with **statically known sizes
and sparsity** — no taping at run time, no symbolic engine. That static
character is what makes the embedded fork possible: a generated file can be
stripped of its runtime dependencies and handed to MATLAB Coder.

## Module structure

| Area | Responsibility |
|------|----------------|
| `adigator.m`, `adigatorOptions.m`, `adigatorCreate*Input.m` | Entry points: drive the overloaded evaluation pass and emit the derivative file. |
| `lib/@cada`, `lib/@cadastruct`, `lib/cadaUtils`, `lib/adigatorInput.m` | The transformation engine. `@cada` is the overloaded numeric class (one `classdef` carrying value size, sparsity, and derivative metadata); `@cadastruct` overloads structs/cells; `adigatorInput` (a single-file `classdef`) defines derivative/auxiliary inputs. The overloaded methods (`cadaunarymath`, `cadabinaryarraymath`, `mtimes`, `sum`, `subsref`/`subsasgn`, `horzcat`/`vertcat`, …) hold the derivative rules. |
| `util/` | User-facing generators that wrap `adigator`: `adigatorGenJacFile`, `adigatorGenHesFile`, the `adigatorGenFiles4{Fmincon,Fminunc,Fsolve,Ipopt,gpops2}` black-box helpers, and the compression utilities `adigatorColor` / `adigatorUncompressJac`. |
| `embedding/` | The embedded fork: `adigatorGenDerFile_embedded` (orchestrates pruning + emission), `prune_adigator_mat` (prunes/down-casts the Gator data struct), `structure_to_embed_mfile` (emits a data function from the Gator data struct), `adigator_patch_derivative` (rewrites the generated file for codegen), `updatestruct`. |
| `tests/`, `examples/`, `unit_tests/` | The `matlab.unittest` suite (`tests/{unit,integration,system}`, driven by `tests/ci_local.m`); worked examples (jacobians, hessians, stiff ODEs, optimization); and `unit_tests/test_unarymath_rules.m`, the legacy finite-difference rule harness the suite was built from. |

## The static tape

After the overloaded pass, the user program has been resolved into a *linear
sequence of primitive vectorized statements with fixed sizes and precomputed
constant index maps* — exactly what gets printed to the derivative file. All
control flow is either unrolled or reduced to rolled `for` loops with
per-iteration index tables. This "static tape" is the central design asset: it
is what lets the embedded pipeline emit fully static source, and it is the
structure a future reverse-mode emitter would walk backward (see
[`ANALYSIS.md`](ANALYSIS.md) §3).

## Embedded generation modes

`adigatorGenDerFile_embedded` produces three flavours of the same derivative,
selected by `embed_mode`:

- **`'c'` (classic)** — upstream behaviour: the generated file reads its
  constant index/data tables from a `.mat` via a `global` + runtime `load`.
- **`'l'` (load)** — codegen-friendly: no `global`; the `.mat` is read through
  `coder.load`, wrapped in `coder.const`.
- **`'i'` (inline)** — fully self-contained: the constant tables are emitted as
  source in a companion data function, so there is **no `.mat` and no
  `coder.load`** at all.

All three must return numerically identical results; that equivalence, and the
absence of `global`/`load`/`.mat` in the restricted modes, are binding
contracts (below) and pinned by tests (`CI_PLAN.md` REQ-T-04, TS-I-02).

## Why source transformation (vs. the alternatives)

Operator overloading *with code generation* keeps the per-call cost low (no
overloading at run time) while supporting MATLAB's array semantics and sparsity
natively — the things a tape-based or symbolic approach would either lose or
pay for repeatedly. The trade-off is a generation-time pass and a generated
artifact to manage; the embedded fork leans into that by treating the artifact
as a deliverable to be optimized and compiled.

## Contracts

The binding cross-surface conventions. Implementations must match these and
these must match the implementations; an automated check is named per rule
under `Verified by:`. The authoritative source for the derivative shapes is
[`adigatorDerivativeConventions.m`](adigatorDerivativeConventions.m); the layout
of the generated data is documented at length in the preamble of
[`ANALYSIS.md`](ANALYSIS.md).

### C-1 — Derivative output shapes

For a function `f: Rⁿ → Rᵐ` evaluated through the wrappers:

- **Gradient** of scalar `f` (`m = 1`): `n×1` (column).
- **Jacobian**: `m×n`.
- **Hessian** of scalar `f`: `n×n`.
- **Vector-function Hessian** (`m > 1`): `[m·n × n]` with row index
  `(x₁−1)·m + y`.
- Generalized matrix-input / matrix-output shapes follow the table in
  `adigatorDerivativeConventions.m`.

The `DER_LEVELS` option selects *which* of these outputs a wrapper returns but
**never changes the shape** of an emitted output, so this shape contract is
unaffected by it. Which outputs appear, in what order, and the selection
invariants are governed by **C-6**.

*Verified by:* `tests/integration/IShapeMatrixTest.m` (shape matrix; `CI_PLAN.md`
TS-I-01), `ISecondDerivTest` (TS-I-04), `ILevelSelectTest` (TS-I-05, output
selection). *Note:* several branches here had dimension bugs (`ANALYSIS.md`
B7–B10); see `ANALYSIS.md` for current status.

### C-2 — Generated-file evaluation interface

A generated derivative file returns the function value `y.f` and the derivative
nonzeros `y.dX`: the vector of possible nonzeros of the *unrolled* Jacobian
(size `[prod(ysize) × prod(xsize)]`, column-major on both sides), ordered by
ascending linear index. `y.dX_location` has one column per dimension listed in
`y.dX_size`.

*Verified by:* `CI_PLAN.md` TS-U-03 (structural ops vs. dense FD).

### C-3 — Gator data layout

In the generated data (`.mat` for `'c'`/`'l'`, source for `'i'`):
`Gator*Data.Index*` fields hold **index vectors**; `Gator*Data.Data*` fields
hold **numeric value constants used in arithmetic**. The two are *not*
interchangeable — integer down-casting applies to `Index*` only; `Data*` stays
`double` (see [ADR-0001](decisions/ADR-0001-downcast-index-fields-only.md), and
`ANALYSIS.md` B1, now fixed in `embedding/prune_adigator_mat.m`).

*Verified by:* `tests/unit/UPruneMatTest.m` (`CI_PLAN.md` TS-U-04) — `Data*`
stays `double` is a hard assertion (`dataFieldsStayDouble`).

### C-4 — Embed-mode invariants

`'l'` and `'i'` generated code contains no `global` declaration and no runtime
`load`; `'i'` additionally contains no `.mat` and no `coder.load`. All three
modes return numerically identical results.

*Verified by:* `CI_PLAN.md` REQ-T-04 / TS-I-02 (static text checks + cross-mode
numeric equality).

### C-5 — `norm` differentiability policy

Vector p-norms (`2`, `1`, `Inf`, `-Inf`, general `p`) and the Frobenius norm
(`'fro'`) are rewritten to elementary differentiable operations; the
induced/spectral matrix norms (which would require an SVD) raise a clear error
rather than returning a wrong derivative.

*Verified by:* `tests/unit/UNormTest.m`;
[ADR-0002](decisions/ADR-0002-norm-matrix-induced-errors.md).

### C-6 — Wrapper outputs: names, order, and level selection

This contract governs *what a generated derivative wrapper returns, named how,
and in what order* — one surface with three facets (the shapes themselves are
C-1).

**Names.** Each output uses a **canonical variable name, uniform across every
generator** (forward, reverse, and the matrix-free products), so the same object
is always called the same thing:

| object | name | | object | name |
|---|---|---|---|---|
| function value | `Fun` | | J·v (R18) | `Jv` |
| gradient | `Grd` | | Jᵀ·v | `Jtv` |
| Jacobian | `Jac` | | H·v (R18) | `Hv` |
| Hessian | `Hes` | | | |

(Three-letter capitalised abbreviations for the assembled objects; the product
names follow the same capitalised style. These names are positional in MATLAB —
a caller may rebind them — but the *generated signature* uses the canonical name
so docs, the comparison harness, and cross-mode reading stay consistent.)

**Order.** Outputs are **highest-derivative-order first, with the function value
`Fun` last**, for every derivative object:

- Jacobian: `[Jac, Fun]`  (gradient of a scalar is the `m = 1` Jacobian: `[Grd, Fun]`)
- Hessian: `[Hes, Grd, Fun]`
- Matrix-free products (R18): J·v → `[Jv, Fun]`, H·v → `[Hv, Grd, Fun]`, Jᵀ·v → `[Jtv, Fun]`

**Level selection (`DER_LEVELS`).** The `DER_LEVELS` option selects *which* of
those outputs a wrapper returns. The binding invariants — identical for **every**
generator, including the matrix-free products as they land:

- Levels are `0` = function value, `1` = first derivative (gradient/Jacobian),
  `2` = Hessian.
- The valid request set is `0..maxlevel`, where `maxlevel` is the highest level
  the generator produces (`1` for Jacobian/gradient, `2` for Hessian).
- The **top level is always returned** — a file must return the derivative it is
  named for; `DER_LEVELS` only chooses which *lower-order* companions accompany
  it.
- Default `[]` = all levels `0..maxlevel`, reproducing the historical signatures.
- Selection **preserves the order above and never changes an emitted output's
  shape** (C-1) — e.g. `der_levels = [1 2]` on a Hessian file ⇒ `[Hes, Grd]`;
  `[1]` on a Jacobian file ⇒ `[Jac]`.
- It is resolved **uniformly** by `adigatorResolveDerLevels(der_levels, maxlevel,
  caller)`; no generator may reimplement the policy.

**Known deviation:** the standalone reverse prototype deviates on **both name
and order** — it emits the value **first** and names outputs off the user's
output variable rather than canonically: `adigatorGenRevGradFile` →
`[<out>, <out>_grad]`, `adigatorGenJtVFile` → `[<out>, jtv]`. This predates the
contract; R16 brings the reverse path into full compliance — canonical names and
order, `[Grd, Fun]` / `[Jtv, Fun]`, honouring `DER_LEVELS` — when reverse gains
embed-pipeline parity
([ADR-0016](decisions/ADR-0016-matrix-free-products-efficiency-path.md)).

*Verified by:* `tests/integration/ILevelSelectTest.m` (`CI_PLAN.md` TS-I-05,
`DER_LEVELS` selection across generators); the order is exercised by every test
that consumes the wrappers positionally (`IShapeMatrixTest`, `IEmbedModesTest`).
Rationale in [ADR-0005](decisions/ADR-0005-der-levels-output-selection.md)
(roadmap R7a, issue #21). R16 adds a reverse cross-mode order check.

## Constraints

- **Minimum release R2022a** — the embedding layer uses `arguments` blocks
  (R2019b+), `readlines`/`writelines` (R2022a+), and string arrays. See
  [ADR-0003](decisions/ADR-0003-r2022a-minimum-release.md).
- **GPLv3** — inherited from the Weinstein/Rao upstream (`docs/COPYING.txt`).
  New dependencies must be licence-compatible.
- **Octave is not viable today** without a deliberate compatibility layer
  (the three features above plus heavy `classdef` `subsref`/`subsasgn`
  dispatch); see `CI_PLAN.md` §0.

## Future directions

Reverse-mode differentiation (O(1) gradient sweeps for `f: Rⁿ → R`), generated-
code size/allocation optimizations for embedded targets, and a triplet/CSC
output mode are analysed in [`ANALYSIS.md`](ANALYSIS.md) §§2–3 with staged,
trigger-gated plans.
