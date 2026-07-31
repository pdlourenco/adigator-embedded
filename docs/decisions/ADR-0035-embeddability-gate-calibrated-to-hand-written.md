# ADR-0035 — The embeddability gate is calibrated against hand-written derivatives, not a byte ceiling

## Status

Accepted — 2026-07-31

## Context

[ADR-0033](ADR-0033-strict-shared-coder-config.md) records the half-truth this
gate closes: **ERT exit-success is necessary but not sufficient for
embeddability.** `EnableDynamicMemoryAllocation=false` rejects *unbounded*
sizes, but a **bounded-but-large** derivative code-generates cleanly, passes
`SRolledErtCodegenTest`, and then overflows the target's stack at run time —
[ADR-0019](ADR-0019-rolled-embeddable-path-scatter-deferred.md)'s "hollow
milestone". `CI_PLAN.md` REQ-T-10 has carried the missing gate as *planned,
#80a-2* since.

The obvious formulation — *"a generated derivative's stack must not grow with
problem size"* — is **wrong, and measurement is what showed it**. A Hessian's
answer is n×n. Even the optimal hand-written reference in this repo,
`Hes = diag(exp(x))`, grows: 144 → 208 → 336 B over n = 8/16/32 — which is
**exactly `80 + 8n`**, i.e. linear at one double per element on a fixed 80 B
frame. Coder returns the matrix through the caller's buffer, but temporaries
still scale. A flatness gate would have failed correct, optimal, hand-written
code.

The second obvious formulation — an absolute byte ceiling — fails differently:
this project declares no target device. Any number would be invented, and would
quietly become policy the first time someone tuned to it.

What *is* measurable, and is squarely this project's responsibility, is the
overhead the **generator** adds over what the derivative's own shape costs.
Measured on the same anchors, same pipeline (`adigatorCoderConfig` + ADR-0027's
`size`/`-fstack-usage`), n = 8/16/32 (the gate itself sweeps 8/32/64):

| case | generated | hand-written | ÷ | shape |
|---|---|---|---|---|
| `vcostfun` gradient | `96+8n` | `96+8n` | 1.00 / 1.00 / 1.00 | identical |
| `vcostfun` Hessian | `96+8n` | `80+8n` | 1.11 / 1.08 / 1.05 | same slope, +16 B → ratio → 1 |
| `vvecfun` Jacobian | `112+24n` | `112+8n` | 1.73 / 2.07 / 2.39 | **3× the slope**, ratio → 3.0 |
| `scostfun` Hessian (**subscripted**) | *not affine* | `80+8n` | 5.33 / 12.31 / **28.62** | **super-linear** |

Extending the gate's own sweep to n = 64 confirms the split out of sample: the
Jacobian lands on **2.64**, exactly what `(112+24n)/(112+8n)` predicts, while the
subscripted Hessian reaches **37,552 B against 592 B hand-written — 63.4×**. A
model that predicts an unmeasured point is a better basis for a threshold than a
fitted exponent.

Every vectorized series is **exactly affine in n** — the fits above reproduce all
three measured points with no residual. That matters more than it looks: a
power-law fit to affine data always reads sub-linear (the shared constant term
dominates at small n), so an "exponent" quoted from this sweep is an artifact,
not a growth law. The only series that is genuinely not affine is the
subscripted Hessian — which is exactly the one this gate must catch.

`scostfun` and `vcostfun` compute the same function; only the formulation
differs, so one analytical reference serves both and the last row is
like-for-like. One caveat worth stating: that comparison charges the *generator*
for the *user's* choice of a subscripted formulation, so some part of 28.6× may
be intrinsic to the rolled path rather than a generator defect. It does not
weaken the finding — super-linear against linear is real either way — but #217's
scope should not be assumed before diagnosis.

## Decision

**The embeddability gate asserts `generated stack ≤ K × hand-written stack` for
the same function and DerType, over a size sweep**, with **K set per case** from
the measured behaviour (1.5× at parity, 4× where a bounded constant-factor gap
is understood and accepted).

- **Hand-written references already exist** (`bench/showcase/analytic/`) and are
  finite-difference-checked by `SDerivShowcaseTest`, so the baseline is a
  maintained artifact, not a magic number.
- **Tolerances are per case, not one global K.** A single loose number makes the
  gate vacuous exactly where the tool is strongest: the vectorized gradient is
  *byte-identical* to hand-written, so a 4× allowance would let a 4× regression
  land green on the one case proving the tool costs nothing.
  - **1.5×** for the parity cases (gradient 1.00×, vectorized Hessian 1.05×).
  - **4×** for the `vvecfun` Jacobian. Its overhead is `(112+24n)/(112+8n)` —
    increasing in n but **bounded above by exactly 3.0, never attained**. So
    `K = 3` leaves *zero* asymptotic margin and 4 leaves a real one. (An earlier
    draft of this ADR justified 4 by claiming 3 "would be breached on a larger
    sweep". That is arithmetically false on this data — the correct argument is
    the asymptote, and it is the stronger one.)
  - **4×** for the #217 pin, which fails against any of these (28.6× at n=32,
    63.4× at n=64).
