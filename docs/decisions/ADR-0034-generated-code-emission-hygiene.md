# ADR-0034 — Generated-code emission hygiene: the no-heap target is a generation-time obligation

## Status

Accepted — 2026-07-30

## Context

This fork's product is not the derivative *value* — it is the derivative *file*.
A file that computes the right numbers in MATLAB but cannot be compiled for the
target has not delivered anything (`REVIEW_CONTEXT.md` principle 1 says a wrong
derivative is worse than an error; the corollary here is that an unshippable
right derivative is still a failure, just a loud one).

Two defects found while consolidating the Embedded Coder configuration (#80a-1)
share a root: **nothing in the pipeline holds the emitter to what the target
accepts.** Each was found by accident, from the far end, long after the emission
that caused it.

1. **B35 — the runtime-bound guard is emitted too late.** `adigatorForInitialize`
   emits `assert(N <= Nmax)` immediately before a `loopbound` loop header. But
   the bound also sizes expressions that run *earlier*: the user's own
   `v = zeros(N,1)`, and the `cadaforvar<k> = 1:N` loop-variable range the
   machinery materializes for itself. Those reach Coder unbounded. With dynamic
   memory allocation enabled — the `coder.config` default, and what the bench
   happened to use — they silently became heap `emxArray`s, so the artifact
   *appeared* to build. With it disabled, generation failed outright. No
   `loopbound` derivative had ever been embeddable, and the whole `loopbound`
   test family was green throughout.

2. **The `NVAROFDIFF`-vs-`DERNUMBER` split in synthesized names** (open; see
   `ANALYSIS.md` §1.3g, B29–B31/B33–B34). `@cadastruct`'s fallback-naming arm
   builds `cada<k>s<n>` identifiers; three siblings (`transpose`, `reshape`,
   `repmat`) key `<k>` off `ADIGATOR.NVAROFDIFF` while the five repaired sites
   now key it off `ADIGATOR.DERNUMBER`. `NVAROFDIFF` is invariant across the two
   Hessian passes, so it can collide with a live pass-1 identifier — a silently
   wrong derivative, not a loud one. The mixed state is itself a hazard.

Both are *emission* defects: the emitter's output is legal MATLAB and numerically
correct, and wrong in a property nothing checks. Fixing the first immediately
surfaced a third of the same kind — **B36**, a loop range over a runtime-named
scalar is unbounded even *without* the `loopbound` option (`ANALYSIS.md` §1.3j) —
which is why this ADR states a principle rather than recording one fix.

## Decision

**The strict-ERT target is a generation-time obligation, and the generated file
carries its own bounding evidence.**

Concretely, three commitments:

1. **A runtime bound is guarded once, at the top of the function it bounds.**
   `adigatorFunctionInitialize` emits `assert(<name> <= <max>);` for **every**
   declared `loopbound` parameter as the first statement of the main function
   body, before any user line. `adigator.m` already validates each name to be an
   input of the main function, so all are in scope there. Guards are emitted for
   every *declared* bound, not only those a loop's trip count matched: the
   envelope claim is "this file was analyzed at `N = max`", and it applies to
   `N`-dependent sizing whether or not a rolled loop happened to match.
   The per-loop guards **stay** — they are what the re-differentiation path keys
   on (`adigatorPrintTempFiles`, #173) and a redundant `assert` costs nothing in
   the generated C.

2. **"Embeddable" means static memory allocation.** A codegen test that leaves
   `EnableDynamicMemoryAllocation` at its default proves almost nothing: the heap
   absorbs exactly the unbounded sizes an embedded target cannot. Tests that
   claim embeddability set it to `false` explicitly (see also ADR-0033's shared
   strict config).

3. **Emitted identifiers are a surface.** Changing how a synthesized name is
   built changes shipped artifacts, so the `NVAROFDIFF` → `DERNUMBER`
   harmonization is a deliberate, separately-sequenced change (with a
   regeneration pass over committed artifacts), not a drive-by fix. It is
   **open** under this ADR, not decided by it.

4. **A guard shape is a re-differentiation surface, not just an emission.** Every
   generated file is the *source* of the next derivative pass, so anything the
   emitter adds must be recognized by `adigatorPrintTempFiles`'s classifier and
   `adigatorParseTape`'s keep-always whitelist — both reading the same shared
   shape (`util/adigatorLoopboundGuard`). B36 is the proof: adding `==` without
   teaching the classifier would have sent every Hessian of a named-trip-count
   function into the generic `Cannot process statement:` error. Adding an emitted
   construct means extending the recognizers **and their lockstep test** in the
   same change, and pinning the behaviour at **3rd** order — 2nd order is where
   the recognize-drop-re-record path first runs, 3rd is where it runs twice,
   which is what separates a one-shot bug from a cumulative one.

   The recognizer must also be **gated**, not just widened. A shape we emit is
   also a shape a user may write: the equality arm accepts a source guard only
   when it sits in the main function and names a main-function input, so a user's
   own `assert(nSteps == 5)` keeps failing loudly instead of being silently
   deleted from their derivative. A recognizer with no gate converts someone
   else's safety check into nothing.

## Consequences

- **`loopbound` derivatives are embeddable.** Measured on the `scostfun_lb`
  gradient (inline `i` / ERT, `Nmax = 64`): padded ROM 4624 → 4400 B (−224),
  stack 240 → 352 B (+112 — the range is now stack-resident rather than
  heap-allocated; +112 is not a straight transfer, a `1:64` double range is
  512 B, so Coder is also folding/aligning), heap requirement gone. Values
  unchanged.
- **Two new behaviours for a *declared-but-unmatched* bound.** A `loopbound` name
  whose value matched no loop's trip count previously produced no guard at all;
  it now gets a hoisted one. So (a) the generated file rejects `N > Nmax` at
  runtime where it previously ignored `N` — which is what decision 1 intends, but
  it is user-visible; and (b) re-differentiating such a file *without* the
  `loopbound` option now raises `adigator:loopbound:rediff` where it previously
  succeeded. Both are fail-loud and actionable.
- **Scope: forward mode only.** Reverse mode rejects a rolled loop earlier
  (`adigator:fwdtape:controlflow`), so no `loopbound` file reaches
  `adigatorGenRevGradFile`. Note that `util/adigatorForwardTapeSlice` selects
  statements by matching `S(k).lhs`, and the guard has none — were reverse mode
  ever extended to `loopbound`, the guard would be silently dropped from the
  value tape and decision 1 would not hold there. Not a defect today; a
  precondition on any future reverse-mode `loopbound` work.
- **Decision 2 is enforced everywhere (B36 landed).** `bench/loopboundPaddingPenalty`
  now measures with `EnableDynamicMemoryAllocation = false`. It could not before:
  its *exact-`n`* baseline half is generated **without** `loopbound`, so it still
  emitted `cadaforvar<k> = 1:N` by name with no declared maximum to hoist
  (`ANALYSIS.md` §1.3j). B36 gives that case its own guard —
  `assert(N == n);`, an **equality**, because such a file is *specialized* to one
  trip count rather than *padded* to a maximum.
- **Enforcing decision 2 changed a published measurement, which is the point.**
  Every padding-penalty figure this project had published was taken with the heap
  on. Measured honestly, the exact-`n` files shed the `emxArray` machinery they
  had been carrying and the penalty roughly **doubled** at small `n`
  (11.0×/18.3×/3.6× at n=4/8/32, was 6.9×/7.9×/2.9×). A benchmark run under a
  configuration the target never uses had been understating the cost of padding
  by ~2×. That is the concrete argument for the decision, not an aside.
- **Benchmarks that quoted the old footprint were re-measured.** The R6 go/no-go
  evidence (`docs/ROADMAP.md`) and `bench/SHOWCASE.md` carry the new figures. The
  *shape* of the `Nmax`-padding penalty is unchanged, so the R6 decision basis is
  unchanged.
- **One tolerance moved.** `SLoopboundPaddingTest` asserted `padded/exact >= 0.95`
  at `n = Nmax`, on the reasoning that the padded file is the exact file *plus*
  loopbound scaffolding. That is no longer true — the padded file's runtime trip
  count is specialized differently by Coder, and the bounded range replaced an
  emxArray — so padded can come in slightly *under* exact (0.88× at `Nmax = 32`,
  1.0× at `Nmax = 64`). The band is now two-sided `(0.75, 1.2)`, asserting "no
  penalty remains" rather than a byte-level relation — a real regression here is
  a multiple-× move, not a few percent.
- **Generated files gain one line.** Anyone re-generating a `loopbound`
  derivative sees an extra `assert` at the top. Recorded in `CHANGELOG.md`.
- **The end-to-end proof is local-only.** Hosted CI licenses neither MATLAB Coder
  nor Embedded Coder (`CI_PLAN.md` §3.2), so
  `SRolledErtCodegenTest::loopboundGradientErtCodegenStaticMemory` is Filtered
  there. `ILoopboundTest::guardPrecedesEveryBoundDependentSize` is the
  license-free stand-in: it pins the *ordering* (the property the fix
  establishes) even where the compiler that punishes violating it cannot run.
  That pairing — a cheap invariant runnable everywhere plus the expensive proof
  runnable locally — is the intended shape for target-acceptance properties.

**A guard that protects itself.** A generated file's own precondition executes
during adigator's initial test evaluation when that file is re-differentiated, so
re-differentiating a specialized file at the wrong trip count cannot silently
produce a mis-stamped guard — it throws first. `adigatorCheckTripCountRediff`
adds a diagnosis, not the safety. Worth knowing when reasoning about future
emitted constructs: anything executable we emit into a generated file also runs
on the next derivative pass.

**Revisit when:** a target other than strict ERT/no-heap becomes a supported
output (then "bounded at generation" may be over-strict); or if #6 Tier 2
(symbolic `N`) lands, which removes the padded sizing this guard bounds and would
make the hoisted `assert` vestigial rather than load-bearing.

## Alternatives considered

- **Emit index arithmetic instead of materializing the loop-variable range.**
  For the canonical `for k = 1:N`, `cadaforvar1.f = 1:N` exists only to be read
  at `cadaforvar1.f(:,cadaforcount1)`, so `k.f = cadaforcount1` would remove the
  array entirely (better than bounding it: no stack cost at all). Rejected as the
  *fix*: it treats a symptom. The empirical probe was decisive — a function with
  both `zeros(N,1)` and `1:N` fails at the `zeros(N,1)` line, i.e. **before** the
  loop variable is ever reached. Removing the range would have left the user's
  own allocations unbounded and the file still unembeddable, while changing value
  and size propagation through the loop body (risk, for no completeness). It
  remains available as a later *optimization* on top of a correct bound.
- **Hoist only the guards whose bound a loop actually matched.** Slightly less
  emitted text, but it makes emission depend on loop-discovery order and gives a
  file whose declared envelope is not stated. Rejected: the guard is cheap and
  the stronger statement is the more useful one.
- **Drop the per-loop guards once hoisted.** Rejected: they are the shape the
  re-differentiation path recognizes (#173/#181) and the exit-union machinery
  sits next to them. Removing them buys nothing in generated C and risks a
  Hessian-of-a-loopbound-file regression.
- **Leave dynamic memory allocation enabled and call it embeddable.** This was
  the status quo, and it is exactly how the defect hid for the life of the
  feature. Rejected on principle: a claim the test cannot fail is not a test.
