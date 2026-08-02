# Changelog

All notable, user-facing changes to this ADiGator fork are recorded here. The
format follows [Keep a Changelog](https://keepachangelog.com/), and the project
follows [semantic versioning](https://semver.org/).

This is the **GMV embedded fork** of ADiGator, built on upstream ADiGator 1.x by
Matthew J. Weinstein and Anil V. Rao and distributed under the GNU GPL v3. The
version numbering restarts at 2.0 to reflect the accumulated new capability (see
below); it is not a patch of upstream 1.x.

## [Unreleased]

<!-- Add user-facing changes here as they land. At release time, the release
     workflow (.github/workflows/release.yml) requires this section to be empty
     and the new version to have its own dated section below. -->

### Added

- **Re-entry pin: a generation after a failed generation must still work.**
  `UCoreErrorHygieneTest.generationSucceedsAfterAFailedGeneration` (TS-U-08)
  runs a malformed fixture to force a failure, then generates a real gradient
  in the same session and checks it against the analytic derivative. The
  existing pins asserted that a failure *releases* its state; releasing state
  is a weaker claim than leaving the engine able to start over. Found while
  cataloguing the vectorized refusal boundary (engine-v2 analysis, E4): the
  property was never in doubt once measured — it holds — but it was untested.
- **`adigatorCoderConfig` — the Embedded Coder configuration this project
  generates for.** Returns a `coder.EmbeddedCodeConfig` that forbids dynamic
  memory allocation (no `malloc`, as an embedded target requires) and pins a
  portable C profile: C99, no code-replacement library, non-finite support on.
  Hand it to `codegen` to build a generated derivative the same way this
  project's own codegen tests and benchmarks do:

  ```matlab
  cfg = adigatorCoderConfig();                     % or ('GenCodeOnly', true)
  codegen('myfun_Grd', '-config', cfg, '-args', {zeros(n,1)});
  ```

  Note that code generation succeeding is **necessary but not sufficient** for
  embeddability: it rejects *unbounded* sizes, but a bounded-but-large
  derivative can still overflow a small stack. See ADR-0033.

### Changed

- **The `polydatafit` example now builds its Vandermonde matrix the embeddable
  way, and the ODE examples say what stops them being embeddable.** `fit.m` grew
  the matrix by concatenation (`V = [V, x.^count]`), which differentiates fine
  but has no compile-time size bound — so MATLAB Coder rejects *that function*,
  before any derivative exists, under the static memory allocation an embedded
  target requires. It now pre-allocates `V` and writes columns into it. The
  mathematics and the computed Jacobian are unchanged.

  If you copied that pattern: prefer indexed writes into a pre-sized array over
  growing one, for anything you intend to differentiate for an embedded target.

  `mybrussode` and `burgersfun_noloop` size their state from a runtime grid size
  `N` and now carry a note explaining the two ways to make such a function
  embeddable — pin the size at build time (`coder.Constant`), or declare a
  maximum with the `loopbound` option. `lb_alloc` gained the matching contrast:
  a runtime bound is not itself a barrier, an *undeclared* one is.

### Fixed

- **A Hessian differentiated through a rolled loop no longer carries an O(n²)
  stack temporary.** If you wrote a scalar cost as a subscripted loop —
  `for k = 1:n, y = y + phi(x(k)); end` — the generated Hessian gathered an
  `n`-by-`n` array of doubles onto the stack inside the loop, even though the
  Hessian it returns is diagonal. At n = 64 that was **37.5 KB of stack, 63×
  what a hand-written `diag(exp(x))` needs**; it code-generated cleanly under
  Embedded Coder and would then overflow a small target at run time. The
  measured stack is now **160/352/608 B at n = 8/32/64** against 144/336/592 B
  hand-written — 1.11×/1.05×/1.03×, the same cost as writing the identical
  maths in vectorized form.

  Derivative values, shapes and the exported sparsity pattern are unchanged; the
  generated file simply stops computing entries it was already discarding, and
  its static second-derivative index tables shrink from `n²` to `n` entries.
  Nothing in your code needs to change — re-generate to pick it up. See
  ADR-0036.

- **A trip count handed to a subfunction is now guarded too.** If your function
  takes a loop bound and passes it on —

  ```matlab
  function y = main(x,N),  y = sub(x,N); end
  function y = sub(x,N),   y = 0; for k = 1:N, y = y + x(k)^2; end, end
  ```

  — the generated file was specialized to the `N` you generated at and said
  nothing about it. Calling with a **larger** `N` ran and quietly returned the
  answer for the generated size. Such files now open with `assert(N == <n>);`
  and reject the mismatch, the same way a bound used directly in the main
  function already did.

  The guard names **your** input, not the subfunction's parameter: if `main`
  takes `M` and the subfunction spells its parameter `N`, the guard is on `M`.

  It is deliberately conservative — a guard is emitted only when the bound
  reaches the subfunction as a plain variable, passed directly from your
  function, through *every* call. Passing an expression (`sub(x,N-1)`), passing
  a local, calling the same subfunction with two different bounds, or handing
  the bound on through a second subfunction all leave the file unguarded rather
  than risk an assertion that rejects correct calls. Those cases keep the
  previous behaviour.
- **A `loopbound` file that mixes a matching and a non-matching loop is now
  refused instead of quietly specialized.** If you declare `loopbound','N'` and
  the function has two loops —

  ```matlab
  for a = 1:N        % matches the declared maximum
  for b = 1:N-1      % does not
  ```

  — the second loop matched no declared bound, so it was given a *fixed* header
  inside a file whose bound is otherwise runtime. Every call below the maximum
  then ran that loop the wrong number of times and returned a wrong answer with
  no error; the file's own `assert(N <= Nmax)` is satisfied by exactly those
  calls. Generation now stops with an actionable message naming the trip count,
  the declared maximum, and three ways to resolve it.

  It refuses rather than generating something because the header that *would*
  be correct — `for b = 1:N-1`, under the assert the file already carries —
  cannot currently be expressed: loops are matched to a bound by trip-count
  value, and only `1:<name>` headers are emitted. Until bounds can be affine,
  stopping is better than emitting a file that is quietly wrong.

  Only loops in your main function whose *range mentions* a declared bound are
  affected — a deliberate fixed loop such as `for k = 1:3` is untouched, as are
  two loops that both match and a bound reached through a struct field. Note the
  check reads the loop range, so writing `M = N-1; for b = 1:M` still slips
  through; prefer spelling the bound in the range if you want it checked.

- **`loopbound` derivatives are now embeddable without a heap.** The runtime-bound
  guard (`assert(N <= Nmax);`) is emitted as the first statement of the generated
  function instead of only at the loop header. Previously the sizes that depend on
  the bound but run *before* the loop — your own `v = zeros(N,1)`, and the loop
  variable the transformation materializes — reached MATLAB Coder with no upper
  bound: with dynamic memory allocation enabled they became heap allocations, and
  with it disabled (the usual embedded setting) code generation failed with
  *"computed maximum size is not bounded"*. Derivative values are unchanged; the
  generated artifact is smaller (−224 B ROM on the `Nmax = 64` benchmark) and no
  longer requires a heap (+112 B stack). If you re-generate a `loopbound`
  derivative, expect one extra `assert` line at the top of the file.

  One behaviour change to be aware of: a guard is now emitted for **every**
  declared `loopbound` parameter, including one whose value happened to match no
  loop. Such a file previously ignored that parameter at runtime and now rejects
  values above the generation-time maximum — which is the correct reading of the
  option, but it can turn a previously-silent call into an assertion failure.

- **A derivative specialized to one trip count now says so — and stops computing
  the wrong answer when called with another.** If a loop bound names an input of
  your function (`for k = 1:N`) and you do *not* use `loopbound`, the generated
  file is specialized to the `N` you generated at. It previously accepted any
  `N`: a smaller one raised an index error, but a **larger one ran and quietly
  returned the answer for the generated size**, with an output vector of the
  requested length whose tail was never written. Such files now open with
  `assert(N == <n>);` and reject the mismatch.

  This is a **behaviour break in the correct direction**, but read it precisely:
  the guard fires whenever the bound *names* an input, which is not quite the
  same as the trip count depending on it. For `for k = 1:N` a mismatched call was
  already returning a wrong derivative and now fails instead. For a bound like
  `for k = 1:min(N,K)`, where the trip count may not actually vary with `N`, a
  call that used to be correct can now hit the assertion. If you need one file to
  serve several trip counts, that is what the `loopbound` option is for.

  The guard also makes these files code-generate with static memory allocation
  (no heap), which they previously could not. Note the check is a MATLAB-level
  precondition on the generated `.m`; generated C is fixed-size by construction,
  and `assert` does not generally survive into it with runtime checks off.

### Deprecated

- **The `adigatorGenFiles4*` solver-integration wrappers are deprecated.**
  `adigatorGenFiles4Fmincon`, `…Fminunc`, `…Fsolve`, `…Ipopt` and `…gpops2` are
  carried over from upstream ADiGator. They are now shipped for **continuity
  with the upstream repository only**: they are **not maintained**, and their
  functionality **may be reduced or removed in a future release** without a
  further deprecation period.

  Nothing changes in this release — they still work exactly as before. What
  changes is the promise: the feature gap below will not be closed.

  They emit **host-only** derivative files, so they do not support embedded code
  generation, `embed_mode`, `path`, the `csc` output form, or reverse mode. If
  you are writing new code, use the core generators — `adigatorGenJacFile`,
  `adigatorGenHesFile`, `adigatorGenDerFile_embedded` — and build the
  solver-shaped wrapper around them. If you have existing code calling the
  `Files4*` family, it keeps working, but treat it as carrying migration risk.

  The four `examples/optimization/{fmincon,fminunc,fsolve,ipopt}Ex/` examples
  demonstrate this family and are tagged deprecated for the same reason. Unlike
  every other shipped example, they are not expected to be embeddable. See
  ADR-0037.

## [2.0] — 2026-07-26

First release of the embedded fork. Everything below is new relative to the
upstream 1.x baseline; the core source-transformation differentiation algorithm
is unchanged.

### Added

- **Embeddable derivative files + MATLAB Coder / Embedded Coder codegen.** A new
  `embed_mode` option produces derivative files that code-generate to embedded C:
  - `'i'` (inline, the default for `adigatorGenDerFile_embedded`) — a single,
    fully self-contained file with the static index data inlined as source: no
    `global` variables, no runtime `load`, no `.mat`. This is the embeddable form.
  - `'c'` (classic) — the original three-file form (wrapper + `.mat` + derivative
    file) for interactive/host use.
- **Reverse-mode gradients and matrix-free products.** `adigatorGenRevGradFile`
  produces a reverse-mode (adjoint) gradient `<fn>_RGrd`, and `adigatorGenJtVFile`
  produces a `J'·v` (transposed-Jacobian-times-vector) product `<fn>_JtV` — both
  carrying near-zero static data for a vectorized scalar cost. Reverse gradients
  are also a first-class embeddable `DerType` through the `c`/`l`/`i` pipeline.
- **Struct and cell inputs.** The variable of differentiation may live inside a
  `struct` or `cell` input (including nested fields); the generators locate it
  and differentiate its numeric field.
- **N-D declared parameters.** Auxiliary inputs may be declared with more than two
  dimensions and sliced by loop counters, so time-`×`-actuator effectiveness
  tensors (and similar) index naturally.
- **`loopbound` — one file for a range of runtime sizes.** With
  `loopbound = 'N'`, a derivative file generated at a maximum trip count `Nmax`
  serves any runtime `n <= Nmax` (padded-program semantics): the loop prints with
  the runtime bound and an `assert(N <= Nmax)` guard, and the executed prefix
  agrees exactly with a file generated directly at `n`. Composes with nested
  runtime bounds and N-D parameters, and supports gradient, Jacobian, and
  (scalar-cost) Hessian.
- **Compressed-sparse-column output (`der_output = 'csc'`).** Returns the
  derivative's structurally-possible-nonzero vector in CSC order, with the
  constant pattern exported once as compressed-sparse-column metadata
  `output.{Jacobian|Gradient|Hessian}CSC` (`Size`/`ColPtr`/`RowIdx`/`Nnz`/
  `IndexBase`) — the single canonical sparse-pattern representation, used in both
  `matrix` and `csc` modes. A downstream (embedded) solver consumes the value
  vector and constant `ColPtr`/`RowIdx` directly, assembling — or never forming —
  the dense matrix itself. Host-only `adigatorCSCToLocs` / `adigatorCSCToSparse`
  reconstruct coordinate / MATLAB-sparse forms when needed.
- **Derivative-level selection (`der_levels`).** The Hessian file's returned
  outputs can be trimmed to a requested subset of `{Hessian, gradient, function}`.
- **`slim_embed` dead-code slicing.** Trims unread `_location`/`_size` chains and
  their index tables from the generated file, shrinking the embedded artifact.
- **Options helper (`adigatorOptions`)** covering all of the above, and derivative
  file generators (`adigatorGenJacFile`, `adigatorGenHesFile`,
  `adigatorGenDerFile_embedded`) that take the user function's own input signature.

### Changed

- Derivative output shapes follow a documented set of conventions (see
  `adigatorDerivativeConventions.m` and the user guide): the Jacobian is `m×n`,
  the scalar-cost gradient is a column, and the wrapper outputs use canonical
  names and order.
- The derivative-file generators require the differentiated function to return a
  **single numeric array**; a `struct`/`cell` *output* through these generators
  raises an actionable error (struct/cell *inputs* are fully supported).
- Unsupported constructs (data-dependent indexing, induced/spectral matrix norms,
  and similar) raise a clear, actionable error naming the construct and a
  supported rewrite, rather than producing an incorrect derivative.

### Deprecated

- **`embed_mode = 'l'` (coderload).** It does not code-generate under Embedded
  Coder, and its compiled footprint converges with inline `'i'`. Prefer `'i'`;
  `'l'` is retained for now with removal planned in a later release.

### Known limitations

Each of the following is **fail-loud** (a clear, actionable error) or has a
documented workaround — none produces an incorrect derivative silently.

- **Loopbound Hessian of a vector/matrix-output function** is not yet supported;
  it fails loud with `adigator:loopbound:vectorhessian`. Scalar-output loopbound
  Hessians *are* supported (generated at `Nmax`, correct for any `n ≤ Nmax`).
- **Re-differentiating a loopbound-generated file** (e.g. taking a Hessian)
  without re-passing the `loopbound` option fails loud with
  `adigator:loopbound:rediff` — pass the option so the runtime guard is
  re-synthesized. Reverse mode does not apply to loopbound files (it needs
  unrolled loops, which `loopbound` forbids).
- **Reverse-mode adjoint of a non-scalar matrix division** (`A/B` with a
  non-scalar denominator) is not supported; it is guarded with an actionable
  error rather than returning a wrong adjoint.
- **Embedded Coder (ERT) code generation of two forms**, both of which compile
  fine under plain MATLAB Coder (`coder.config('lib')`) — the limitation is the
  stricter ERT target only:
  - the *unslimmed* inline Hessian — use the default `slim_embed = 1`, which
    ERT-codegens;
  - the *unrolled* subscripted scalar-cost derivative — use the **rolled** form
    (`unroll = 0`), the recommended form for loop-based costs, which ERT-codegens
    with a flat, `n`-independent structure.
- **`if`-guarded `while`-counter indexing**: a narrow N-D-indexing edge case
  raises a raw `MATLAB:badsubscript` instead of the actionable
  data-dependent-index error.
- **The inherited `adigatorGenFiles4{Fminunc,Fsolve,Fmincon,Ipopt,gpops2}`
  solver wrappers** are host-only and not at embedded feature parity (no
  `embed_mode`, `path`, `der_output='csc'`, or reverse mode). They are retained
  for drop-in compatibility with upstream ADiGator; use the core generators
  (`adigatorGenJacFile` / `adigatorGenHesFile` / `adigatorGenDerFile_embedded`)
  for embeddable derivatives.

### Attribution

Preserves the upstream copyright (© Matthew J. Weinstein and Anil V. Rao) and the
GNU GPL v3; adds the fork's contributions (© Pedro Lourenço and GMV).

[2.0]: https://github.com/pdlourenco/adigator-embedded/releases/tag/v2.0
