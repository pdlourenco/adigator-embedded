# Derivative showcase — which mode should I pick?

One derivative of a curated anchor function generated through every relevant
axis, with its generated-code complexity measured and its value checked against
the analytic derivative. This is the "which mode should I pick?" reference.

The comparison spans **four methods**: AD **forward**, AD **reverse**, a
hand-coded **analytical** derivative (the "do I even need this tool?" baseline and
the gold correctness oracle), and central **finite differences** (FD, the method
one reaches for by default — trivial to write, but O(n)/O(n²) evaluations and the
*only inexact* method). The analytical and FD forms are reference *points*, not
grid cells: they have no embed/slim/unroll variants, so each appears once per
DerType with those fields blank (`method = analytic`/`FD`, `—` elsewhere). FD is
written Coder-compatibly (`showcase/fd/*`, via the `fdDeriv` kernel) so it flows
through **both** environments — interpreted here and compiled-C below — like every
other method.

Regenerate the interpreted (MATLAB-level) table with:

```matlab
addpath bench
r = derivShowcase('n',6,'timeReps',3, ...
    'reportPath','bench/showcase_table.md', ...     % MATLAB-level table
    'texPath','docs/userguide/bench_interp.tex');   % committed guide fragment
```

The **C level** (compiled-C footprint + `timeit` MATLAB-vs-MEX runtime over an
`n`-sweep, via MATLAB Coder) is below and adds the runtime columns + a figure.

## Anchors

- `scostfun(x)` — scalar cost with a **rolled loop** and subscripting,
  `J = Σₖ (exp(xₖ) + 2xₖ)` (the allocation/`loopbound` shape). Exercises
  gradient, Hessian, forward & reverse, rolled & unrolled.
- `vcostfun(x)` — the same cost **vectorized** (`sum(exp(x)+2x)`, no
  subscripting). Its reverse adjoint references no index tables.
- `vfun(x)` — vector output with a diagonal (sparse) Jacobian, for the Jacobian
  axis.
- `vvecfun(x)` — a vectorized vector output (`sin(x)+x.^2`), the unrolled
  Jacobian anchor at C level.
- `showcase/analytic/*.m` — hand-coded analytical grd/jac/hes of the anchors,
  the AD-vs-analytical reference (each finite-difference-checked once by
  `SDerivShowcaseTest`).

## Snapshot (n = 6)

