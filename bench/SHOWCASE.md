# Derivative showcase — which mode should I pick?

Roadmap **R17** (issue #73 item B), MATLAB level. One derivative of a curated
anchor function generated through every relevant axis, with its generated-code
complexity measured and its value checked against the analytic derivative. This
is the "which mode should I pick?" artifact.

Each AD axis is also measured against a hand-coded **analytical** derivative —
the "do I even need this tool?" baseline and the gold correctness oracle (#73).
It's a reference *column*, not a grid cell: a hand derivative has no
embed/slim/unroll variants, so it appears once per DerType with those fields
blank (`mode = ana`, `—` elsewhere).

Regenerate this table with:

```matlab
addpath bench
r = derivShowcase('n',6,'reportPath','bench/showcase_table.md');   % MATLAB level
```

The **C level** (compiled-C size + `timeit` MATLAB-vs-MEX runtime over an
`n`-sweep, via MATLAB Coder / `matlabtest.coder.TestCase`) is **R17b** and adds
the runtime columns + a figure.

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
  the AD-vs-analytical reference (each FD-checked once by `SDerivShowcaseTest`).

## Snapshot (n = 6)

| function | DerType | mode | slim | unroll | der_levels | code lines | .mat bytes | idx tables | idx elems | correct |
|---|---|---|---|---|---|---:|---:|---:|---:|---|
| scostfun | gradient | c | 0 | 0 | — | 46 | 478 | 3 | 78 | ok |
| scostfun | gradient | l | 1 | 0 | — | 41 | 310 | 3 | 78 | ok |
| scostfun | gradient | i | 1 | 0 | — | 51 | 0 | 0 | 0 | ok |
| scostfun | gradient | i | 0 | 0 | — | 51 | 0 | 0 | 0 | ok |
| scostfun | gradient | i | 1 | 1 | — | 130 | 0 | 0 | 0 | ok |
| scostfun | hessian | c | 0 | 0 | — | 124 | 1038 | 11 | 246 | ok |
| scostfun | hessian | i | 1 | 0 | — | 142 | 0 | 0 | 0 | ok |
| scostfun | hessian | i | 1 | 0 | [2] | 140 | 0 | 0 | 0 | ok |
| scostfun | gradient-reverse | c | 0 | 1 | — | 177 | 288 | 12 | 12 | ok |
| scostfun | gradient-reverse | l | 0 | 1 | — | 172 | 288 | 12 | 12 | ok |
| scostfun | gradient-reverse | i | 0 | 1 | — | 187 | 0 | 0 | 0 | ok |
| vfun | jacobian | c | 0 | 0 | — | 45 | 484 | 4 | 120 | ok |
| vfun | jacobian | i | 1 | 0 | — | 50 | 0 | 0 | 0 | ok |
| vfun | jacobian | i | 1 | 1 | — | 135 | 0 | 0 | 0 | ok |
| vcostfun | gradient | l | 0 | 1 | — | 24 | 249 | 1 | 6 | ok |
| vcostfun | gradient-reverse | l | 0 | 1 | — | 18 | 0 | 0 | 0 | ok |
| vcostfun | gradient | ana | — | — | — | 4 | 0 | 0 | 0 | ok |
| vcostfun | hessian | ana | — | — | — | 5 | 0 | 0 | 0 | ok |
| vvecfun | jacobian | ana | — | — | — | 4 | 0 | 0 | 0 | ok |

(Numbers are a snapshot; regenerate as above. `SDerivShowcaseTest` guards
correctness + the headline relationships, not the exact figures.)

## How to read it

- **`embed_mode`** is a *where-does-the-constant-data-live* knob, not a numeric
  one (all three are bit-identical, DESIGN §Contracts C-4): `c`/`l` keep the
  index tables in a `.mat` (small code, non-zero `.mat bytes`); `i` inlines them
  as source (no `.mat`, more `code lines`). Pick `i` for a fully self-contained
  artifact, `l` when the constants are large and you'd rather not inline them.
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
  number of variables the way a forward *dense* Jacobian/Hessian does (ANALYSIS
  §3.5). Use reverse (`gradient-reverse`) for objective gradients / first-order
  embedded solvers; forward for Jacobians and where `m ≈ n`.
- **AD vs analytical** is the user-facing column ("do I even need this tool?").
  A hand derivative is tiny here — `4`–`5` code lines vs the AD wrapper's `18`
  (vectorized reverse) to `187` (rolled reverse) — and carries no data, because a
  human writes the closed form directly. That's expected and is the *point*: for
  a simple cost, hand-coding wins; AD's value is at scale, where the derivative
  is large/sparse enough that deriving and maintaining it by hand becomes
  impractical or silently drops sparsity. The crossover — not a win/lose — is the
  story; see the C level for where reverse AD nearly matches the hand floor. The
  analytical derivatives double as the **gold correctness oracle** (FD-checked
  once, then the equivalence reference).

## C level (R17b)

`bench/derivShowcaseC.m` carries the embeddable (`i`/inline) cells the rest of
the way: through MATLAB Coder to a static `lib` (generated-C size) and a MEX
(numeric equivalence + runtime), with compile time. Skip-clean where Coder is
absent.

```matlab
addpath bench
rc = derivShowcaseC('n',8,'figPath','bench/showcase_scaling.png');
```

Snapshot (inline mode, n = 8, MATLAB R2024a + MinGW):

| function | DerType | impl | unroll | C bytes | MEX≡analytic | MEX (ms) | MATLAB (ms) | compile (s) |
|---|---|---|---:|---:|---|---:|---:|---:|
| vcostfun | gradient | AD | 1 | 19505 | yes | 0.003 | 0.118 | 13.5 |
| vcostfun | gradient-reverse | AD | 1 | 17940 | yes | 0.002 | 0.006 | 2.8 |
| vcostfun | gradient | analytic | — | 17766 | yes | 0.002 | 0.001 | 3.0 |
| vcostfun | hessian | AD | 1 | 20666 | yes | 0.002 | 0.114 | 2.3 |
| vcostfun | hessian | analytic | — | 18635 | yes | 0.003 | 0.002 | 2.2 |
| vvecfun | jacobian | AD | 1 | 19309 | yes | 0.003 | 0.064 | 2.3 |
| vfun | jacobian | AD | 0 | 20484 | yes | 0.004 | 0.190 | 2.7 |
| vvecfun | jacobian | analytic | — | 17950 | yes | 0.003 | 0.002 | 2.6 |

![AD vs analytical compiled-C size and runtime vs n](showcase_scaling.png)

- **AD vs analytical — reverse AD nearly matches the hand floor.** The hand-coded
  analytical gradient is the smallest compiled C (≈17.8 k bytes) and the cheapest
  to evaluate — it's the floor, what a user writes *without* this tool. The key
  result: **reverse AD (≈17.9 k) lands right on that floor**, while forward AD
  (≈19.5 k) sits above it; the analytical Hessian/Jacobian are likewise the floor
  for their DerTypes. For these *simple* costs hand-coding is the cheapest, as
  expected — the value of AD is the **crossover** at scale, where the derivative
  is large/sparse enough that hand-deriving it becomes impractical or silently
  drops sparsity, and reverse AD already matches hand-coded ROM with none of the
  by-hand effort. (The analytical column is also the gold correctness oracle;
  `SDerivShowcaseTest` FD-checks it once.)
- **The §3.5 result carries to compiled C:** the reverse gradient's generated C
  is consistently **leaner** than the forward gradient's (≈17.9 k vs ≈19.5 k
  bytes, ~8 %), and the reverse builds faster — it has no nonzero-location
  scatter to emit.
- **…but runtime is COMPARABLE, not a reverse win** (the figure's right panel,
  and #73's runtime axis). Across `n` = 256 / 1024 / 4096 the compiled MEX times
  are forward 0.006 / 0.014 / 0.045 ms vs reverse 0.006 / 0.010 / 0.045 ms — both
  O(n) and within noise of each other. The reverse advantage is **code size and
  ROM, not speed**; pick reverse to shrink the artifact, not to run faster.
- **Compiled-C size is roughly `n`-flat for a vectorized cost** (left panel):
  `n` is a runtime array length, not unrolled code, so the C barely grows with
  the number of variables; the forward/reverse gap is a roughly constant offset.
- **rolled vs unrolled, to C:** `vvecfun` (unrolled) vs `vfun` (rolled) Jacobian
  both compile and match — the rolled file is a bit larger (20.5 k vs 19.3 k)
  and slower to interpret. Note **rolled *scalar-cost* gradient/Hessian do not
  codegen** (a separate concern, ANALYSIS §2.3(7) / roadmap R19), so the rolled
  axis reaches C here only for the Jacobian; the MATLAB-level table above covers
  the rest.
- **MEX ≡ analytic exactly** on every cell (the embed-mode C-4 guarantee
  compiled). The interpreted-MATLAB column still shows reverse (0.006 ms) cheaper
  than forward (0.118 ms) — the interpreter pays per-statement overhead the
  compiled code amortizes. (`SCodegenShowcaseTest` pins build + equivalence +
  reverse-is-leaner.)

