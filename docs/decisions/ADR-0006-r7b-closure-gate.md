# ADR-0006 — R7b slimming gate: eval-free dependency-closure, not a numeric round-trip

## Status

Accepted — 2026-06-20. Roadmap R7b (issue #21). Supersedes the "numeric
round-trip on staged inputs" wording in `docs/ROADMAP.md` for the *generation-
time* gate; a cheap numeric round-trip is retained as belt-and-suspenders in
the driver PR (see Consequences).

## Context

The R7b field-slice (`util/adigatorFieldSlice.m`) removes statements of a
generated `_ADiGator*` derivative file that feed only output-struct fields the
wrapper never reads (e.g. `..._location`/`..._size` in embed modes), so the
constant index tables they reference drop in `prune_adigator_mat`. Removing
statements from a generated derivative file is exactly the class of change where
"a wrong derivative is worse than an error" (`REVIEW_CONTEXT.md` principle 1), so
each slimming must be gated by a generation-time correctness check before the
slimmed file is accepted.

The roadmap originally specified a **numeric round-trip**: evaluate the original
and slimmed files on staged random inputs and compare. That requires
reconstructing valid staged inputs for the `_ADiGator*` function (the seeded
`gator_x.f` / `gator_x.d<vod>` struct plus random aux inputs) and `eval`-ing both
files at generation time — which the structure investigation flagged as the
fragile part (seed-shape reconstruction, `.mat`/global/path handling), and which
cannot be exercised in the authoring environment (no MATLAB).

## Decision

Gate each slimming with an **eval-free dependency-closure check**
(`closureOk` in `util/adigatorSlimDerivBody.m`) instead of a numeric eval.

For the generated dialect the slimmed file is **provably** numerically identical
to the original on all demanded outputs when, over the kept statement set:

1. every base name *read* by a kept statement is **external** (a function input
   or `Gator1Data`) **or has ALL of its writers kept**, and
2. every demanded output field `<outvar>.<field>` is still produced by a kept
   `<outvar>.<field>` (or whole-`<outvar>`) write.

If either fails, the engine bails and keeps the original file.

### Why this is sound (and the assumptions it leans on)

The proof relies on properties of the generated dialect, all already enforced by
the parser/engine (each with an explicit bail when violated):

- **Straight-line, fully unrolled** — rolled `for`/`while`/`if` are rejected
  (`adigator:fwdtape:controlflow`); the engine bails on any such file.
- **Side-effect-free with value semantics, no aliasing** — every statement is a
  pure assignment; the only partial write is `b(subs)=…`, and the parser records
  `b` among that statement's own reads, so a kept scatter forces `b` into the
  read set and condition (1) then forces *all* writers of `b` kept. Hence no kept
  statement can ever read a partially-reconstructed base.
- **One statement per line, no continuations** — the printer emits one statement
  per line; the engine bails if any body line ends in `...`.
- **The output struct is write-only** — generated code assembles `<outvar>.*`
  but never reads it back, so the per-field gating is *effective* (an undemanded
  sibling field is not pulled back in via a whole-struct read).

Under these, a dropped statement only ever wrote a base that no kept statement
reads; every kept statement sees identical inputs and computes identical values;
the demanded outputs are produced by kept statements. So the slimmed program
computes the demanded outputs identically — a guarantee *stronger* than a
finite-sample numeric round-trip, with no eval.

## Consequences

- No staged-input reconstruction or `eval` of generated files at generation
  time; the gate is deterministic and cannot itself be the source of a wrong
  result (any uncertainty → bail → original file).
- The check is unit-testable in isolation on hand-written tape snippets
  (`tests/unit/USlimEngineTest.m`, `CI_PLAN.md` TS-U-12) rather than needing a
  full pipeline + MATLAB Coder.
- **Belt-and-suspenders:** the driver PR (which already constructs staged inputs
  to exercise the wrapper end-to-end) *also* runs a cheap numeric round-trip of
  the slimmed wrapper against the unslimmed one as an independent cross-check.
  The closure gate is the primary, always-on guarantee; the numeric check is a
  secondary integration test. `docs/ROADMAP.md` R7 reflects both.
- **Revisit** if the dialect ever gains a construct that breaks an assumption
  (in-body control flow that survives analysis, a read of the output struct,
  multi-statement lines): the corresponding bail must stay, or the gate must be
  extended, before slimming such a file.

## Alternatives considered

- **Numeric round-trip only (the original roadmap wording).** Rejected as the
  *primary* gate: fragile staged-input reconstruction, an `eval` that can't be
  exercised without MATLAB, and only a finite-sample guarantee. Kept as a
  secondary cross-check in the driver where staged inputs already exist.
- **Trust the slice as sound-by-construction with no gate.** Rejected: the slice
  *is* sound by construction, but an independent generation-time gate is cheap
  insurance against an implementation bug (re-emission, parsing edge cases) in a
  change that edits derivative files — exactly where silent wrongness is worst.