| function | DerType | method | mode | slim | unroll | der_levels | code lines | .mat bytes | idx tables | idx elems | interp (ms) | max err | correct |
|---|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|---|
| scostfun | gradient | AD | c | 0 | 0 | — | 46 | 478 | 3 | 78 | 0.073 | 0.0e+00 | ok |
| scostfun | gradient | AD | l | 1 | 0 | — | 39 | 310 | 3 | 78 | 0.096 | 0.0e+00 | ok |
| scostfun | gradient | AD | i | 1 | 0 | — | 49 | 0 | 0 | 0 | 0.114 | 0.0e+00 | ok |
| scostfun | gradient | AD | i | 0 | 0 | — | 49 | 0 | 0 | 0 | 0.115 | 0.0e+00 | ok |
| scostfun | gradient | AD | i | 1 | 1 | — | 128 | 0 | 0 | 0 | 0.063 | 0.0e+00 | ok |
| scostfun | hessian | AD | c | 0 | 0 | — | 124 | 1038 | 11 | 246 | 0.136 | 0.0e+00 | ok |
| scostfun | hessian | AD | i | 1 | 0 | — | 136 | 0 | 0 | 0 | 0.186 | 0.0e+00 | ok |
| scostfun | hessian | AD | i | 1 | 0 | [2] | 134 | 0 | 0 | 0 | 0.169 | 0.0e+00 | ok |
| scostfun | gradient-reverse | AD | c | 0 | 1 | — | 177 | 288 | 12 | 12 | 0.025 | 0.0e+00 | ok |
| scostfun | gradient-reverse | AD | l | 0 | 1 | — | 172 | 288 | 12 | 12 | 0.038 | 0.0e+00 | ok |
| scostfun | gradient-reverse | AD | i | 0 | 1 | — | 187 | 0 | 0 | 0 | 0.062 | 0.0e+00 | ok |
| vfun | jacobian | AD | c | 0 | 0 | — | 45 | 484 | 4 | 120 | 0.107 | 0.0e+00 | ok |
| vfun | jacobian | AD | i | 1 | 0 | — | 50 | 0 | 0 | 0 | 0.136 | 0.0e+00 | ok |
| vfun | jacobian | AD | i | 1 | 1 | — | 133 | 0 | 0 | 0 | 0.079 | 0.0e+00 | ok |
| vcostfun | gradient | AD | l | 0 | 1 | — | 22 | 249 | 1 | 6 | 0.020 | 0.0e+00 | ok |
| vcostfun | gradient-reverse | AD | l | 0 | 1 | — | 18 | 0 | 0 | 0 | 0.003 | 0.0e+00 | ok |
| vcostfun | gradient | analytic | ana | — | — | — | 4 | 0 | 0 | 0 | 0.000 | 0.0e+00 | ok |
| vcostfun | gradient | FD | fd | — | — | — | 3 | 0 | 0 | 0 | 0.005 | 2.6e-10 | FD err=2.6e-10 |
| vcostfun | hessian | analytic | ana | — | — | — | 5 | 0 | 0 | 0 | 0.001 | 0.0e+00 | ok |
| vcostfun | hessian | FD | fd | — | — | — | 4 | 0 | 0 | 0 | 0.042 | 7.9e-08 | FD err=7.9e-08 |
| vvecfun | jacobian | analytic | ana | — | — | — | 4 | 0 | 0 | 0 | 0.001 | 0.0e+00 | ok |
| vvecfun | jacobian | FD | fd | — | — | — | 3 | 0 | 0 | 0 | 0.006 | 3.1e-11 | FD err=3.1e-11 |

Four **methods** appear per (function, DerType): AD forward, AD reverse, a
hand-coded **analytical** reference, and central **finite differences** (FD).
`interp (ms)` is the un-gated interpreted derivative-evaluation time (no Coder
needed — the no-compile simulation cost, batch-timed so the sub-microsecond
references clear the timer floor); `max err` is the derivative error vs the
analytical reference — `0` for AD/analytical (machine-eps exact), the truncation
error for **FD**, the only inexact method. **Note on `code lines`:** the AD and
analytical figures are the full implementation, but the **FD** figure counts only
the per-anchor wrapper (it reuses the shared `showcase/fdDeriv` kernel, ~44 lines,
not counted here) — read it as the *marginal per-function* authoring cost ("no
derivation, reuse the kernel"), not the total. (Numbers are a snapshot; regenerate
as above. `SDerivShowcaseTest` guards correctness + the headline relationships —
incl. that FD is accurate-but-nonzero-error and every cell's runtime is measured —
not the exact figures.)

## How to read it

- **`embed_mode`** is a *where-does-the-constant-data-live* knob, not a numeric
  one (all three are bit-identical): `c` (classic) keeps the index tables in a
  `.mat` (small code, non-zero `.mat bytes`); `i` (inline) inlines them as source
  (no `.mat`, more `code lines`). Pick `i` for a self-contained, **embeddable**
  artifact (the default), `c` for interactive/host use. The third row, `l`
  (coderload), is a midpoint kept **for completeness only**: it holds the data in
  a `.mat` read through `coder.load`, but it does **not** code-generate under
  Embedded Coder and its compiled footprint converges with `i`, so it offers no
  advantage over `i` — it is slated for removal in a future version, so don't pick
  it.
- **`slim`** trims unread `_location`/`_size` chains, so the unreferenced index
  tables drop in the prune — visible as fewer `.mat bytes` / `idx elems` (e.g.
  `scostfun` gradient `c`→`l`+slim: 478→310 bytes).
- **`unroll`** trades code for loops: unrolling the rolled anchor multiplies
  `code lines` (e.g. gradient `i` 51→130) — keep `unroll=0` for code size.
