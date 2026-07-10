# ADR-0027 — Compiled memory metrics come from the ERT object (`size`/`-fstack-usage`), not the codegen report

## Status

Accepted — 2026-07-09

## Context

The R17b C-level derivative showcase (`bench/derivShowcaseC.m`, issue #73 item B)
originally reported a per-cell "size" column that was a **sum of generated
`.c`/`.h` source-file bytes**. R17b itself flagged this as misleading: source
bytes are dominated by comments and `initialize`/`terminate` boilerplate, so the
small forward-vs-reverse spread they showed (the "reverse compiled C is ~8%
leaner" reading) is not a real footprint difference and does not survive to the
compiled binary. R17c is the correction: report the **honest compiled footprint**
— ROM, static RAM, and max stack of the derivative function as actually built by
Embedded Coder — so the #73 "which mode should I pick?" comparison, and the R6 /
R24 decision gates that depend on it, rest on real numbers.

Two questions had to be settled to do that: **where** the numbers come from, and
**what** exactly is measured.

The obvious candidate source — the Embedded Coder **static-code-metrics report**
(`metrics.html` / `data.json` inside the generated `.mldatx`) — was evaluated and
found unreliable for this code:

- Its code-metrics tables **silently do not populate for generated AD code**: a
  hand-written function yields a full ~22 KB report, but the AD wrapper yields a
  ~574-byte empty stub. No error, just no data.
- `GlobalVariables` is **empty for inline mode** anyway — the derivative's static
  index tables are emitted as `static const` (landing in `.rdata`), not as
  globals the report enumerates.

So the report cannot be the data source. The compiled object itself can: the
GNU binutils `size` tool reads the linked sections, and `gcc -fstack-usage`
emits per-function frame sizes.

## Decision

**Measure the compiled footprint by compiling the ERT-generated C and reading the
object, not the codegen report.** Concretely, in `bench/derivShowcaseC.m`
(`coreFootprint`):

- Build the embeddable cell through Embedded Coder (`coder.config('lib','ecoder',
  true)`) as before, then compile the generated C with the MATLAB-bundled MinGW:
  `gcc -Os -fstack-usage -c <file> -I"<clib>" -I"<matlabroot>/extern/include"`
  (the include path resolves `tmwtypes.h` / `rtwtypes.h`).
- **ROM** = `.text` + `.rdata`, **static RAM** = `.data` + `.bss`, summed from
  `size -A` on the object. (MinGW emits COFF, so read-only data is `.rdata`, not
  the ELF `.rodata`.)
- **Max stack** = the largest frame in the `.su` files gcc writes alongside each
  object.
- Measure the **core derivative object(s) only** — `<wrapper>.c` plus
  `<wrapper>_data.c` (the static index tables, where the ROM that differs between
  modes/forms actually lives). **Exclude** the lifecycle stubs
  (`_initialize`/`_terminate`), the `examples/` main, and the entire `interface/`
  MEX gateway (`_coder_*`): none of those deploy to the embedded target, and the
  MEX gateway in particular is large, constant boilerplate that would swamp the
  signal.
- **Skip-clean** when the standalone `gcc`/`size` toolchain is absent: the
  footprint fields stay `-1` (rendered as an em dash, treated like a skip by the
  test) while the build + numeric-equivalence checks still run. A machine with
  MATLAB Coder but no on-disk MinGW is not a failure.

`size`/stack are the source of truth; the codegen report is not consulted for
these numbers.

## Consequences

- The showcase now tells the **honest, converged-footprint story**: for the
  vectorized costs, forward and reverse gradient compiled ROM are byte-identical
  (192 B at n=64, 208 B at n=8), the analytical floor is only ~15–50 B under, and
  static RAM is **0** — the embeddable (`i`) forms carry ≈0 static data, so ROM /
  RAM do not distinguish them. The earlier source-byte "reverse is leaner" claim
  is retired. The forms that *would* differ (data-heavy index tables) are exactly
  those still blocked on the Embedded-Coder codegen gaps in
  [#80](https://github.com/pdlourenco/adigator-embedded/issues/80); when they
  unblock, this same measurement captures the real ROM spread.
- `bench/derivShowcaseC.m` gains `romBytes` / `ramBytes` / `stackBytes` per cell,
  leads the markdown table and the scaling figure with compiled ROM, and keeps the
  source-byte sum only as an explicitly-labelled secondary column. Pinned by
  `SCodegenShowcaseTest` (ROM/RAM/stack measured, forward/reverse convergence),
  which is Coder+ERT+toolchain-gated and skips cleanly otherwise.
- The bench now depends on the MATLAB-bundled MinGW `gcc`/`size` being findable
  (via `MW_MINGW64_LOC` or `matlabroot/bin/<arch>/mingw64`). This is dev-only and
  non-gating (the whole showcase is extended-suite, never the PR gate).
- The user-guide "which mode" fragment (`docs/userguide/bench_compare.tex`) still
  shows the source-byte proxy; refreshing it to compiled ROM is a coupled
  R13-continuation doc pass (it needs a PDF rebuild) and is deliberately left as a
  follow-up, not folded into R17c.

## Alternatives considered

- **Parse the Embedded Coder static-code-metrics report.** The intended source,
  and it would need no compiler. Rejected: it silently does not populate for
  generated AD code (574-byte stub) and its `GlobalVariables` is empty for inline
  mode — it simply does not contain the numbers for this code.
- **Keep the source-byte sum as the size metric.** Zero new dependency. Rejected:
  it is boilerplate-dominated and actively misleading (it produced a
  forward-vs-reverse ordering that the compiled object does not have) — the exact
  thing R17c exists to fix. Retained only as a labelled secondary.
- **Measure the whole generated library** (all `.c`, including runtime + MEX
  gateway). Rejected: the `interface/` MEX gateway and `examples/` main are not
  deployed and are large constant boilerplate that swamps the derivative's own
  footprint; the honest comparison isolates the derivative object.
