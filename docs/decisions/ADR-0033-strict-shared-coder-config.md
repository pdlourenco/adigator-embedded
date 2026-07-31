# ADR-0033 — A single strict Embedded Coder config (`adigatorCoderConfig`)

## Status

Accepted — 2026-07-29. Extends the V&V-for-release effort from *correctness*
(ADR-0032 coverage floor + the value oracles) to *embeddability*. Realizes the
first half of issue #80's "compile everything through Embedded Coder (ERT)"
objective as a shared, strict, drift-proof config; the stack-ceiling gate that
completes it is #80a-2 (see Consequences).

## Context

The fork's purpose is ERT-capable embedded code, and the V&V gate must prove the
generated derivatives *are* ERT-capable — not merely assume it. Two problems:

- **Config drift.** Five sites code-generated embedded derivatives, each with its
  own inline `coder.config('lib','ecoder',true)`: `SCodegenTest`,
  `SRolledErtCodegenTest`, the Monte-Carlo `oracleCodegenEquivalence`,
  `bench/derivShowcaseC`, and `bench/loopboundPaddingPenalty`. A "strict
  everywhere" policy spread across five literal copies is one edit away from
  being strict in four places — exactly how a gate quietly weakens. The copies had
  already begun diverging: as of B35/B36 (#209/#211) two of the five —
  `bench/loopboundPaddingPenalty` and `SRolledErtCodegenTest` — set
  `EnableDynamicMemoryAllocation=false` for themselves while the other three did
  not. Strictness arriving copy-by-copy is the drift, whichever direction it
  runs.
- **The config mostly wasn't strict.** Three of the five copies set only the ERT
  target and turned the HTML report off, so an *unbounded* `coder.varsize`
  derivative would still code-generate for them (needing `malloc` on an MCU that
  has none) and pass the gate. The two that *did* forbid dynamic allocation got
  it as a consequence of B35/B36 rather than from any shared policy — which is
  the same drift seen from the other side, and is exactly what ADR-0034 decision
  2 now requires of every embeddability claim. This helper is what makes that
  requirement enforceable in one place instead of five.

Both feed the deeper lesson from #80's Gap-B analysis: **ERT exit-success is
necessary but not sufficient for embeddability.** A *bounded-but-large*
derivative (the "hollow milestone": ERT-clean yet O(n²) stack — 16.9 KB at
n=64; ~67 KB at n=128 by O(n²) extrapolation) code-generates and would ship a stack-overflow. This is
the codegen twin of ADR-0032's "coverage is necessary, not sufficient".

## Decision

Introduce **`util/adigatorCoderConfig.m`** — the single definition of the strict
Embedded Coder config — and route every codegen site through it.

- Returns `coder.config('lib','ecoder',true)` **+ `EnableDynamicMemoryAllocation
  = false`** (no `malloc`; an unbounded-varsize derivative now fails codegen as a
  *test failure*) + `GenerateReport=false`; a `GenCodeOnly` name/value for sites
  that assert ERT *acceptance* without a C toolchain (`SRolledErtCodegenTest`).
- Plus the **portable, deterministic embedded-C profile** a real embedded
  Embedded Coder target uses (cross-checked against a reference embedded config):
  `TargetLang='C'`, `TargetLangStandard='C99 (ISO)'` (pinned, vs the `Auto`
  default), `CodeReplacementLibrary='None'` (portable ANSI), `PurelyIntegerCode
  =false` (derivatives are `double`). These are mostly the current defaults, set
  **explicitly** so the strict profile is version-proof. `SupportNonFinite` is
  also set explicitly to its (safe) default **`true`** — precisely because it is
  the setting a shifted default would make *most* dangerous: a derivative can
  legitimately produce Inf/NaN (`1/x`, `sqrt`/`log` near 0), and a `false` here
  generates code that assumes finiteness, silently mis-computing those (Principle
  1). A reference embedded config keeps it on; a lean non-finite-off build stays
  an explicit caller opt-out.
- All five sites consume it, so the strict policy has one source of truth and
  cannot drift. It is also **user-facing** (shipped in `util/`): the config an
  end user should hand `codegen` when embedding a generated derivative.
- **Scope is exactly the config.** Adding `EnableDynamicMemoryAllocation=false`
  was verified to leave every exercised ERT codegen consumer green
  (`SCodegenTest`, `SRolledErtCodegenTest`, `MCSmokeTest`'s codegen oracle,
  `SCodegenShowcaseTest`) — the current cases were already dynamic-alloc free,
  so this tightens the gate without breaking it. `SLoopboundPaddingTest` (the
  fifth site) is the identical config-substitution but filters locally on the
  absent standalone `gcc`/`-fstack-usage` toolchain; it runs on the CI extended
  job.

## Consequences

- One strict config, five consumers, zero drift; `REQ-T-10` now names the shared
  helper and the `EnableDynamicMemoryAllocation=false` flag.
- **The gate is tightened, not yet complete.** `EnableDynamicMemoryAllocation
  =false` rejects only *unbounded* varsize; the *bounded* O(n²)-stack case still
  passes. The completion is a **stack ceiling** on the compiled `-fstack-usage`
  footprint — reusing the existing `measureErtFootprint` helper (R17c/ADR-0027),
  gating by the *property* (stack is O(n), caught via an n-vs-2n scaling check or
  an absolute bound) — tracked as **#80a-2**. That is what turns "codegens" into
  "embeddable".
- **The bench baselines were measured under the *old* config.** `derivShowcaseC`
  and `loopboundPaddingPenalty` now build with the strict profile (`C99` pinned,
  `CodeReplacementLibrary='None'`, dynamic allocation off). `loopboundPaddingPenalty`
  already had dynamic allocation off (B35/B36), so for it only the C99 and
  code-replacement pins are new; `derivShowcaseC` picks up all three. The committed `bench/SHOWCASE.md` / guide
  footprint tables were honest under the old config, so nothing needs
  regenerating now; but **the next regeneration may shift ROM/stack values, and
  that delta must be attributed to this config change, not read as a code
  regression.**
- **The `× slim_embed` axis is transitional.** Several consumers still sweep
  `slim=false`/`true` (`SCodegenTest` `FullData`/`SlimData`, the CI_PLAN two-point
  rows). #80b removes `slim_embed` as a user option (always-on + automatic
  internal fallback), collapsing that axis — at which point the `FullData` case
  becomes the *forced-internal-fallback* test. This ADR deliberately does **not**
  deepen the slim axis; the config helper is surface-stable and survives #80b.
- **User-facing surface.** Shipping `adigatorCoderConfig()` adds one public
  function to `util/`. It composes with the #199 single-entry-point direction
  (the blessed embed config a user pairs with the one generator entry).