- **`der_levels`** drops the lower-order companions (Hessian `[2]` returns just
  `Hes`, no `Grd`/`Fun`) — marginal here, larger when `Fun`/`Grd` assembly is
  expensive.
- **forward vs reverse** is the headline. For the *gradient* of a scalar cost,
  reverse carries **zero static data** when the adjoint is fully vectorized
  (`vcostfun` reverse: 0 bytes / 0 tables, vs forward `l`: 249 bytes / 1 table —
  the `1:n` nonzero-location map). With subscripting (`scostfun`) the reverse
  still carries its subscript maps, but the gradient ROM never grows with the
  number of variables the way a forward *dense* Jacobian/Hessian does. Use reverse
  (`gradient-reverse`) for objective gradients / first-order embedded solvers;
  forward for Jacobians and where `m ≈ n`.
- **AD vs analytical vs FD** is the user-facing story ("which method?"). A hand
  **analytical** derivative is tiny here — `4`–`5` code lines vs the AD wrapper's
  `18` (vectorized reverse) to `187` (rolled reverse) — and carries no data,
  because a human writes the closed form directly; that's expected, and is the
  *point*: for a simple cost, hand-coding wins; AD's value is at scale, where the
  derivative is large/sparse enough that deriving and maintaining it by hand
  becomes impractical or silently drops sparsity. **FD** is cheaper still to write
  (`3`–`4` lines, no derivation) but is the only **inexact** method — its `max
  err` column (`~1e-10` gradient, `~1e-8` Hessian) is the truncation floor — and
  its evaluation cost grows O(n)/O(n²) with the variable count (`interp (ms)`: FD
  Hessian is the slowest reference here), the reason to prefer AD as the problem
  grows. The crossover — not a win/lose — is the story (the compiled-footprint side
  is below). The analytical derivatives double as the **gold correctness oracle**
  (finite-difference-checked once, then the equivalence reference).

## C level

`bench/derivShowcaseC.m` carries the embeddable (`i`/inline) cells the rest of
the way: through **Embedded Coder (ERT)** to a static `lib`, then measures the
**honest compiled footprint** of the derivative function — ROM (`.text`+`.rdata`),
static RAM (`.data`+`.bss`) via `size -A`, and max stack via `gcc -fstack-usage`
— alongside a MEX for numeric equivalence + runtime and compile time. All four
methods are **compiled cells** here: AD forward/reverse, the **analytical**
reference, and **finite differences** — the FD wrappers (`showcase/fd/*`)
code-generate through ERT like any other, so FD gets a real on-target footprint,
not just an interpreted-cost column. Because FD evaluates the cost n times, its
compiled ROM is a **multiple** of the hand-derivative's (below: `4.8×` gradient,
`9.0×` Hessian, `2.45×` Jacobian at n=8) — the "cheap to write, but O(n)
evaluations in flash, and inexact" trade the table makes concrete. (An interpreted
FD-cost column, `FD (ms)`, is also kept per row for the O(n²) host scaling.)
Skip-clean where Coder (or the standalone `gcc`/`size` toolchain) is absent.

```matlab
addpath bench
rc = derivShowcaseC('n',8,'timeReps',2, ...
    'figPath','bench/showcase_scaling.png', ...
    'texPath','docs/userguide/bench_compare.tex');   % committed guide fragment
```

Snapshot (inline mode, n = 8, MATLAB R2024a + MinGW; ROM/RAM/stack in bytes).
`FD (ms)` is the interpreted central-finite-difference cost of the same
derivative — the numerical leg of the analytical / numerical / AD triad:

