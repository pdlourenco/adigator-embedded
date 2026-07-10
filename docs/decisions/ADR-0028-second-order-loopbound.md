# ADR-0028 — Second-order (`DERNUMBER>=2`) loopbound via derivative-level-agnostic runtime-header re-emission

## Status

Accepted — 2026-07-10

## Context

The `loopbound` option (roadmap R3, issue #6 Tier 1, ADR predates this) lets a
rolled derivative file generated at a maximum trip count `Nmax` serve any runtime
trip count `n <= Nmax`: the outermost (and constant-bound inner) loops print with
a runtime bound `for k = 1:name`, guarded by `assert(name <= Nmax)`, and the exit
variables take the loop *overmap* (the union over every iteration's exit state)
so post-loop code stays correct at any `n` with structural zeros in the skipped
tail. B27 ([#162](https://github.com/pdlourenco/adigator-embedded/issues/162))
extended the exit-union to *inner* runtime-bound loops.

All of that fired at the **first derivative level only**: the runtime-header /
assert emission (`adigatorForInitialize`) and the exit-union
(`adigatorForIterEnd`) were gated on `ADIGATOR.DERNUMBER == 1`. Re-differentiating
a loopbound file — a **Hessian** (or nth derivative) *of* a loopbound gradient —
therefore hit two failures: the gradient file's own `assert(name <= Nmax)` source
line choked the reprint pipeline (made actionable + fail-loud as
`adigator:loopbound:rediff` in
[#173](https://github.com/pdlourenco/adigator-embedded/issues/173) PR A / #176),
and even bypassing that, the second-derivative loop would **specialize to a
literal `Nmax`** and the exit derivative would be **silently zeroed** at `n<Nmax`
(the B27 bug, at the Hessian level). PR A deliberately kept re-diff fail-loud;
this ADR (PR B) is the decision to actually *support* it.

## Decision

Make the loopbound runtime-header re-emission and the exit-union **derivative-
level-agnostic**, and treat the gradient file's source `assert` as a
**regeneration marker** owned by a single mechanism:

1. **`lib/adigatorForInitialize.m`** — the outer-loop and inner-loop loopbound
   emission drop the `DERNUMBER == 1` gate (keeping `FILE.FUNID == 1` and the
   `adigatorLoopboundMatch` value-match). The inner-loop block is restructured so
   the loopbound `assert` + `for c = 1:name` path is reachable at *any* level;
   previously the `DERNUMBER != 1` branch re-emitted the loop from the raw loop
   variable, which for a runtime bound is the `1:N` **range object**, producing a
   malformed `for c = 1:(1:N)` header ("colon operands must be real scalars") that
   silently mis-ran the inner loop.

2. **`lib/adigatorForIterEnd.m`** — the runtime-bound exit-union gate drops
   `DERNUMBER == 1` (keeping `FILE.FUNID == 1` and the loopbound match). The B27
   `INNEREXITCOUNTS` machinery (computed unconditionally in
   `adigatorAssignOvermapScheme`) then applies at the second derivative level
   with no further change.

3. **`lib/adigatorPrintTempFiles.m`** — the `assert(name <= max)` source line is
   **dropped and regenerated**: when the current pass has the `loopbound` option
   set *and* the guard names a loopbound parameter, the printer drops the source
   copy (the loop machinery re-synthesizes it via (1)), avoiding a duplicate
   guard. Otherwise — re-differentiation without the option, or a user's own
   `assert` — it keeps PR A's fail-loud `adigator:loopbound:rediff`.

The loopbound option already reaches the Hessian pass unchanged
(`adigatorGenHesFile` threads the same `opts` to both `adigator` calls), so no
generator change is needed. Validated against analytic, direct-`n`, the CasADi
oracle ([#87](https://github.com/pdlourenco/adigator-embedded/issues/87)), and
finite differences across `n<Nmax` for single-level, nested inner-exit,
triple-nested, and coupled off-diagonal Hessians; pinned by `ILoopboundTest`.

## Consequences

- A loopbound Hessian is now a first-class supported output: the `Nmax` file's
  Hessian at `n<Nmax` equals the `n`-sized program with a structurally-zero
  padded tail. The `loopboundHessianReDiffTripwire` `KnownIssue` self-heals into
  live numeric guards (`loopboundHessianMatchesNsizedProgram`,
  `nestedLoopboundHessianInnerExit`, `coupledLoopboundHessianOffDiagonal`).
- The three gates become value-driven (`adigatorLoopboundMatch`) rather than
  level-driven. A **non-loopbound** generation is unaffected: `LOOPBOUND` is empty
  so the match returns `''` and every widened branch is inert — confirmed by the
  full `ci_local` regression sweep.
- The single-source-of-truth choice for the guard (loop machinery emits it;
  printer drops the source copy) keeps first- and second-derivative files
  emitting the guard identically, so there is one place to change the guard shape.
- **Revisit when:** nth derivative (`DERNUMBER >= 3`, roadmap R22/#85) lands — the
  gates are already level-agnostic, but the guard-drop discriminator and the
  padded-tail validation must be re-swept at order ≥3. Also revisit if the guard
  emission shape in `adigatorForInitialize` changes: the printer's drop-regex and
  the emitter must move in lockstep (a shared shape constant would remove that
  coupling; noted on #173, deferred).
- **Not yet swept:** the pinned Hessian tests cover **scalar-output** loopbound
  functions (the ADR-scoped headline `J = Σ φ(x_k)` and its curvature) across
  single-level, nested inner-exit, triple-nested, and coupled off-diagonal
  shapes. A **vector/matrix-output** loopbound Hessian at `n<Nmax` is not yet in
  the battery — the exit-union mechanics are output-shape-agnostic, but the
  second-order union is the danger zone, so a vector-output sweep is a warranted
  follow-up before advertising that shape.

## Alternatives considered

- **Keep re-diff fail-loud (ship nothing beyond PR A).** Rejected by maintainer
  decision: the single-level scalar-cost Hessian is the headline loopbound use
  (`J = Σ φ(x_k)` and its curvature), and it works with a small, value-gated
  change. Fail-loud was the right *interim* (principle 1), not the end state.
- **Pass the source `assert` through verbatim (printer re-emits it) instead of
  regenerating.** Rejected: adigator must re-analyze the loop to differentiate
  its body, so the runtime header necessarily comes from the loop machinery
  anyway; passing the source assert through as well yields a *duplicate* guard,
  and splits guard ownership across two mechanisms.
- **Ship single-level only, keep nested inner-runtime-bound fail-loud.**
  Considered (it was the recommended cautious scope), but the spike showed the
  nested case needed only the inner-header restructure — once the inner loop runs
  at the right count, the existing `INNEREXITCOUNTS` union is correct at second
  order — so the full fix carried little extra risk and avoided shipping a
  fail-loud guard we would immediately remove.
- **Add a dedicated second-order exit-union path.** Unnecessary: `INNEREXITCOUNTS`
  is computed level-independently in `adigatorAssignOvermapScheme`; the only
  blocker was the level-gated *consumption* and the malformed inner header.
