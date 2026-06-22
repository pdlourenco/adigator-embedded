# ADR-0009 — Interprocedural field-slice via an assembled-file worklist

## Status

Accepted — 2026-06-22. Implements issue #44 item 1 (the interprocedural R7b
increment deferred from #21); extends the closure-gate reasoning of
[ADR-0006](ADR-0006-r7b-closure-gate.md) across call boundaries. Guarded by the
fixtures/test from [ADR-0008](ADR-0008-offline-fixture-equivalence-tests.md).

## Context

R7b shipped as an **intra-function** field-slice: `adigatorSlimDerivBody` slices
only the *main* derivative function body (`Start Derivative Computations` → the
first `function ADiGator_LoadData()`), and on a **multi-subfunction** generated
file the embedded subfunction `function`/`end` lines fall inside that span,
`adigatorParseTape` throws `adigator:fwdtape`, and the driver conservatively
bails — the file is left unsliced. So for a derivative whose user function calls
subfunctions (e.g. `gapfun` → `conefun` → `setfun`, where `setfun` is called
from both), no dead value-chains or unread output fields are removed in any
function, and the per-subfunction `Gator*Data.Index*` tables stay in the `.mat`.

Two facts shape the fix:

- The slim **driver** (`adigatorSlimEmbeddedDeriv`) runs *post-hoc on the
  assembled single `_ADiGator*.m` file* plus the still-unpruned `.mat`. It does
  not carry the generation-time `AdigatorGeneratedFiles` call graph.
- The per-function primitive already exists and is field-granular:
  `adigatorFieldSlice` keeps the statements that produce a demanded set of
  output **fields** (`v.fld`), and handles a rolled `for…end` as one unit. It
  needs no change; what is missing is the layer that drives it across calls.

The maintainer selected **field-granular** cross-call demand (vs. a coarser
whole-call keep/drop), because the payoff of this increment — dropping a
subfunction output field and its index table that no caller reads — only
materializes with per-field demand.

## Decision

Add an **interprocedural layer that operates on the assembled file text** and
reuses `adigatorFieldSlice` per function:

1. **Split** the `_ADiGator*` file into function blocks — main `dername`, each
   `ADiGator_*` subfunction, and the `ADiGator_LoadData` trailer — each with its
   header, `Start…` marker, body, and closing `end`.
2. **Call graph:** within each body, identify call statements
   `X = ADiGator_sub(Y);`. A subfunction may be called from multiple sites; its
   demand is the union over them.
3. **Worklist fixpoint over `(function, demanded-field-set)`:**
   - Seed the main function with the wrapper-demanded fields
     (`adigatorWrapperDemand`).
   - Process a function with `adigatorFieldSlice(body, innames, demand)`. For
     each **kept** call `X = ADiGator_sub(Y)`: the live `X.<field>` reads in the
     sliced caller become demand on `ADiGator_sub`'s **outputs**; the input
     fields `sub` consumes on its parameter map **back** to demand on the
     caller's `Y.<field>` (re-slice the caller). Iterate until no demand set
     grows — monotone over finite field sets, so it terminates.
4. **Re-emit** by reassembling the sliced blocks; the R7c peephole and
   `prune_adigator_mat` then run unchanged, and the newly-unreferenced
   per-subfunction index tables drop.
5. **Soundness:** the existing eval-free closure gate runs **per function**
   (a call statement reads its callee-consumed input fields and writes its
   demanded output fields), and the driver's whole-file numeric round-trip is
   the combined cross-check — the same two-layer guarantee as ADR-0006, now
   applied to each function and to the assembled whole.

## Consequences

- Multi-subfunction derivatives slim for the first time; the per-subfunction
  `Gator*Data` index tables drop in the prune, so the embedded `.mat`/inline
  data shrinks while the numbers stay bit-identical (which the ADR-0008
  guard/fixtures pin once regenerated).
- `adigatorFieldSlice` is reused unchanged; the new code is the split +
  call-graph + worklist + re-emit, plus the per-function closure wiring.
- The **R7c union-copy peephole resolves Gator data for the main function
  only** (`loadGatorData` returns `s.(dername)`); it stays main-only in this
  increment. Extending it per-subfunction is a separate, benign-if-skipped
  follow-up (less optimization, never a wrong result).
- **Rolled `for…end` is out of scope when interprocedural.** A subfunction call
  or a result-field read hidden inside a rolled loop would be invisible to the
  top-level call/field scans and would under-demand a callee (a wrong
  derivative), so a multi-subfunction file containing *any* rolled loop bails
  the whole file unsliced. The intra-function path (`adigatorSlimDerivBody`)
  keeps its loop-as-a-unit handling for single-function files, where there is
  no cross-call demand to get wrong. The interprocedural + rolled-loop
  combination (the rest of issue #44 item 1) is a deferred follow-up. (The bail
fires only for a rolled loop in a *reached* block; an undemanded subfunction is
left whole and never sliced, so its loops are moot.)
- A wrong cross-call demand would be a wrong derivative, so the layer is
  conservative: any unresolved split, ambiguous call site, or closure failure
  bails the **whole** file to unsliced (never a partial, possibly-inconsistent
  rewrite), exactly as the intra-function path does today.
- **Revisit** if: generated code ever becomes recursive (it cannot from a
  non-recursive user function, but the worklist would need cycle handling); or
  if the peephole is taken per-subfunction; or if a future single-file format
  change moves the per-function `Gator*Data` binding the split relies on.

## Alternatives considered

- **Generation-time worklist over `AdigatorGeneratedFiles` (`.name`→`.dername`
  →`.func`).** The original #21 spec framing. Rejected for the as-built
  pipeline: the slim driver is deliberately a post-hoc pass on the *assembled*
  embedded file (the single artifact the embed modes ship), and threading a
  generation-time call graph into it would add plumbing for no extra
  information — the assembled file already contains every function and its
  per-function `Gator*Data` binding.
- **Base-granular cross-call demand (keep/drop a whole call).** Simpler and
  safe, but on the `gapfun` shape it slims almost nothing (every subfunction
  output is read *somewhere*), so it would not exercise or deliver the
  increment's purpose. Rejected by the maintainer in favour of field-granular.
- **Flatten/inline all subfunctions into one body, then reuse the existing
  intra-function slicer.** Rejected: inlining renames index references and
  fuses the per-function `Gator*Data` bindings, changing the `.mat` layout that
  `prune_adigator_mat` and the runtime loader depend on — a much larger,
  riskier change than slicing each function in place.
