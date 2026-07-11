# Changelog

All notable, user-facing changes to this ADiGator fork are recorded here. The
format follows [Keep a Changelog](https://keepachangelog.com/), and the project
follows [semantic versioning](https://semver.org/).

This is the **GMV embedded fork** of ADiGator, built on upstream ADiGator 1.x by
Matthew J. Weinstein and Anil V. Rao and distributed under the GNU GPL v3. The
version numbering restarts at 2.0 to reflect the accumulated new capability (see
below); it is not a patch of upstream 1.x.

## [2.0] — 2026-07-11

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
- **Alternative output forms (`der_output` + `*Locs`).** `der_output = 'nonzeros'`
  returns the derivative's nonzero vector in a fixed pattern order, with the
  sparsity pattern exported once via `output.JacobianLocs` / `output.HessianLocs`,
  so a downstream solver assembles (or never forms) the dense matrix itself.
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

### Attribution

Preserves the upstream copyright (© Matthew J. Weinstein and Anil V. Rao) and the
GNU GPL v3; adds the fork's contributions (© GMV / Pedro Lourenço).

[2.0]: https://github.com/pdlourenco/adigator-embedded/releases/tag/v2.0
