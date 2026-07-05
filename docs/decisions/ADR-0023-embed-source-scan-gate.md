# ADR-0023 — Reject cells / `load` / `global` in embed-mode source (input-scan gate)

## Status

Accepted — 2026-07-03 (issues #101, docs/ANALYSIS.md B21/B22). Adds an
embed-mode facet to `DESIGN §Contracts C-4`. Implementation lands with this ADR
(`util/adigatorScanEmbedUnsupported.m` + a gate in `adigator.m`); pinned by
`tests/integration/IEmbedUnsupportedTest.m`.

**Revised 2026-07-04 (maintainer): error → warning.** The disposition below —
a hard error that *stops* differentiation — diverged from the intended design.
The corrected behavior is a **warning + verbatim emission** (as classic mode);
see the Revision section. The realignment (code, `C-4`, the user guide,
`CI_PLAN`, and `IEmbedUnsupportedTest`) is **pending in
[#123](https://github.com/pdlourenco/adigator-embedded/issues/123) / ROADMAP
R29** and flips together, contract-first. **Until it lands the tool still
errors, and `C-4` / the guide / `CI_PLAN` correctly describe that current
behavior.**

## Revision — 2026-07-04: warn, don't stop (issue #123)

**Decision (revised).** In embed modes `'l'`/`'i'`, a user **cell**, **`load`**,
or **`global`** in the differentiated source is **not** an error. It is emitted
**verbatim into the derivative file exactly as classic mode does**, accompanied
by a **warning** that the generated file is not self-contained and may not
code-generate until the construct is removed.

**Why.** A user may `load` (or use a `global`/cell) *provisionally* and replace
it on both the original and derivative function later; classic mode already
accepts these. "The derivative should be embeddable, so the source should be
too" is a *warning*-worthy observation, not a blocking one — stopping
differentiation is too strong, especially when classic accepts the same code.

**Governing principle — embed is no more restrictive than classic.** Embed adds
only a warning (reduced embeddability); it introduces **no** gate beyond
classic's, and it must **not suppress** classic's own errors. Constructs that
classic itself rejects (bare `load(...)`, `persistent`, cell patterns the core
cannot differentiate) continue to error **from the core, unchanged**.

**Proviso (maintainer).** The warn-and-pass treatment applies to a construct
**only where it actually works in classic**. The realignment (#123) must
**verify** each of cells/`load`/`global` produces a correct classic-mode
derivative before downgrading its gate to a warning.

**Reclassifies B21** from "C-4 violation → hard block" to "warn-and-allow"
(embeddability is the user's responsibility). **B22-in-embed:** the constant
cell is emitted verbatim (correct since the B22 classic fix); the warning notes
a cell may still be rejected by MATLAB Coder downstream.

*This Revision supersedes the disposition in the Decision / Consequences /
Alternatives below, which are kept unchanged as the record of what shipped
first.*

## Context

Embed modes `'l'`/`'i'` exist to produce **dependency-free, embeddable**
derivative code (Contract C-4: no runtime `global`/`load`, no `.mat` for `'i'`).
Two bug classes showed the pipeline instead emits code that only fails *later*:

- **B21** — a user `load(...)` in the differentiated function is passed
  **verbatim** into the generated `'l'`/`'i'` file, re-introducing a runtime
  dependency (a C-4 violation) that surfaces at codegen/runtime, not generation.
- **B22** — a constant **cell** used in the body is emitted verbatim; the B17/B22
  work makes constant cells *correct in classic*, but cells are not an accepted
  embedded-C construct, and a cell that carries the derivative variable produces
  broken code regardless.

The common thread: constructs that cannot be made embeddable were discovered
*after* generation (a confusing runtime crash, or a silently non-embeddable
file), violating the project's first principle — *a clear error beats a
plausible-but-wrong / broken result*. A user `global` in the source is the same
category (runtime dependency).

ADiGator already reads and parses every function it transforms (main +
subfunctions + external callees, as `CalledFunctions`/`FunctionInfo`) and knows
`EMBED_MODE` in the core, so a **static pre-transformation scan of the user
source** is a natural, cheap hook — the same shape as detecting `load` that the
maintainer flagged for B21.

## Decision

In embed modes `'l'`/`'i'` only, **statically scan each user-source function**
ADiGator will transform and **raise a clear, actionable error** (naming the file
and line) if it uses a **cell array**, a user **`load`**, or a user **`global`**.
Classic mode `'c'` is unaffected (there cells work via the B17/B22 fix and
`load`/`global` are legitimate runtime dependencies).

- Detection is **AST-based** (`mtree`), so occurrences inside comments or strings
  do not false-trigger. Kinds: cell literal `LC` / cell index `CELL`; `GLOBAL`;
  `load` as a `CALL`/`DCALL` whose leftmost identifier is `load`.
- The scan runs in `adigator.m` after each function file is classified, gated on
  **`~PrevDerFlag`** so it scans only **user source** — a previously-generated
  ADiGator derivative file (re-differentiated for the Hessian's second pass)
  carries ADiGator's *own* `global ADiGator_…`/`ADiGator_LoadData` boilerplate,
  which the embed pipeline strips and which must **not** trip the gate.
- The error identifier is `adigator:embed:unsupportedConstruct`.

## Consequences

- **Easier:** B21 and B22-in-embed are resolved by one mechanism; the user gets a
  fail-fast, actionable message at generation time instead of a downstream crash.
  The gate composes with the standing error-path cleanup (ADR-0011), so it exits
  cleanly (path/handles restored).
- **Harder / constrained:** constant cells that *work in classic* are **rejected
  in embed** — an intentional asymmetry (the B17/B22 fix stays valuable for
  classic; embed is stricter). Users must pass parameters as struct/numeric
  inputs (pre-loading any data) for embed targets.
- **Scope:** the scan is per-file; a cell/`load`/`global` in an *untransformed*
  local function sharing a user file would still be flagged. Acceptable
  (conservative, and such a construct in an embed-bound file is suspect).
- **Revisit if:** a future embeddable representation for cells/`load` lands (e.g.
  capturing `load`'d constants as embedded `Data*`), in which case the gate for
  that construct is relaxed to that path rather than an error; or if the
  per-file scope proves too coarse and needs narrowing to the transformed
  function's line span — e.g. an embed-bound kernel that uses a cell purely for
  *non-differentiated bookkeeping* (`error('%s', msgs{k})`) is rejected today,
  the kind of report that would justify the line-span narrowing.

## Alternatives considered

- **Make cells/`load` embeddable (capture into `Data*`).** The original B21
  direction ("capture the loaded constants as embedded data") and a
  cell-lowering pass. Rejected for now: substantially more machinery for
  constructs the embedded coding standard disallows anyway; a clear error is the
  higher-value, principle-1-aligned move. Left as the revisit condition above.
- **Scan in `adigatorGenDerFile_embedded` (the embed entry point).** Simpler
  (knows `embed_mode` directly) but only sees the main file — it lacks the call
  graph, so a cell/`load` in an *external* user subfunction (the B21 shape, in a
  separate file) would be missed. The core hook sees every transformed function.
- **In-transformation handling / per-operand rejection.** Detect the construct
  as the overloads hit it. More invasive to the delicate `@cada` layer, fires
  mid-transformation (less clean), and is harder to make comprehensive than a
  source AST scan.
- **Regex/text scan instead of `mtree`.** Rejected: false-positives on cells or
  the words `load`/`global` inside comments and strings. `mtree` is exact.
- **Blanket rejection in all modes.** Rejected: classic mode legitimately
  supports these (cells via the B17/B22 fix; `load`/`global` as runtime deps),
  and the incompatibility is specifically an *embeddability* (C-4) concern.
