# ADR-0002 — Matrix-induced norms raise an error rather than mis-differentiating

## Status

Accepted — 2026-06-18. Back-filled from issue #28 (`norm` overloading in `@cada`).

## Context

Overloading `norm` for `@cada` makes it differentiable. The vector p-norms
(`2`, `1`, `Inf`, `-Inf`, general `p`) and the Frobenius norm (`'fro'`) have
closed-form derivatives that rewrite to elementary operations ADiGator already
differentiates. The **induced / spectral matrix norms** (`norm(A)`,
`norm(A,2)`, `norm(A,Inf)` on a matrix, etc.) do not: their derivative requires
the singular value decomposition, which ADiGator has no rule for.

Leaving the matrix case to fall through to a generic path produces a derivative
that is silently wrong — the worst failure mode for an AD tool, because the
generated code runs and returns plausible numbers.

## Decision

Rewrite the differentiable norms to elementary operations; for the induced /
spectral matrix norms, **raise a clear, specific error** at generation time
explaining that the SVD-based derivative is unsupported, rather than emitting a
wrong derivative.

## Consequences

- A user hitting the unsupported case gets an actionable message at generation
  time, not a wrong number at run time — consistent with the project principle
  "warnings/errors are actionable" and the C-5 contract in `DESIGN.md`.
- The guard must cover the `Inf`/`-Inf` matrix cases too, not just the default
  2-norm (a matrix `Inf`-norm must not slip past into the vector path).
- Pinned by `unit_tests/test_norm_rules.m`.
- **Revisit** if an SVD derivative rule is added to `@cada`; the error becomes a
  real rule at that point.

## Alternatives considered

- **Fall through to a generic/numeric derivative.** Rejected — silently wrong
  derivatives are the failure mode an AD tool exists to prevent.
- **Approximate the spectral norm derivative** (e.g. via the dominant singular
  vector). Rejected for now — correct only at simple singular values, fragile
  near multiplicities, and out of scope for the embedded use cases that
  motivated #28.
