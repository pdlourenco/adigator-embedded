# ADR-0036 — The rolled printing run prunes derivative patterns against the loop overmap it is about to be squeezed into

## Status

Accepted — 2026-07-31

## Context

[ADR-0035](ADR-0035-embeddability-gate-calibrated-to-hand-written.md)'s gate
found [#217](https://github.com/pdlourenco/adigator-embedded/issues/217) on first
contact: the **rolled/subscripted Hessian** of `sum_k exp(x_k) + 2x_k` carries
**37,552 B of stack at n=64 — 63.4× the hand-written `diag(exp(x))`** — while
ERT-code-generating cleanly and passing `SRolledErtCodegenTest`. The *vectorized*
form of the identical maths sits at 1.05×, and the rolled **gradient** is flat at
96 B, so neither the maths nor the rolled machinery is the cost.

A rolled `for` loop is processed twice, and the two passes do not see the same
thing:

- The **overmap run** walks the body once per iteration with the **exact**
  per-iteration derivative patterns and unions them (`cadaOverMap` →
  `cadaUnionVars`, which unions exact locations — no row/column cross-product,
  no densify fallback).
- The **printing run** walks the body **once**, because one printed body has to
  serve every iteration. Every loop-body operand therefore carries its *overmap*
  — the union — rather than its per-iteration pattern.

So the printing run composes two unions **as if they were independent**, which
throws away the correlation between them. For `exp(x(k))` the second-derivative
pattern is `{(k,k)}` in iteration `k`; the union is the n-nonzero **diagonal**,
and that is what the tool exports (`SCscMetadataTest`/TS-S-08 pins `Nnz = 8` at
n=8). But in the printing run both factors of the product rule are n-wide
overmaps, so `times` yields the full **n×n cross product**. Instrumenting both
runs shows it directly — per-iteration nonzeros `1,1,…,1` unioning to `8`, then:

```
SHRINK  scostfun_ADiGatorHes  der=cada1f2dxdx  nzx=64  nzover=8  nzd=8
```

`cadaPrintReMap` then squeezes the 64 back down to the 8 — **one statement
later, after the generated code has already gathered n² doubles onto the
stack**. The emitted culprit is the scalar-derivative repmat in `cadaRepDers`:

```matlab
cada2tempdx = cada2f1dx(Gator2Data.Index1);   % n^2 doubles, inside the loop
cada1f2dxdx = cada2tf1(:).*cada2tempdx;       % n^2
cada1f2dxdx = cada1f2dxdx(Gator2Data.Index3,1);  % ... and back down to n
```

That is the whole defect. The tool **already knows** the answer is diagonal; it
computes n², keeps n, and pays for the n² at run time on the target.

## Decision

**An operation that is about to have its result squeezed into a loop overmap may
drop the doomed derivative locations before it prints them.** The target pattern
is supplied by a new private helper, `lib/@cada/private/cadaOverMapTargetNz.m`,
and applied in `cadaRepDers` via an optional sixth argument, wired from the two
scalar-expansion call sites in `cadabinaryarraymath`.

Three properties make this safe enough to put into second-derivative pattern
propagation, where a wrong pattern is a *silently wrong derivative*
(`REVIEW_CONTEXT` principle 1):

1. **It is not a new truncation.** It removes exactly the locations
   `cadaPrintReMap` removes a statement later. The helper returns `[]` — and the
   caller prunes nothing — unless that remap is actually going to happen: same
   `OverLoc` and `SubsFlag` (`NAMELOCS(:,3)`) test as `cadaOverMap`'s printing
   branch, plus a `func.size` match so no caller has to reason about
   `cadaPrintReMap`'s changing-size `xref`/`oref` mapping.
2. **A location outside the overmap is structurally zero, not merely small.**
   `cadaUnionVars` unions *exact* locations, so the stored overmap contains at
   least the union of the variable's per-iteration patterns. It is not
   necessarily tight — an overmap slot can be **shared** by several variables,
   since `cadaOverMap`'s direct-assignment merge folds LHS and RHS slots
   together — but that only makes the prune more conservative. Safety rests on
   property 1, not on tightness.
3. **Composing overmapped operands is sound at run time only because the
   non-live slots hold zero**, which is what the per-iteration re-zeroing of the
   derivative temporaries buys. That same invariant is what makes pruning to the
   union correct rather than optimistic.

**Scope is set by measurement, not by symmetry.** Instrumenting every
`cadaPrintReMap` over-approximation across the whole corpus (`tests/unit`,
`integration`, `system`) found **18 events**:

- **17 are this defect**, all with the signature `nzx = n²`, `nzover = n`, and
  all from the scalar-expansion path — across six fixtures, and reaching **third
  order** (`cada1f2dxdxdx`), so the fix is not Hessian-specific. The largest is
  the gate's own n=64 sweep: **`nzx = 4096`, `nzover = 64`**, which is the
  37.5 KB in a single line of log.
- **1 is different in kind**: a *first-order* Jacobian's growing concatenation
  (`ForHorzcat` in `horzcat.m`, `V.dx` at 700 → 600 nonzeros in the
  `polydatafit` example). That is a bounded ~17% over-approximation with no
  growth-law character, on a path with no repmat and no directly comparable
  target mapping. **Left alone deliberately** — it is a constant-fraction cost,
  not a stack blow-up, and fixing it on no evidence of harm is the wrong trade
  in this code.

`cadaRepDers`'s third caller (`subsasgn`, the rolled indexed-assignment path) is
likewise **not** wired: its repmat lives in the assigned-from variable's row
space rather than the result's, so the target pattern is not directly
comparable, and no measured case needs it.

**The `IF` overmap is deliberately out of scope.** `cadaOverMap`'s non-loop
branch remaps against a conditional-set overmap under different save/return
conditions; the same argument would probably carry, but nothing measured needs
it and the guard conditions there are not the ones this helper checks. Note this
is *not* B19/[#108](https://github.com/pdlourenco/adigator-embedded/issues/108),
the `if`-guarded `while`-counter over-approximation: that one is an index
over-approximation that raises an error, not a pattern width that costs stack.
Same family of symptom, different site and different failure mode.

## Consequences

- **#217 closes, measured the way it was found.** `measureStackScaling` on the
  pinned anchor, n = 8/32/64:

  | n | before | after | hand-written | before | after |
  |---:|---:|---:|---:|---:|---:|
  | 8 | 768 | **160** | 144 | 5.33× | **1.11×** |
  | 32 | 9,616 | **352** | 336 | 28.62× | **1.05×** |
  | 64 | 37,552 | **608** | 592 | 63.43× | **1.03×** |

  The generated series becomes exactly `96 + 8n` — **affine**, and
  byte-for-byte the same series ADR-0035 measured for the *vectorized* Hessian
  (`96+8n` against hand-written `80+8n`). The subscripted rolled Hessian joins
  the parity cases: `SStackScalingTest`'s pin loses its `KnownIssue` tag and
  moves from `TolPin = 4` to `TolParity = 1.5`, the same budget its vectorized
  twin already meets. Renamed with the tag —
  `subscriptedHessianStackOverhead` → `subscriptedHessianMatchesVectorizedTwin`,
  since what it now asserts is parity, not an overhead ceiling.

- **ADR-0035's caveat is answered.** It flagged that the 28.6× "charges the
  *generator* for the *user's* choice of a subscripted formulation, so some part
  of it may be intrinsic to the rolled path". The diagnosis says none of it was:
  the whole gap was one over-approximation, and the rolled form now costs the
  same as the vectorized one.

- **The n² static index tables go with it.** `Gator2Data.Index1/2/3` collapse
  from 64 entries to 8 at n=8; the gather statement disappears entirely
  (`cada2tf1` degenerates to `cada1f1dx(:)`). ROM falls too — modestly, because
  those tables were already down-cast to `int8`, which is exactly why the ROM
  discriminator in #217 read clean while 512 B sat on the stack.

- **The prune is a no-op everywhere else.** Across the corpus it fires on one
  variable in one fixture; every other generation is byte-identical.

- **A new obligation on future overmap work.** Anything that changes what
  `cadaOverMap` stores, or when `cadaPrintReMap` is called, now also changes
  when this prune fires. The helper's guards mirror `cadaOverMap`'s printing
  branch on purpose — they must be kept in step, and
  `IRolledOvermapWidthTest` (license-free) is the tripwire: it asserts the
  second-derivative index metadata stays linear in n, *and* that a genuinely
  dense rolled Hessian is left alone.

**Revisit when:** a printing-run over-approximation outside the scalar-expansion
path is measured to *cost* something — the `ForHorzcat` one above is the known
candidate and is currently just noted, not tracked as a defect. The helper is
the reusable part; wiring another op to it is small. Or if the rolled loop
machinery stops recomputing patterns from overmapped operands in the printing
run, which would remove the over-approximation at its source and make the prune
dead code.

## Alternatives considered

- **Prune generically, at every operation that composes operand patterns**
  (`mtimes`, `cadaunarymath`, `sum`, `subsasgn`, `cadaunion`'s result…). Catches
  future instances of the same class in one go. Rejected on evidence: of the 18
  over-approximations the probe found, 17 are on the one path this change wires
  up and the remaining one is a bounded first-order concatenation that costs
  nothing. So the general version would touch many second-derivative propagation
  paths with nothing measured behind any of them — the wrong trade in
  principle-1 territory. The helper is written so adding a site later is a
  two-line change.
- **A peephole over the emitted statements**, fusing `gather → op → gather` into
  a single composed gather. Mathematically airtight (composition of constant
  index vectors) and would have fixed the same three temporaries. Rejected
  because it is regex-over-generated-source, which the project is already trying
  to *retire* rather than extend (ROADMAP R20d, `adigatorStripDeadOutputIndices`),
  and because it treats the symptom in the text rather than the cause in the
  pattern.
- **Carry per-iteration correlation through the loop** — the accumulation-engine
  rewrite [ADR-0019](ADR-0019-rolled-embeddable-path-scatter-deferred.md)
  judged avoidable. It is the real fix in the sense that it removes the
  over-approximation at its source rather than trimming the result. Rejected as
  disproportionate: it is a rewrite of the rolled propagation core to buy what a
  guarded intersection against an already-computed union buys today. ADR-0019's
  "avoidable" verdict was argued for the gradient and did not transfer to the
  Hessian; with this change it does.
- **Accept it as intrinsic to the rolled form and leave the pin.** Defensible
  before the diagnosis — the issue itself warned not to assume "generator bug".
  Refuted by the measurement: the exported pattern is diagonal, the vectorized
  twin is at 1.05×, and the gap turned out to be a single over-approximation.
- **Widen `SStackScalingTest`'s tolerance for this case.** Would have made the
  suite green without making the artifact embeddable — the "plausible-looking
  pass" ADR-0035 exists to eliminate.