| function | DerType | impl | unroll | ROM | RAM | stack | MEX≡analytic | MEX (ms)² | MATLAB (ms)² | FD (ms)² | compile (s)² | C src (B)¹ |
|---|---|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|
| vcostfun | gradient | AD | 1 | 208 | 0 | 160 | yes | 0.002 | 0.050 | 0.036 | 14.1 | 19505 |
| vcostfun | gradient-reverse | AD | 1 | 208 | 0 | 160 | yes | 0.002 | 0.004 | 0.004 | 3.4 | 17939 |
| vcostfun | gradient | analytic | — | 160 | 0 | 160 | yes | 0.002 | 0.001 | 0.006 | 3.4 | 17764 |
| vcostfun | gradient | FD | — | 768 | 0 | 368 | yes | 0.003 | 0.014 | 0.005 | 3.8 | 22945 |
| vcostfun | hessian | AD | 1 | 224 | 0 | 160 | yes | 0.002 | 0.070 | 0.202 | 2.8 | 20576 |
| vcostfun | hessian | analytic | — | 224 | 0 | 144 | yes | 0.002 | 0.001 | 0.142 | 2.9 | 18633 |
| vcostfun | hessian | FD | — | 2016 | 0 | 736 | yes | 0.020 | 0.204 | 0.142 | 3.5 | 29668 |
| vvecfun | jacobian | AD | 1 | 224 | 0 | 304 | yes | 0.002 | 0.049 | 0.011 | 2.4 | 19308 |
| vfun | jacobian | AD | 0 | 448 | 0 | 288 | yes | 0.003 | 0.172 | 0.021 | 3.4 | 20484 |
| vvecfun | jacobian | analytic | — | 176 | 0 | 176 | yes | 0.002 | 0.001 | 0.010 | 2.9 | 17948 |
| vvecfun | jacobian | FD | — | 432 | 0 | 320 | yes | 0.003 | 0.015 | 0.006 | 2.8 | 21516 |

> **ROM/RAM/stack are the compiled footprint of the derivative *function*** —
> the `<wrapper>.c` (+ `<wrapper>_data.c` static tables) object, excluding the
> lifecycle stubs, the `examples/` main and the `interface/` MEX gateway (none
> deploy to the target). Measured from the ERT object with `size` /
> `-fstack-usage`, not the codegen report (whose static-code-metrics tables
> silently do not populate for generated AD code).
> ¹ `C src (B)` is the sum of generated `.c`/`.h` *source* bytes — a
> boilerplate-dominated proxy kept only as a secondary column; **do not read it as
> ROM** (its small forward-vs-reverse spread is comments, not footprint).
> ² runtime + compile columns are single-sample and machine-dependent — read as
> order-of-magnitude.

**The honest finding: for these vectorized costs the footprints CONVERGE.**
Forward and reverse gradient are byte-identical (ROM 208 / 208), the analytical
floor is only ~50 B under, and **static RAM is 0 across the board** — the
embeddable (`i`) forms carry ≈0 static data, so there is no ROM/RAM story to tell
them apart. The forms that *would* differ (data-heavy index tables) are the
data-heavy vectorized-Hessian / subscripted-scalar shapes; the ROM comparison here
is on the ≈0-static-data vectorized costs.

![Compiled ROM, compiled MEX runtime, and interpreted numerical-FD-vs-AD scaling vs n](showcase_scaling.png)

- **AD vs analytical is a *code-lines* story here, not a footprint one.** The hand
  derivative is 4–5 lines vs the AD wrapper's 18–187 (MATLAB-level table above),
  and both compile to ≈0-data objects of comparable ROM. For these *simple* costs
  hand-coding is cheapest, as expected — the value of AD is the **crossover** at
  scale, where the derivative grows large/sparse enough that hand-deriving it
  becomes impractical or silently drops sparsity. The analytical column also
  doubles as the gold correctness oracle (`SDerivShowcaseTest` finite-difference-
  checks it once).
