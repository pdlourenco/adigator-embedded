# ADR-0008 — License-free equivalence tests run committed generated fixtures

## Status

Accepted — 2026-06-22. First applied in the issue #44 part-1b interprocedural
equivalence guard (`tests/offline/gap_interproc_equiv.m`).

Amended — 2026-06-22 (with #44 item 1): the fixtures are generated in **inline
embed mode**, not classic. `slim_embed` is skipped in classic mode (the embed
pipeline returns early), so a classic capture makes `slim1` a byte-copy of
`slim0` and the guard can never exercise slimming. Inline mode runs the slice
*and* embeds the data into the wrapper as `coder.const(...)` (identity outside
codegen); the offline core adds a `coder.const` shim
(`tests/offline/octave_shims`) only where `coder.const` is unavailable, so the
fixtures still run license-free in Octave / Coder-less MATLAB.

## Context

Issue #44 part 1b (interprocedural under-demand) needs a regression guard that
pins the *numeric* behaviour of an **interprocedural** generated derivative —
one where the differentiated function calls subfunctions (`gapfun` calls
`conefun`/`setfun`, and `conefun` calls `setfun`), so the generated
`_ADiGator` file is multi-subfunction. The guard must keep biting once the
part-1b slimming actually changes the generated code.

Two constraints pull in opposite directions:

- **Generation needs real MATLAB.** ADiGator's front end uses `classdef`
  operator overloading, `arguments` blocks, and `readlines` — none viable in
  Octave today (`CI_PLAN.md`; ADR-0003). So a derivative cannot be *generated*
  without a MATLAB license.
- **We want a license-free guard.** The cheap local-verification path that
  `CI_PLAN.md` otherwise leaves to "run the MATLAB pre-push script" still
  requires a MATLAB license. For a pure numeric-equivalence regression on an
  *already generated* artifact, that is a heavy gate.

The key observation: while *generating* a derivative needs MATLAB, *executing*
a generated derivative does not — the emitted `*_Grd.m` is plain procedural code
(indexing, matrix ops) that runs in GNU Octave. The one non-plain construct in
the inline-embedded form is `coder.const(...)`, a MATLAB Coder directive that is
identity at runtime and is shimmed where unavailable (see Amended status).

## Decision

Pin interprocedural (and similar) derivative behaviour with **committed
generated fixtures plus a plain-assert core wrapped for the MATLAB gate**:

- Generate the derivative on MATLAB and **commit the fixtures** under
  `tests/fixtures/<group>/` (here `tests/fixtures/gen_dialect/{slim0,slim1}`).
  In inline embed mode this is the single self-contained `gapfun_Grd.m` (the
  derivative + per-subfunction data functions are embedded into it; there is no
  separate `_ADiGator*.m` / `.mat`). The generator lives beside the data it
  produces (`capture_gen_dialect.m`); a nested `.gitignore` re-includes the
  generated filenames the repo-wide `.gitignore` excludes.
- Put the actual checks in a **plain-assert core under `tests/offline/`** that
  runs in both Octave and MATLAB. It only *executes* the committed fixtures and
  asserts numeric equivalence against an independent oracle (analytic gradient,
  finite-difference cross-checked) and across variants.
- **Wrap the core in a `matlab.unittest` test under `tests/integration/`** so
  it sits in the CI gate. `tests/ci_local.m` discovers `unit`/`integration`/
  `system` — *not* `offline` — so the core reaches CI solely through the
  wrapper, while staying runnable license-free in Octave.

The cross-variant equivalence contract is **numeric, not structural**: variants
are compared on their results (`AbsTol 0`), never on bytes or index-table
layout. A slimmed variant is allowed to shrink; only its numbers must not move.

## Consequences

- Interprocedural derivative behaviour can be verified **without a MATLAB
  license** (Octave, or any plain interpreter), which neither the MATLAB CI gate
  nor the MATLAB pre-push script offered.
- **Fixtures are committed generated artifacts** (binary `.mat` + generated
  `.m`). They must be **regenerated on MATLAB** whenever the generator or the
  slim engine changes; the regenerate step is documented in
  `capture_gen_dialect.m`, which is co-located with the data to make drift
  obvious. The guard deliberately does **not** regenerate, so it will not catch
  a generator change until someone regenerates the fixtures — this is the
  staleness cost we accept in exchange for license-free execution.
- **No Octave CI leg is added.** Octave stays an optional *local* convenience;
  CI remains MATLAB-only, consistent with `CI_PLAN.md` and ADR-0003.
- **Revisit** if: (a) an Octave compatibility layer ever makes *generation*
  itself license-free — then fixtures could be generated in-test and committing
  them becomes unnecessary; or (b) committed-fixture staleness bites in practice
  — then add a MATLAB-side CI check that regenerating is byte-stable against the
  committed fixtures.

## Alternatives considered

- **`matlab.unittest`-only, regenerate in-test (no committed fixtures).** This
  is what `IEmbedSlimTest` already does for *intra*-function slimming, and it
  needs no fixtures. Rejected here because it offers no license-free guard —
  the whole point of part 1b's offline check is reproducibility without a
  MATLAB license; regeneration requires one.
- **Pure Octave script + a dedicated Octave CI job.** Rejected — directly
  contradicts `CI_PLAN.md`'s "Octave not viable" stance and ADR-0003, and adds
  a CI dependency (a second toolchain to install and maintain) for marginal gain
  over running the same core through the existing MATLAB gate.
- **Compare variants structurally (byte / index-table identity).** Rejected —
  with the interprocedural slice (#44 item 1, ADR-0009) the slimmed variant
  legitimately shrinks (its unread output fields and index tables drop), so a
  structural comparison would *wrongly fail*. The contract that must hold across
  the slice is numeric identity, not structural identity.
- **Classic embed mode for the fixtures.** Rejected (see Amended status):
  classic skips `slim_embed`, so `slim1` would be a byte-copy of `slim0` and the
  guard could never exercise the slice. Inline mode (with the `coder.const`
  shim) runs the slice while keeping license-free execution.
