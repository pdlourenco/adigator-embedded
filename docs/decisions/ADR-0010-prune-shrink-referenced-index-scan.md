# ADR-0010 — Prune-shrink drops a Gator*Data.Index* only when the slimmed code provably cannot reference it

## Status

Accepted — 2026-06-22. Roadmap R7b (issue #21), the data half of
slice-before-prune. Builds on [ADR-0006](ADR-0006-r7b-closure-gate.md) (the
code-slice soundness) and [ADR-0009](ADR-0009-interprocedural-field-slice-worklist.md)
(the interprocedural slice that creates the now-dead tables).

## Context

The R7b field-slice removes generated statements that feed only unread output
fields; ROADMAP R7b specifies it "runs before `prune_adigator_mat` so the
now-unreferenced `Gator*Data.Index*` constants drop from the `.mat`/inline
data." ADR-0006/0009 establish that the *code* slice is numerically sound. But
`prune_adigator_mat` historically kept **all** `Index*` unconditionally
(`startsWith(fG,"Index")` force-keep), so the slice removed a table's *readers*
yet the table survived in the embedded data — e.g. `gapfun`'s `Index7` after its
sole reader `f.dz_location = Gator1Data.Index7` was sliced away. The data half
was never realized: correct numbers, dead constants embedded.

Dropping an embedded constant is correctness-sensitive in the same way the slice
is — wrongly dropping an `Index*` the code still reads is a wrong derivative (a
codegen/runtime failure at best, a silent miscompute at worst), which
`REVIEW_CONTEXT.md` principle 1 ranks worse than keeping a dead one. Unlike the
slice, the prune runs *after* the slice's numeric round-trip cross-check, so it
has no independent numeric guard — its soundness must be structural.

## Decision

Keep an `Index*` field iff the **slimmed** code provably references it, decided
by a static scan of the just-rewritten derivative file, and keep-all on any
doubt.

- A new `embedding/adigatorReferencedIndex.m` splits the slimmed `genfile.m`
  into per-function blocks and records, per generated function, the literal
  `Gator<d>Data.Index<n>` tokens (and `Gator<d>Data` table names) its body
  references. Comments are stripped first (the dialect never uses `%` as an
  operator).
- `prune_adigator_mat` takes an optional third argument (this map). When a
  function is present in the map, an `Index*` is kept only if its token is in
  the function's referenced set; otherwise **all** `Index*` are kept, exactly as
  before. The `Data*` non-empty rule and the `Index*`-only down-cast (C-3 /
  ADR-0001) are unchanged.
- `adigatorGenDerFile_embedded` builds the map only when `slim_embed` actually
  rewrote the file (`slim.sliced || slim.collapsed>0`); any failure yields an
  empty map → keep-all. So the non-slim path is byte-for-byte unchanged.

### Why this is sound (and the assumptions it leans on)

Index access in the generated dialect is **always** the literal token
`Gator<d>Data.Index<n>` (the per-function constant table is loaded into a local
named exactly `Gator<d>Data`, then indexed by literal field). So the set of
`Index*` a function can read is exactly the set of such tokens in its body. The
scan is conservative on every way that literalness could break:

- **Not confidently parsed → keep-all.** A function whose block is absent, or
  whose name cannot be parsed, is simply not in the map (prune keeps all its
  `Index*`).
- **Non-literal table use → keep-all.** A dynamic field `Gator<d>Data.(v)`, or
  aliasing/passing the bare table to another variable, could hide a live index
  from the token scan; such a function is dropped from the map (keep-all) rather
  than risk under-keeping.
- **Shrink never empties a referenced table.** The boilerplate
  `Gator<d>Data = coder.const(<data>.Gator<d>Data)` reads the table even when the
  function indexes nothing (e.g. `setfun`). If dropping the unreferenced indices
  would leave such a table with no fields, the prune falls back to the *unshrunk*
  keep-set for that table — emitting exactly the data shape it produces today
  (a codegen-proven shape) rather than a zero-field `coder.const(struct())`,
  which is an edge case Coder has never been exercised on. A table the slimmed
  code references in no way at all is still dropped entirely.

So a dropped `Index*` is one no kept statement can name; the kept code sees
identical constants and computes identical values. A wrongly *kept* index is a
few embedded bytes; the scan never *drops* one it cannot prove dead.

Two dialect assumptions this rests on, both true for the bare mechanical
assignment lines ADiGator emits and each failing *safe* (over-keep) if revisited:
(1) the comment strip cuts at the first `%`, which assumes no char literal
containing `%` shares a line with an index access; (2) a table is bound to a
local `Gator<d>Data` before indexing, never chained `parent.Gator<d>Data.Index<n>`
inline — and even that chained form is handled defensively (the scan records the
index), so it cannot be under-kept. A future dialect change that broke (1) is the
only way to manufacture an under-keep, which is why the assumption is pinned here
and in the scanner comment.

## Consequences

- The data half of slice-before-prune is realized: the per-subfunction index
  entries the slimmed code no longer reads (e.g. `gapfun`'s `Index7`) drop from
  the inline/`.mat` data when `slim_embed` slices. A table that becomes fully
  unindexed but is still referenced keeps its unshrunk shape (see above), so the
  shrink is bounded by what is provably both dead and non-emptying.
  `IInterprocGapEquivTest` /
  `gap_interproc_equiv` stay green because they assert numbers, not bytes; the
  committed fixtures shrink on the next regeneration.
- A new structural guarantee to maintain: if a future change makes the generated
  dialect index a table through anything other than a literal
  `Gator<d>Data.Index<n>`, the scanner's keep-all guards must still fire (or be
  extended) — covered by the offline core's dynamic-field/alias cases
  (`tests/offline/prune_shrink_offline_checks.m`, gated by `IPruneShrinkTest`).
- **Revisit** if the generated data layout or the per-function `Gator*Data`
  local-naming convention changes (then the token form the scan keys on must be
  updated in lockstep), or if a non-`slim_embed` caller ever wants the shrink
  (today it is deliberately gated behind an actual slice).

## Alternatives considered

- **Keep the unconditional Index* force-keep (status quo).** Simplest and
  trivially safe, but leaves R7b's data half unimplemented — the whole point of
  slicing before pruning. Rejected: it permanently embeds the dead tables the
  slice was meant to free.
- **Re-run a numeric round-trip after the prune.** Mirrors ADR-0006's secondary
  check, but needs staged-input reconstruction and an `eval` of generated code
  at generation time (the fragile path ADR-0006 deliberately avoided), and a
  finite sample is weaker than the structural argument. Rejected for the same
  reasons ADR-0006 rejected it as the primary gate.
- **Have `prune_adigator_mat` parse the file itself** instead of taking a
  prebuilt map. Rejected: it would duplicate the per-function block split the
  scanner does and couple the data-struct prune to file I/O; a text-in/struct-out
  scanner plus a map-in prune are each testable in isolation, and (being
  char/regexp) license-free in Octave via `prune_shrink_offline_checks` /
  `UPruneMatTest`.
- **Emit a zero-field `struct()` for a referenced-but-emptied table.** The first
  cut did this; rejected on review because `coder.const(struct())` is an
  unexercised codegen shape and the generation pipeline has no Coder gate to
  catch it. Falling back to the unshrunk keep-set for that (always tiny) table
  costs nothing measurable and stays on a data shape Coder already compiles.
- **Drop a referenced-but-emptied table entirely.** Rejected: the boilerplate
  `Gator<d>Data = coder.const(...Gator<d>Data)` would then fail to resolve.
