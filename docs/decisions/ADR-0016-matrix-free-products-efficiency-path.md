# ADR-0016 — Matrix-free products are the embedded-efficiency path; the re-vectorization peephole is shelved

## Status

Accepted — 2026-06-26. Supersedes the #56 §4 decision gate ("re-vectorization
post-pass, scheduled after R10(a)"): that gate approved *building* the peephole;
the measurements below redirect the effort. Ties together issues
[#56](https://github.com/pdlourenco/adigator-embedded/issues/56) (vectorization /
matrix algebra), [#73](https://github.com/pdlourenco/adigator-embedded/issues/73)
(all-axes showcase + comparison to C), and
[#64](https://github.com/pdlourenco/adigator-embedded/issues/64) /
[ADR-0014](ADR-0014-matlabtest-codegen-equivalence.md) (codegen-equivalence
infrastructure). **Codifies the wrapper-output convention** — output order and
`DER_LEVELS` level selection — as DESIGN §Contracts **C-6** and in
`adigatorDerivativeConventions.m` (it was previously documented only in the
generator headers): see §Decision item 5. The forward generators already comply;
the standalone reverse prototype deviates (value-first) and is brought into
compliance in R16.

## Context

#56 asked whether ADiGator-embedded can "generate vectorized code from scratch"
or "rebuild it after generation" so the generated derivative keeps the
efficiency of vectorized MATLAB. The §4 gate approved a source-to-source
*re-vectorization peephole* (R12) reusing the R7 substrate
(`adigatorParseTape`, the closure gate, the numeric round-trip), targeting the
`scatter → matrix-op → flatten → gather` plumbing `cadamtimesderiv` emits.

Before building it, the pass was prototyped far enough to **measure** what it
would buy on this fork's real generated code. The measurements (recorded in
`docs/ANALYSIS.md` §3.5) changed the conclusion:

1. **The peephole has almost no reach (the R10(b) lesson again).** The
   `scatter → matrix-op → flatten → gather` idiom only fuses where the index
   maps are provably identity/contiguous. Surveying real bodies, the **scatter
   is never an identity** — it intrinsically maps the sparse nonzero-vector into
   structured positions of the dense operand matrix. So the plumbing cannot be
   collapsed; only an occasional identity *gather* permits a marginal
   one-index-drop. The fusion precondition does not occur naturally.

2. **The cost is governed by density and assembled-vs-matrix-free, not by the
   AD mode.** Forward assembled static-data (≈ constant ROM) scales with `nnz`
   of the derivative. For **sparse** Jacobians/Hessians — the common embedded
   case — forward + ADiGator's compile-time sparsity exploitation is already
   lean. For **dense** assembled matrices the O(n²) constant data is
   **intrinsic**: any method handing you a dense n×n matrix must produce n²
   numbers; reverse does not avoid it (it would need *m* adjoint sweeps to
   assemble), and no peephole removes it. **Matrix-free products** (J·v, J'·v,
   H·v) carry **~0 ROM** regardless of density — measured 0 for `_RGrd`/`_JtV`
   across diagonal / dense-square / tall shapes; correctness verified (reverse
   gradient = forward = analytic to 1e-10).

The full evidence table is in ANALYSIS §3.5.

## Decision

1. **Shelve the re-vectorization peephole (R12 as originally scoped).** Keep the
   R7c `adigatorPeepholeUnionCopy` guard as-is; do not build the larger fusion
   pass. Reason: its precondition (identity scatter) does not arise, and the
   real ROM cost it would chase is intrinsic to assembled dense matrices.

2. **Adopt the matrix-free product family as the embedded-efficiency path**, and
   **record the assembled-matrix verdict**: for *assembled* derivatives, forward
   + sparsity is the answer (near-optimal for sparse; dense O(n²) is intrinsic);
   the open frontier is *matrix-free products*, which give zero-ROM,
   density-independent products across all three objects. Today's coverage:
   gradient (`_RGrd`) and J'·v (`_JtV`). The gaps to close — in priority order —
   are **H·v** (forward-over-reverse; brings zero-ROM to second-order embedded
   solvers) and **J·v** (forward directional), then **rolled-loop reverse**
   (ANALYSIS §3 Stage 3) so the products reach the allocation-over-time anchor
   under `unroll=0`.

3. **Reverse gets embed-pipeline parity first** (`#73` item A): a
   `'gradient-reverse'` `DerType` in `adigatorGenDerFile_embedded` that routes
   the reverse file through the existing prune → patch → coderload/inline +
   `slim_embed` stages (ANALYSIS §3.3 Stage 5). This is the prerequisite that
   makes forward-vs-reverse expressible *through to C* — required by both the
   `#73` comparison harness and the C-level validation of the determination
   above.

4. **The comparison is delivered through `#73`'s all-axes harness, in two
   levels** — first at MATLAB level (statement/ROM complexity, already measured),
   then at C level (compiled-C size + runtime). The C level **reuses the `#64` /
   ADR-0014 `matlabtest.coder.TestCase` codegen-equivalence + generated-code
   coverage** as its correctness gate and metric source. The three issues are
   one track: `#56` sets the direction, `#73` builds the showcase/benchmark,
   `#64` supplies the codegen-equivalence machinery.

5. **Derivative output order — codified as a contract; the new generators follow
   it.** The wrappers are derivative(s)-highest-order-first with the function
   value `Fun` last, and `DER_LEVELS` selects which levels appear. This was
   documented only in the generator headers; this PR promotes it to **DESIGN
   §Contracts C-6** and `adigatorDerivativeConventions.m`. It applies to **all**
   derivative objects (not just the Hessian): Jacobian `[Jac, Fun]`, gradient
   `[Grd, Fun]`, Hessian `[Hes, Grd, Fun]`, and `DER_LEVELS` trims the lower-order
   companions for every one of them — resolved uniformly by
   `adigatorResolveDerLevels` (e.g. `der_levels = [1 2]` on a Hessian ⇒
   `[Hes, Grd]`; `[1]` on a Jacobian ⇒ `[Jac]`). Therefore:
   - **`adigatorGenJvFile`** → `[Jv, Fun]` (mirrors `[Jac, Fun]`).
   - **`adigatorGenHvpFile`** → `[Hv, Grd, Fun]` (mirrors `[Hes, Grd, Fun]`),
     honouring `der_levels` to trim outputs.
   - The R4/R5 prototype generators currently deviate — `_RGrd` emits
     `[y, grad]` and `_JtV` emits `[y, jtv]` (value **first**). **Align them to
     the convention** (`[Grd, Fun]`, `[Jtv, Fun]`) when reverse gains embed
     parity (decision 3): the embedded reverse wrapper is emitted by the shared
     wrapper generator and so is `[Grd, Fun]` by construction; the standalone
     prototype signatures are flipped to match, updating `IRevGradTest` and the
     `adigatorGenJtVFile` doc. Recorded as a deliberate (small) breaking change
     to the prototype, for a uniform cross-mode signature that the comparison
     harness depends on.

6. **Phasing is recorded as roadmap rows** (R12 reframed + R16–R19) so progress
   is followable; this ADR + the ROADMAP + ANALYSIS updates land in one docs PR,
   with connecting comments on #56/#64/#73.

## Consequences

- The efficiency question is settled with evidence rather than intuition:
  re-vectorization is a dead end on current generated shapes; the leverage is
  matrix-free products + the assembled-matrix verdict.
- Reverse mode stops being a standalone prototype and enters the embed pipeline
  (coderload/inline/slim), making it a first-class, codegen-able mode — and a
  comparable axis in the `#73` harness.
- A uniform `[derivative…, Fun]` output convention across forward and reverse
  generators (decision 5) costs a one-time breaking change to `_RGrd`/`_JtV`
  signatures (+ `IRevGradTest`, the JtV doc) but removes a cross-mode footgun.
- New on-disk artifacts: `'gradient-reverse'` embedded files; `_Hvp` / `_Jv`
  generated files (+ their `.mat`). They consume the same `Index*`/`Data*`
  dialect, so prune/patch/inline apply — but the "applies unchanged" claim
  (ANALYSIS §3.3 Stage 5) is a *design assertion to be validated*, not a
  guarantee; R16 must confirm or adjust the patch/prune regexes against the
  reverse file's two-pass (forward + adjoint) shape.
- **Revisit** if: a future emitter change makes the scatter index identity
  (re-vectorization would then have reach); or if a consumer genuinely needs
  *assembled* dense Jacobians/Hessians at a size where O(n²) ROM is binding
  (only reverse-with-coloring or a different representation could help — out of
  scope here).

## Alternatives considered

- **Build the re-vectorization peephole as gated (the original R12).** Rejected:
  measured to have near-zero reach (identity scatter never occurs); the ROM it
  would chase is intrinsic to assembled dense matrices. Would add a gated pass +
  ADR for marginal, rarely-firing wins.
- **Treat reverse as "the answer" wholesale.** Rejected as overbroad: for sparse
  assembled Jacobians/Hessians (the common embedded case) forward + sparsity is
  already lean, and reverse offers no assembled-matrix advantage. The honest
  scope is *matrix-free products*, not "reverse beats forward."
- **Commit now to the full in-printer reverse mode** (ANALYSIS §3.3 Stages 1–5).
  Deferred: that remains the larger R6-class "separate decision." The
  source-to-source prototype (R4/R5) already realizes the gradient + J'·v wins;
  embed parity + H·v/J·v + rolled-loop reverse are contained increments that
  deliver the measured value without the printer rewrite.
- **Keep the reverse prototype's `[y, grad]` order.** Rejected: it contradicts
  the established `[Jac, Fun]` / `[Hes, Grd, Fun]` convention and makes a
  forward-vs-reverse comparison harness error-prone (a real footgun hit during
  the measurement work). Uniformity is worth the one-time flip.
