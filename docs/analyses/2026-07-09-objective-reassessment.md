# 2026-07-09 objective reassessment — state of the frontier

**Dated snapshot at master `9149e73`** (after the 2026-07-07/08 merge burst).
This records the *cross-cutting* state of the project's core objective and the
reasoning behind the current priority order — the argument no single ROADMAP
row carries. It is deliberately short and **will not be maintained**: per-item
live status is [`../ROADMAP.md`](../ROADMAP.md), bug dispositions are
[`ANALYSIS.md` §1.5](ANALYSIS.md). Companion to the
[2026-07-04 code-quality review](2026-07-04-code-quality-review.md), whose
findings the burst largely remediated (R28).

**The objective.** Correct and fast embedded MATLAB code implementing
gradients, Jacobians, and Hessians that auto-codes for embedded targets
(MATLAB Coder / Embedded Coder), with the testing structured to *prove* it.
Three pillars: **correct**, **provably correct on target**, **fast**.

## Pillar 1 — Correct

Every catalogued silent-wrong-output bug (B1–B26) is fixed or safely errors,
**except one**: **B27**
([#162](https://github.com/pdlourenco/adigator-embedded/issues/162)) — a
nested runtime-bound (`loopbound`) loop's exit-variable derivative is silently
**zeroed** when evaluated at `n < Nmax`. It is the only known wrong-derivative
on master, and it sits in a flagship embedded feature (generate-at-max,
run-at-n). Everything else unsupported now errors, per principle 1:
reverse-mode matrix division (B24 → error; the true adjoint is deferred,
R30/[#128](https://github.com/pdlourenco/adigator-embedded/issues/128)), the
B19 `if`-guarded residual
([#108](https://github.com/pdlourenco/adigator-embedded/issues/108)), and the
struct-output limitation
([#164](https://github.com/pdlourenco/adigator-embedded/issues/164), error
quality to fix, plus a *latent* strip residual gated behind it).

## Pillar 2 — Provably correct on target

The **MATLAB-side** proof is now genuinely strong: the test registry matches
reality with the former phantom guards written and `IShapeMatrixTest`
asserting the exported structures (#160/#119); the shape-fuzz value hole is
closed by the FD secondary oracle (#161/#145); R27 Phase 2's first axis
(der_output invariance, #114) fuzzes the nonzeros surface; cross-mode
equality is exact everywhere it is claimed, now including the warn-and-emit
constructs (R29).

The **compiled-side** proof is the missing keystone. Today "the compiled
binary computes the same derivative" rests on a handful of hand-picked cells
(`SCodegenTest`'s two build variants plus the curated showcase cells in
`SCodegenShowcaseTest`); nothing asserts it at scale. R15 — the ADR-0014
codegen-equivalence oracle (`matlabtest.coder.TestCase`, born-ERT per the
R20c amendment, sampled over the MC campaign) — is approved and spec'd but
unimplemented ([#64](https://github.com/pdlourenco/adigator-embedded/issues/64)).
And REQ-T-10's remaining ERT cells have never been green: the **unrolled**
O(n²) form and **loop-carrying reverse-mode** (reverse requires `unroll=1`,
so the two are coupled) — R21. The *vectorized* reverse anchor is ERT-green
in the showcase; it is the subscripted/loop-carrying reverse claim that is
currently made (R16, guide-documented) but unproven.

## Pillar 3 — Fast

The efficiency path is decided (ADR-0016: matrix-free products, R16–R19), but
execution is gated on measurement: **R17c** (compiled ROM/RAM/stack) plus
R17's outstanding interpreted-`timeit` and Nmax-padding metrics are the
decide-gate evidence for the R6 padding decision and the R24 `'l'`-removal
gate, and they inform R18's ROM expectations. R18 (H·v first) has not
started.

## Priority order (2026-07-09)

1. **Fix B27** ([#162](https://github.com/pdlourenco/adigator-embedded/issues/162))
   — the one live wrong derivative. Extend the exit-variable union past
   `~PARENTLOC` for runtime-bound parents, or — if that is deep — make the
   pattern a generation-time **error** until it is (an interim error is itself
   shippable; a wrong derivative is not). The `KnownIssue` tripwire is already
   in `ILoopboundTest` (`nestedRuntimeBoundInnerExitDerivative`, #163); the fix
   flips it to a hard guard.
2. **Implement R15** ([#64](https://github.com/pdlourenco/adigator-embedded/issues/64))
   — the highest-leverage testing item for the objective: converts "ERT
   accepts the file" into "the compiled binary computes the same derivative",
   sampled across the campaign. MATLAB-session work; spec done.
3. **R21 — close the ERT matrix** — loop-carrying reverse-mode first (shipped
   surface, unproven claim), which drags the coupled unrolled form with it.
4. **R17c + R17's outstanding metrics** — cheap harness work (compiled
   ROM/RAM/stack, interpreted `timeit`, the Nmax-padding cell) that unblocks
   the two queued decision gates (R6, the R24 `'l'`-removal gate) and informs
   R18's ROM expectations.
5. **R27 Phase 2: add the `loopbound` axis (evaluated at `n < Nmax`) and the
   `unroll`/`slim_embed`/`der_levels` axes.** B27 repeats the B17 lesson —
   found by directed experiment in exactly an axis the fuzzer holds fixed; the
   truncated-trip loopbound axis would have caught it and will catch its
   siblings.
6. **R18 H·v** — the accepted efficiency path; new surface, so after 1–4
   (which prove existing surface).

## Consciously deferred (fine where they are)

R30/[#128](https://github.com/pdlourenco/adigator-embedded/issues/128) matrix
adjoint (safe error, no demand yet);
[#164](https://github.com/pdlourenco/adigator-embedded/issues/164) actionable
error (one-liner; the strip-residual guard stays latent-gated); R25 phase 2
matrix + R24 `split_data` (feature completeness; R24 waits on R17c);
R22/[#85](https://github.com/pdlourenco/adigator-embedded/issues/85)
nth-derivative (outside the grad/Jac/Hes core);
[#156](https://github.com/pdlourenco/adigator-embedded/issues/156) solver
wrappers (quarantined by ADR-0026);
[#108](https://github.com/pdlourenco/adigator-embedded/issues/108) B19
residual (safe error);
[#121](https://github.com/pdlourenco/adigator-embedded/issues/121) residuals
and doc polish.

**One-sentence version:** fix the last known wrong derivative (B27), then make
the *compiled* side of the promise provable (R15 oracle + R21 ERT cells), let
the R17c numbers unlock the speed decisions — the MATLAB-side correctness
story is in good shape.
