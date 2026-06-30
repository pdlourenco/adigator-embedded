# ADR-0019 — Rolled form is the embeddable path for subscripted/loop derivatives; fixed-size scatter deferred to R21

## Status

Accepted — 2026-06-30. Issue #80 (Gap B); realized by PR #89 (Path A). Records a
*determination* (which path delivers embeddability), not a code change — kin to
[ADR-0016](ADR-0016-matrix-free-products-efficiency-path.md).

## Context

The #80 mandate: **every generated derivative except the `classic`/`c` path must
codegen under strict Embedded Coder (ERT)**. Gap B — subscripted scalar-cost
derivatives (the rolled/loop `J = Σₖ φ(xₖ)` shape) — was assumed to require a core
rewrite of the derivative-accumulation engine (`cadaOverMap`/`cadaPrintReMap`/
`cadabinaryarraymath`), because the *unrolled* form grows its accumulator and
compiles to an **O(n²) stack** (measured 16.9 KB at n=64), which is unusable on an
embedded target.

The #80 feasibility spike measured the alternative and changed the picture:

- The **rolled** form (`unroll=0`) ERT-codegens with a **flat, n-independent
  stack** (~96 B at n = 8/32/64). Its accumulator is pre-allocated at its final
  size *before* the loop, so there is no field-add-after-read and the temps are
  reused — bounded stack. The catastrophic O(n²) stack was the *unrolled* choice,
  not inherent to subscripted derivatives.
- The rolled Hessian's only remaining ERT blocker was a contained **Gap-A-family
  static-data read-then-add** (the de-dup emitter aliased an index to a sibling
  struct field), fixed in PR #89 (route the shared copy through a local temp).

So **embeddability does not require the engine rewrite.** What the rolled form does
*not* give is *efficiency*: it does full-size-`n` vector ops per iteration for a
1-element update — **O(n²) runtime** — and reverse mode still requires `unroll=1`
(hence the unrolled O(n²) **stack**).

## Decision

Two-part determination:

1. **Path A — ship now (PR #89).** The **rolled** form is the embeddable path for
   forward subscripted/loop derivatives (gradient, Jacobian, Hessian). The only
   change needed was the contained ERT-safe de-dup fix; no engine rewrite.
2. **Path B — defer to R21.** The **fixed-size scatter accumulation** engine
   (write each contribution to its already-known nonzero index → **O(n) runtime +
   O(n) stack**, and bounded-stack **reverse** mode) is a separately-scoped engine
   change. It is **spiked tractable** (the final location set is known pre-print
   from the RUNFLAG==1 overmap pass; single choke point `cadaPrintReMap.m`; blast
   radius ~15–20 `@cada` files) but carries the highest correctness stakes, so it
   gets **its own ADR** when scoped and is validated by the full Monte-Carlo +
   CasADi ([#87](https://github.com/pdlourenco/adigator-embedded/issues/87),
   [ADR-0018](ADR-0018-casadi-independent-oracle.md)) apparatus.

Consequence boundary: until R21, the **unrolled** O(n²)-stack form and **reverse**
mode (which requires `unroll=1`) are not embeddable — for embedded forward
subscripted/loop derivatives, **prefer rolled**.

## Consequences

- Forward gradient/Jacobian/Hessian over the rolled/loop shape are ERT-embeddable
  now, with bounded stack — the #80 correctness mandate is met for the forward
  subscripted case without touching the accumulation engine.
- The risky engine rewrite is deferred to a deliberate R21 with an independent
  C-capable oracle already in place — a contained fix shipped now de-risks it.
- Reverse-mode bounded stack and O(n)-runtime efficiency are explicitly *not*
  delivered yet; they are the R21 deliverables.
- **Revisit if:** an embedded target needs reverse mode or hits the O(n²) *runtime*
  of the rolled forward form before R21 lands — that pulls R21 forward.

## Alternatives considered

- **Do the engine rewrite now (the original assumption).** Rejected: large blast
  radius and the highest correctness risk in the repo, and — per the spike —
  *unnecessary* for embeddability. The rewrite is an efficiency play, not a
  correctness one; sequencing it after a contained fix is the safer order.
- **Variable-size pre-allocation of the unrolled accumulator** (an earlier idea):
  makes the unrolled form codegen but keeps the **O(n²) stack** — a hollow
  milestone (codegens, not embeddable). Rejected in favour of preferring rolled.
- **Roadmap rows only, no ADR.** The forward work is already gated by ROADMAP
  R20/R21 + the #80 spike, and the Path A change is bug-fix-shaped (like #81/
  approach D, no ADR). But the A-now/B-later split locks in a trade-off a future
  PR will revisit (§4), and the *rationale* — embeddability ≠ rewrite — is exactly
  what that PR will want; an ADR (cf. ADR-0016) records it durably.