- **The trend is reported, never asserted** — and the Jacobian is why. At n ≤ 32
  its ratio *looks* divergent (1.73 → 2.39) and a power-law fit reads 0.77 vs
  0.53, but both are artifacts of the shared `+112` term; the gap is a bounded
  constant factor (three vector temporaries where hand code uses one). Asserting
  on direction would have encoded a **measurement artifact as binding policy** —
  the worst outcome for a gate. The right instrument for a genuine asymptotic
  gap is a wider sweep, where the ratio gate catches it without the noise.
- **Local-only, by necessity.** Hosted CI licenses neither Coder product
  (`CI_PLAN.md` §3.2), so this can never be a CI job. `tests/ci_ert.m` is the
  release-attestation entry point.

Lands as `bench/measureStackScaling.m` (measurement),
`tests/system/SStackScalingTest.m` (gate), `tests/ci_ert.m` (attestation).

## Consequences

- **REQ-T-10 is complete**: "codegens" now means "codegens *and* does not carry
  runaway stack overhead". The requirement's *(planned, #80a-2)* marker retires.
- **The gate found a real defect on first contact** — [#217](https://github.com/pdlourenco/adigator-embedded/issues/217),
  the rolled/subscripted Hessian at 28.6× (n=32) rising to 63.4× (n=64, 37.5 KB
  of stack), which ERT-codegens
  cleanly and passes the existing gate today. It ships as a `KnownIssue` pin
  (`CI_PLAN.md` §3.3: visible, counted, non-blocking) that **self-heals**: when
  #217 lands, `assumeFail` stops firing and the assertion runs for real.
- **The gate deliberately produces an Incomplete.** That is the documented
  KnownIssue convention working as intended, and a concrete reason why "expect
  0 incomplete" is the wrong way to read a local run (see `CONTRIBUTING.md`
  §"Local development & pre-push CI" — confirm the codegen classes *per class*).
- **The `vvecfun` Jacobian is a bounded constant-factor gap, not a watch item.**
  Three vector temporaries against hand-written one, ratio → 3.0. Worth fixing
  for its own sake; *not* the same shape as #217, which is super-linear. An
  earlier draft of this ADR claimed it was — corrected on the arithmetic.
- **Cost**: ~170 s (each case is four Coder builds). Extended/local suite, not
  the fast pre-push gate.
- **ADR-0019 needs narrowing** (noted in #217, not done here): its "flat,
  n-independent stack" claim is reproduced exactly — *for the gradient*. It does
  not hold for the Hessian, and its "the accumulation-engine rewrite is
  avoidable" argument does not extend there either.

**Revisit when:** a target device *is* declared — an absolute ceiling then
becomes meaningful and should be added *alongside* this ratio, not instead of it
(the ratio catches generator regressions the ceiling would sit above). Or if the
analytical references stop being representative of optimal hand code.

## Alternatives considered

- **"Stack must be flat / n-independent."** The formulation this work started
  with. Rejected on measurement: hand-written `diag(exp(x))` grows *linearly*
  (`80+8n`), so the gate would fail optimal code — and the refutation is
  stronger than the first draft of this ADR claimed, which quoted a fitted
  "exponent ≈0.6" that was itself an artifact of the affine data. Worth recording that the error was
  only visible because a control was measured — the generated-only numbers
  looked like a clean O(n^1.8) defect until the hand-written baseline showed a
  growing stack is normal and the *ratio* is the signal.
- **Absolute byte ceiling (e.g. `stack ≤ 8 KB`).** Meaningful to a user with a
  known board, and it is the number they ultimately care about. Rejected *for
  now* because this project declares no target: the number would be invented,
  then defended. Explicitly left as the revisit condition rather than refused.
- **Ratchet against recorded per-anchor baselines** (the ADR-0032 coverage-floor
  pattern). Consistent with existing precedent and cheap, but it only detects
  drift — it never asserts embeddability, and it would have happily ratcheted
  #217's 28.6× in as the baseline. Rejected: this gate exists to make a claim,
  not to freeze the status quo.
- **Assert on the trend (overhead must not diverge).** Attractive — it catches
  asymptotic gaps regardless of constant, which is the more fundamental property.
  Rejected as the *assertion* at three data points: too noisy to fail a build on,
  and it would fail the Jacobian today for a gap comfortably inside budget.
  Retained as reported output, which is where a weak-but-real signal belongs.
- **Gate only the passing cases, exclude the subscripted Hessian.** Would ship a
  gate that is green on arrival and silent about the one case known to be broken
  — the "plausible-looking pass" this whole line of work exists to eliminate.
