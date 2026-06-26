# Derivative showcase — which mode should I pick?

Roadmap **R17** (issue #73 item B), MATLAB level. One derivative of a curated
anchor function generated through every relevant axis, with its generated-code
complexity measured and its value checked against the analytic derivative. This
is the "which mode should I pick?" artifact.

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

| function | DerType | C bytes | MEX≡analytic | MEX (ms) | MATLAB (ms) | compile (s) |
|---|---|---:|---|---:|---:|---:|
| vcostfun | gradient | 19505 | yes | 0.003 | 0.138 | 15.9 |
| vcostfun | gradient-reverse | 17940 | yes | 0.004 | 0.016 | 2.9 |
| vcostfun | hessian | 20669 | yes | 0.003 | 0.095 | 3.3 |
| vvecfun | jacobian | 19309 | yes | 0.003 | 0.067 | 2.1 |

![compiled-C size vs n](showcase_scaling.png)

- **The §3.5 result carries to compiled C:** the reverse gradient's generated C
  is consistently **leaner** than the forward gradient's (≈17.9 k vs ≈19.5 k
  bytes, ~8 %), and the reverse builds faster — it has no nonzero-location
  scatter to emit.
- **Compiled-C size is `n`-flat for a vectorized cost** (the figure): `n` is a
  runtime array length, not unrolled code, so the C does not grow with the
  number of variables; the forward/reverse gap is a roughly constant offset.
- **MEX ≡ MATLAB exactly** on every cell (the embed-mode C-4 guarantee compiled).
  At these sizes the MEX runtime is at the `timeit` floor (~0.003 ms) so the
  compiled-vs-compiled comparison is noise here; the *interpreted* MATLAB column
  still shows reverse (0.016 ms) cheaper than forward (0.138 ms), reflecting its
  smaller operation count. (`SCodegenShowcaseTest` pins build + equivalence +
  reverse-is-leaner; the rolled-loop anchors are excluded from the C level —
  rolled-loop codegen is a separate concern, ANALYSIS §2.3(7).)

