# ADR-0018 — CasADi as a dev-only independent oracle (same-source) + codegen benchmark

## Status

Accepted — 2026-06-30. Tracked by issue #87; supports the #80 v2 engine work.

## Context

The Gap B analysis (#80) concludes the principled fix is a **v2 derivative-propagation
engine** — a re-architecture of `cadaOverMap` / `cadabinaryarraymath`, the most
"a-wrong-derivative-is-worse-than-an-error" code in the repo (REVIEW_CONTEXT.md
principle 1). Such a rewrite needs an **independent ground truth**.

Our existing oracles are valuable but not method-independent: `oracleKnownDeriv`
and the hand-analytic references are hand-coded (a transcription risk), cross-mode
equality only proves the modes *agree* (not that they are *right*), and finite
differences are truncation-limited. None is an independent re-derivation by a
different AD engine.

**CasADi** computes derivatives by a symbolic expression graph — a method wholly
independent of ADiGator's source transformation — and emits C, so it can serve as
both an independent **correctness oracle** and a **codegen benchmark**. The
Monte-Carlo V&V plan (ADR-0007 Phase D) already anticipated a "differential-vs-upstream
/ Symbolic-Toolbox spot oracle"; CasADi is a stronger, C-capable instance of that.

Proof of concept (issue #87): on the *same unmodified* showcase m-files, ADiGator
and CasADi agree to machine precision — Jacobian (`vvecfun`) `numErr = 0`, Hessian
(`scostfun`, rolled loop) `4.4e-16`.

## Decision

Adopt CasADi as a **dev-only, tool-gated** V&V instrument, with three properties:

1. **Same source, no transcription.** Both engines are operator-overloading AD, so
   the harness feeds *one* unmodified function m-file to both — ADiGator via `@cada`,
   CasADi via the `SX` symbolic type — eliminating the hand-transcription gap that
   would otherwise undermine an oracle. Comparison is on **reconstructed dense
   values** (`full(J)`/`full(H)`), so the engines' differing sparse layouts /
   nonzero orderings never enter (no C-1..C-6 coupling).
2. **Tool-gated, skip-clean, not shipped.** `bench/casadiAvailable.m` detects
   CasADi; `tests/system/SCasadiOracleTest.m` `assumeTrue`s on it and skips cleanly
   when absent — exactly as the Coder-gated system tests skip without a license. It
   is an **extended-suite** test, not the PR gate. CasADi binaries are **not
   committed** (50 MB+, platform-specific): the harness uses whatever CasADi is on
   the MATLAB path (e.g. a developer `startup.m`), or addpath's `CASADI_DIR` if set
   (for CI).
3. **Benchmark is a reference, not a floor.** CasADi also emits C, so it can anchor
   a ROM/RAM/stack/runtime comparison — but it targets optimal-control / large-scale
   NLP, *not* MCU-embedded. It is therefore a "mature general AD-tool" reference; the
   hand-coded **analytic stays the embedded floor**, with ADiGator expected between
   them. (The benchmark side is not built in this ADR — only the correctness oracle.)

The first battery is the SX-consumable showcase cases: `vvecfun/jacobian`,
`scostfun/{gradient, gradient-reverse, hessian}`, `vcostfun/gradient`. `vfun` is
omitted — its `y = zeros(n,1); y(k) = <expr>` (preallocation + indexed symbolic
store) is not SX/MX-consumable (verified); its math is identical to `vvecfun` (its
vectorized sibling, included) and its generated code is covered by the cross-mode
and analytic oracles.

## Consequences

- The #80 v2 engine rewrite has an independent C-capable oracle from day one; a
  value error introduced by the rewrite is caught by a different method, not just by
  our own agreeing modes.
- New developers get the oracle for free if CasADi is on their path; CI gets it by
  exporting `CASADI_DIR`. With neither, the test skips — never red for absence.
- No new shipped/runtime dependency and no new committed artifact; the only addition
  is dev/test code.
- **Revisit if:** we want the benchmark side wired (a follow-up), or the battery
  grows enough to need its own extended-CI job, or a target needs `MX` / a
  "transcribe-only" path because it is not `SX`-consumable.

## Alternatives considered

- **Hand-transcribe each function into CasADi's API.** Rejected — a transcription
  error makes the "oracle" silently wrong, defeating its purpose. The same-source
  route removes the gap entirely and is verified to work (incl. `scostfun`'s rolled
  loop / indexing / accumulation under `SX`).
- **Symbolic Math Toolbox only.** It is a fine MATLAB-level exact oracle (already in
  the Phase-D plan) but emits no C and gives no codegen reference; CasADi adds both.
- **Commit the CasADi binaries / make it a hard dependency.** Rejected — 50 MB+,
  platform-specific, and it would put a heavy tool on the PR gate. Tool-gated +
  skip-clean keeps it dev-only, matching the Coder-gated system suite.
- **Tapenade / ADOL-C / Enzyme.** Less convenient from MATLAB and no symbolic
  MATLAB interface; CasADi uniquely gives independent AD + C codegen + an `SX`
  interface that consumes our source m-files directly.
