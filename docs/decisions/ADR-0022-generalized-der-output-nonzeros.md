# ADR-0022 — Generalized derivative output form (`der_output` + `*Locs`) across DerTypes

## Status

Accepted — 2026-07-01 (issue #84). Ratified by the maintainer; the generalized
output-form convention now **binds** `DESIGN §Contracts C-6` (a fourth facet)
and extends **C-2** (the binding restatement lands in this PR; **C-3 needs no
change** — it governs the `Index*`/`Data*` downcast layout, orthogonal to output
form). Implementation is roadmap **R25**, Hessian-nonzeros first (the R22/#85
prerequisite); each phase lands its `Verified by:` test.

**Update — R25 phase 1 shipped (#99, "decision b").** As implemented,
`der_output` selects the form of each generator's **top-order output only** (a
Hessian file's `Grd` companion stays dense regardless); `jac_output` is kept as
a **level-1-only alias with no cross-sync** — it never flips a Hessian. Genuine
per-derivative-level selection (Decision 1's "per level") and the
`(der_output × DerType × mode)` matrix (Decision 3) are **deferred to R25 phase
2**. Phase 1 shipped Hessian-nonzeros + `HessianLocs` + the `Jac→Grd`
forward-gradient name fix, verified by `IOutputModesTest` (`CI_PLAN.md` TS-I-12).

## Context

The output-form option grew incrementally and applies **unevenly** across
DerTypes and modes:

- **`jac_output ∈ {matrix, nonzeros}`** lives in `util/adigatorGenJacFile.m`,
  which generates **both** the Jacobian (`NameAppendix='Jac'`) and the
  **gradient** (`'gradient'` routes through `adigatorGenJacFile(...,'Grd')`). So
  `nonzeros` already applies to the **Jacobian and the gradient** — the nonzeros
  branch emits `… = y.dx(:)` for either (verified end-to-end under ERT,
  `numErr=0`).
- **Missing nonzeros form:** the **Hessian** (`adigatorGenHesFile` computes the
  second-order locations `dydxdxlocs` internally but **every branch projects to
  dense** — `Hes = zeros(...)`); **reverse-grad / `JtV`** (return a
  vector/product); and **n-th order** (#85).
- **Naming deviation (confirmed live, fixed in phase 1):** the forward gradient
  (`'gradient'` → `adigatorGenJacFile(...,'Grd')`,
  `embedding/adigatorGenDerFile_embedded.m:122`) returns its first output named
  literally `Jac`, **not** the C-6 `Grd` — `jacOut = {'Jac'}` is unconditional
  (`util/adigatorGenJacFile.m:219`) and nothing renames it downstream (the
  `'Grd'` appendix sets only the file *name*). This holds in **every** output
  form (matrix *and* `nonzeros`), so it is broader than the `nonzeros` branch and
  is a *live* C-6 name-facet deviation today — cosmetic (callers consume the
  output positionally, so numerics are unaffected), but a real contract drift.
  Phase 1 fixes it (maintainer disposition on PR #95: fold into R25 phase 1).
- **Value.** `nonzeros` (nonzero vector + pattern exported once, no per-call
  dense projection) pays off where the derivative is **sparse**: the **Hessian**
  (`n×n` or vector-function `[m·n × n]`, frequently very sparse) is the biggest
  concrete win, and for **n-th-order tensors** (#85) it is *essential*, not
  optional — the dense object is `Nᵏ`. The two issues are coupled.
- **Contract surface.** The nonzeros form + exported constant pattern is
  currently contracted **only for the Jacobian** (C-2's `y.dX` interface; the
  `output.JacobianLocs` pattern exported by `adigatorGenJacFile`); C-6 governs
  wrapper names/order/levels but not an
  output *form*. Generalizing it is a contract change (C-2 / C-3 / C-6 family)
  with no doc presence today.

## Decision

**1 — One generalized option `der_output`, not per-type options.** Replace the
Jacobian-specific `jac_output` with a single derivative-form option
**`der_output ∈ {matrix, nonzeros}`** applied **per derivative level**, backed
by a **`*Locs` family** — `HessianLocs` as the `JacobianLocs` analog, and one
per DerType that gains a nonzeros form — exporting the constant sparsity pattern
once (consistent with the C-2/C-3 data/pattern split). `jac_output` stays as a
**back-compat alias** for the first-derivative level. Rejected the alternative
of per-type options (`hes_output`, …) as option sprawl. *(Narrowed at
implementation — see the Status "decision b" update: `der_output` flips the
top output only and per-level selection is deferred.)*

**2 — Treat it as a contract change (C-6 + C-2; C-3 unchanged).** On
ratification:
- **C-6** gains an *output-form* facet: alongside names/order/levels, each
  wrapper's outputs may be emitted in `matrix` or `nonzeros` form per
  `der_output`, with the `*Locs` pattern companion.
- **C-2** extends the "vector of possible nonzeros + exported pattern"
  statement from the Jacobian to **every DerType that supports nonzeros**, the
  `*Locs` tuples carrying one column per dimension (which is exactly what lets
  the higher-order `*Locs` of ADR-0020 drop in).
- **C-3 needs no change** — it governs the `Index*`/`Data*` downcast layout,
  orthogonal to output form.

**3 — N/A cells are an explicit, documented design choice.** Publish an
**option × DerType × mode matrix** (DESIGN + README) with the N/A cells *named*,
so "unsupported" is a decision, not an accident. Known N/A / trivial cells:
`classic + slim` (classic returns before the slim pass); `nonzeros` of a dense
gradient (trivially the vector); `nonzeros` of reverse-grad / `JtV` (already a
vector/product — N/A or the result itself).

**Phasing** (each phase locks its slice + a `Verified by:` test):
1. **`nonzeros` for the Hessian (`HessianLocs`)** — the highest-value concrete
   gap **and** the hard prerequisite for R22 (#85) being usable at `k ≥ 3`. The
   locations already exist internally (`dydxdxlocs`), so this is a new emit
   branch over an existing computation, not new sparsity theory. Fix the
   confirmed-live `Jac`→`Grd` forward-gradient naming deviation in the same
   change — emit the canonical output name per `NameAppendix` + a C-6
   name-assertion test.
2. **Audit + document** the full option × DerType × mode matrix (the table),
   N/A cells named.
3. **Fill** the remaining sensible gaps.

Lands as (on ratification): the `der_output` option + `*Locs` family; the
C-2/C-3/C-6 restatement; the option matrix table (DESIGN/README); the Hessian
nonzeros emit branch + the `Jac`→`Grd` naming fix; a `Verified by:` test
(`HessianLocs` nonzeros reconstructs the dense Hessian vs dense FD, the
`TS-U-03` analog). Roadmap **R25** (issue #84). Hessian-nonzeros (phase 1) is
the concrete prerequisite noted on R22.

## Consequences

- **Easier:** unblocks R22 (#85) — nonzeros is mandatory for `k ≥ 3`; the option
  surface becomes **uniform and documented** (the matrix table kills "does this
  option apply here?" ambiguity); the `*Locs` family is consistent with the
  existing C-2/C-3 pattern/data contracts, so higher-order `*Locs` is a straight
  generalization.
- **Harder / constrained:** `adigatorGenHesFile` today *always* projects to
  dense — adding a nonzeros branch touches the load-bearing second-order
  location path (mitigated: `dydxdxlocs` already exists, and the phase-1 test
  diffs against the shipped dense output, giving a baseline per REVIEW_CONTEXT
  principle 1); the `Jac`→`Grd` naming fix edits the *shipped* gradient path, so
  it needs its own assertion; the option matrix must be kept honest as
  DerTypes/modes evolve.
- **Revisit if:** a DerType needs a third output form beyond `{matrix,
  nonzeros}` (e.g. a compressed/CSC layout); or the N/A matrix turns out to have
  a cell users actually want (promote it from N/A to supported).

## Alternatives considered

- **Per-type options (`hes_output`, `grad_output`, …).** Rejected: option
  sprawl, inconsistent defaults, and harder to compose with `embed_mode` /
  `slim_embed` / `der_levels`; a single `der_output` + `*Locs` family is cleaner
  and mirrors the C-2/C-3 pattern/data split.
- **Leave the Hessian dense-only; add nonzeros only when R22 (#85) lands.**
  Rejected: the Hessian is the highest-value sparse case on its own, and R22
  needs exactly this machinery — doing the Hessian first yields a shipped,
  tested baseline to diff the harder order-`n` generalization against, instead
  of debugging both at once in the most "a-wrong-derivative-is-worse" path.
- **Symmetry-deduplicated Hessian nonzeros from the start.** Deferred (aligned
  with [ADR-0020](ADR-0020-nth-derivative-output-conventions.md) Decision 3):
  emit the full set first; dedup to the unique upper-triangle entries as a
  measured optimization once there is a passing baseline.
- **Drop `jac_output` outright and rename to `der_output`.** Rejected: keep
  `jac_output` as a documented alias for the first-derivative level — a free
  back-compat courtesy for existing callers.
