# ADR-0021 — Deprecate coderload `'l'`; add a split-inline (derivative + data) form

## Status

Proposed — 2026-07-01 (issue #83). **Awaiting maintainer ratification before it
changes `DESIGN §Contracts C-4` and the README embed-mode table.** Two coupled
calls: retire `'l'`, and give inline (`'i'`) a two-file escape hatch so its only
remaining rationale — compact *source* for large constant data — is covered
without `'l'`. The deprecate call is gated on the R17 large-data measurement
(#73) confirming no embedded regime where `'l'` beats `'i'`.

## Context

The fork exposes three embed modes — `'c'` classic (global + runtime `load`),
`'l'` coderload (`coder.load` + `coder.const`, tables kept in a `.mat`), `'i'`
inline (tables emitted as source, fully self-contained; the default since
[ADR-0012](ADR-0012-embedded-generator-default-inline-slim.md)). Facts that
frame the decision:

- **`'l'` is fork-only.** It was added in this fork as an *incremental* step on
  the way to inline (not upstream core), so retiring it removes maintainer-owned
  surface, not an upstream contract.
- **`'l'` does not codegen under Embedded Coder (ERT).** Verified this session
  (#83): a `'l'` Jacobian fails `coder.config('lib','ecoder',true)` for **both**
  `jac_output='matrix'` and `'nonzeros'`, *identically* — so it is the
  `coder.load` mechanism, not an output-form issue. Inline codegens clean under
  ERT (`numErr=0`). So "fix `'l'`" is a genuine `coder.load`-under-ERT project,
  not a triviality — against a mode with no unique deployed benefit.
- **`'l'`'s only edge is source size, and it doesn't survive to the binary.**
  Inline emits tables as literal source, so a huge-data case yields a large `.m`
  and large literal initializers in C (parse / compile-time / source-size cost).
  `'l'` keeps them as a compact blob. **But** `coder.const` folds the data into
  the compiled binary regardless, so the *compiled* footprint converges — the
  same "source bytes ≠ ROM" lesson #79 already taught. `'l'`'s advantage, if
  any, is purely at generation/source level for large data.
- **Contract coupling.** `DESIGN` C-4 and the README "embed modes" table assert
  **three modes, all numerically identical**; retiring `'l'` changes both.

## Decision

**1 — Deprecate `'l'` (lean-deprecate, maintainer-confirmed).** `'l'` is
redundant with `'i'` on the deployed artifact, fails ERT, and is fork-only. The
recommended mechanics (a §4 sub-choice — recommend, not decided): **deprecate
with a warning first, remove in a later major** — `adigatorOptions('embed_mode','l')`
emits a one-time deprecation warning routing users to `'i'` (+ the split form
below), docs stop advertising it, and CI keeps a single "still warns / still
runs" guard until removal. A hard removal now is the alternative (see
Alternatives); the warning-first path is safer if any downstream depends on it.

**2 — Give inline a split-data form so large-data source size is not a reason to
keep `'l'`.** Add an option that breaks the inline output into **two files —
the derivative and its data** — instead of one merged file. Two implementations
(the maintainer's two possibilities), recommended default first:

- **(b) tied by a data-function call *(recommended default)*.** The embedded
  generator simply **stops merging every function into one file**: the data
  function is emitted as its own file and the derivative file *calls* it. Small,
  local change (the assembly/merge step in the embedded generator), and it
  **preserves self-containment and C-4** — both files are source, no `global`,
  no `load`, no `.mat`, no `coder.load`. Directly removes the single-large-`.m`
  concern.
- **(a) data as a `coder.const` argument.** The data structure is passed *into*
  the derivative function as a constant argument, fully decoupling the two.
  Larger change (a signature rewrite threaded through the pipeline and every
  caller), but it enables **sharing one data blob across multiple derivative
  calls**. Deferred to a follow-on, wanted only if a data-sharing regime
  appears.

Recommended surface: a dedicated, composable option (e.g. `split_data ∈
{off, on}`, default `off`) orthogonal to `embed_mode='i'`, rather than a new
`embed_mode` value — to avoid a mode × split combinatorial blow-up. Exact
spelling is a ratification detail.

**3 — Gate the final deprecate on the R17 large-data measurement (#73).** Add a
large-constant-data cell to the showcase and compare **source size + compile
time + compiled footprint** for `'i'`, split-inline, and `'l'` across the
N-sweep. If (as expected) `'i'`/split wins or ties everywhere embedded users
care about → deprecate `'l'`. If a real large-data regime needs `'l'`'s compact
source that split-inline cannot match → keep and fix its ERT codegen instead.
Split-inline is what makes the "no regime needs `'l'`" outcome likely.

Lands as (on ratification): the `split_data` option (form (b)) in the embedded
generator; `DESIGN` C-4 marks `'l'` deprecated and states the split-inline form
holds the same invariants (both files source; no `global`/`load`/`.mat`/
`coder.load`); README embed-mode table updated; a `Verified by:` test for the
two-file form's C-4 invariants + cross-mode numeric equality; the R17 large-data
cell. Roadmap **R24** (issue #83).

## Consequences

- **Easier:** one fewer mode to keep ERT-clean, slim-compatible, and
  option-complete (#84); split-inline kills the large-`.m` parse/compile concern
  **without** reintroducing a `.mat`/`coder.load` dependency; the mode story
  collapses to "classic for host debugging, inline (optionally split) for
  embedded."
- **Harder / constrained:** deprecating a public option needs a warning + a
  removal timeline (breaking-ish); C-4 and the README table must change together
  (contract gate); form (b) requires the embedded generator to **stop merging
  all functions into one file** — a real change to the assembly step, validated
  against the C-4 invariants; form (a)'s `coder.const`-arg signature change is
  deliberately deferred.
- **Revisit if:** the R17 large-data numbers show `'l'`'s compact source wins a
  real embedded regime split-inline can't match (flips deprecate → fix); or a
  data-sharing-across-calls use case appears (promotes split form (a) from
  follow-on to shipped).

## Alternatives considered

- **Fix `'l'`'s ERT codegen and keep all three modes.** Rejected as the primary
  path: root-causing `coder.load` under `ecoder` is real work on a fork-only,
  redundant mode whose *compiled* footprint converges with `'i'` — maintenance
  surface with no measured deployed payoff. Kept only as the fallback if R17
  finds a large-data regime split-inline can't cover.
- **Hard-remove `'l'` now (no deprecation window).** Rejected as the default:
  cheaper long-term, but a public option may have silent downstream users; a
  warning-first window costs little and de-risks the removal. Offered as the
  faster alternative if the maintainer confirms no external users.
- **Keep inline monolithic; accept a large `.m` for big data.** Rejected:
  parse/compile time and source size are real at scale, and the split gives a
  cheap escape with no `.mat` — which is precisely what lets `'l'` go.
- **Data as a `coder.const` argument (form (a)) as the default split.**
  Rejected as default: largest change (signature rewrite across the pipeline and
  callers) for a decoupling benefit (cross-call data sharing) nothing needs yet;
  form (b) gets the source-size win with a far smaller, C-4-preserving change.
- **A new `embed_mode` value (`'is'`) instead of an orthogonal `split_data`.**
  Left as a ratification detail; recommended against because it multiplies the
  mode axis against every other option instead of composing.