- **Runtime is COMPARABLE, not a reverse win** (the figure's middle panel).
  Across `n` = 256 / 1024 / 4096 the compiled MEX times are forward and reverse
  both O(n) and within noise of each other. The forward-vs-reverse choice here is
  bought with **neither footprint nor speed** — it is a code-generation-style
  preference at this scale.
- **Numerical finite differences are where AD earns its keep** (the figure's
  right panel — the analytical / numerical / AD *cost* triad). At the *interpreted*
  host level (finite differences aren't deployed to target, hence no ROM), the
  numerical-FD gradient of `vcostfun` costs **3.1 / 19.4 / 164 ms** at
  `n` = 256 / 1024 / 4096 — `n` perturbations × an O(n) cost each, i.e. **O(n²)
  work asymptotically** (the sampled window is pre-asymptotic — ~6–8× per 4× `n`
  — as each eval still carries vectorized-op overhead, but already pulling away) —
  while reverse AD stays O(n) (**0.02 / 0.05 / 0.19 ms**) and the analytical floor
  is O(n) too. By `n` = 4096 FD is ~**860×** slower, and the gap widens with `n`.
  FD is also only *approximate* (truncation + round-off), so it is slower **and**
  less accurate. This is the durable, machine-independent "why AD over
  finite-differencing a gradient" — read the **scaling**, not the noisy
  single-`n` absolutes in the table above.
- **Compiled ROM is roughly `n`-flat for a vectorized cost** (left panel): `n` is
  a runtime array length, not unrolled code, so neither the generated code nor its
  ≈0 static data grows with the number of variables.
- **rolled vs unrolled, to C:** `vvecfun` (unrolled, ROM 224) vs `vfun` (rolled,
  ROM 448) Jacobian both compile and match — the rolled loop pays a modest ROM +
  stack premium here. The rolled axis reaches C here for the Jacobian; the
  MATLAB-level table above covers the rolled scalar-cost gradient/Hessian.
- **MEX ≡ analytic exactly** on every cell (the embed modes return identical
  numbers, compiled). `SCodegenShowcaseTest` pins build + numeric equivalence
  **and** the measured footprint (ROM/RAM/stack populated, forward/reverse
  convergence).


## Loopbound padding penalty

A `loopbound` derivative is generated once at `N = Nmax` and called with any
runtime `n <= Nmax` (padded-program semantics). `bench/loopboundPaddingPenalty.m`
measures what that padding **costs** vs a file regenerated at exact `n`, for the
subscripted scalar-cost anchor `scostfun_lb` (`J = Σₖ₌₁ᴺ exp(xₖ)+2xₖ`), inline
`i` / ERT:

```matlab
addpath bench
rp = loopboundPaddingPenalty('Nmax',64,'nSweep',[4 8 16 32 64]);
```

Snapshot (gradient, `Nmax = 64`, MATLAB R2024a + MinGW). Padded(Nmax) footprint
is **n-independent**: ROM 4624, RAM 0, stack 240 bytes.

| n | exact ROM | exact RAM | exact stack | ROM penalty (padded/exact) |
|---:|---:|---:|---:|---:|
| 4 | 640 | 0 | 240 | 7.2x |
| 8 | 560 | 0 | 160 | 8.3x |
| 16 | 736 | 0 | 176 | 6.3x |
| 32 | 1504 | 0 | 192 | 3.1x |
| 64 | 4592 | 0 | 224 | 1.0x |

- **The penalty is real and it is in ROM.** A *subscripted* (allocation-shaped)
  derivative carries a per-iteration nonzero-location table that scales with the
  trip count; the padded file keeps the full `Nmax`-sized `static const` tables
  regardless of `n`, so at `n = 4` you pay **~7×** the ROM of an exact-`n` file.
  RAM stays 0 (tables are `.rdata`, not RAM) and stack is comparable.
- **It converges at `n = Nmax`** (1.0×) — padded and exact are the same file
  there — and grows with `Nmax/n`, so it is largest exactly where a runtime bound
  is most useful (a big `Nmax` seldom hit).
- **It quantifies the cost of the runtime bound.** The padding penalty is exactly
  what a symbolic-`N` bound (sizing the tables to the runtime `n` instead of
  `Nmax`) would remove: for subscripted forms run at `n ≪ Nmax` the ROM penalty is
  multiple-×; for vectorized forms (≈0 static data, C level above) or when
  `n ≈ Nmax`, it is negligible.
- **Gradient measured; the Hessian rides the same padding.** A loopbound Hessian
  of a scalar cost is supported, so extending this measurement to the
  second-derivative padding is a natural add. Pinned by `SLoopboundPaddingTest`.

---

*Development context (roadmap, design rationale) lives in `docs/ROADMAP.md` and
`docs/DESIGN.md`.*
