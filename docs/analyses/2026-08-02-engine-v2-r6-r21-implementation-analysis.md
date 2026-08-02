# 2026-08-02 — R6 Tier-2 (symbolic N) and R21 (fixed-size scatter): implementation analysis

**Dated snapshot at master `494c765`** (post-#224/#225/#226/#227; the engine
reads and line citations were taken against this tree). This is a **HOW** analysis
— mechanism, choke points, hazards, and verification — deliberately not a
why/when: the go/no-go itself stays with the
[`../ROADMAP.md`](../ROADMAP.md) **R6** decision gate and is not made here.
Authored by the reviewing session **without MATLAB access**: every claim
grounded in source is cited; every claim that needs a running MATLAB is
labelled **[H]** (hypothesis) and collected as numbered experiments (§7) for
a MATLAB-equipped session to run before any of this is committed to.

> **Update 2026-08-02 — all six experiments have now been run** by the authoring
> session (MATLAB R2024a, MATLAB Coder + Embedded Coder licensed, MinGW, ADR-0027
> toolchain, strict no-heap `adigatorCoderConfig`). Measured results are folded in
> below: resolved hypotheses are marked **[M]** with the number, and §7 carries
> the per-experiment outcome. Two findings changed the text rather than merely
> confirming it — **E1 falsified its own pass criterion** (§4, B2 needs
> emitter-form canonicalization) and **E2 beat its prediction** (generators
> compile to *no* table, not to a folded one). The go/no-go still stays with the
> R6 gate; this remains a HOW analysis.

**Associated roadmap rows:** [R6](../ROADMAP.md) (decision gate on #6 Tier 2 /
#11 Level 3), [R17](../ROADMAP.md) (the padding-penalty evidence the gate is
decided on), [R19](../ROADMAP.md) (rolled-loop reverse),
[R20](../ROADMAP.md) (codegen completeness, #80),
[R21](../ROADMAP.md) (fixed-size scatter — the subject of §3).

**Associated issues:**
[#6](https://github.com/pdlourenco/adigator-embedded/issues/6) (loopbound
tiers; Tier 2 = symbolic N),
[#11](https://github.com/pdlourenco/adigator-embedded/issues/11) (N-D levels;
Level 3 is the Route-C-class rewrite),
[#80](https://github.com/pdlourenco/adigator-embedded/issues/80) (ERT
completeness; the R21 spike),
[#56](https://github.com/pdlourenco/adigator-embedded/issues/56) (reverse
mode — unblocked by scatter),
[#73](https://github.com/pdlourenco/adigator-embedded/issues/73) (benchmark
harness; source of the R17 numbers),
[#87](https://github.com/pdlourenco/adigator-embedded/issues/87) (CasADi
independent oracle — the rewrite's ground truth),
[#210](https://github.com/pdlourenco/adigator-embedded/issues/210) /
[#213](https://github.com/pdlourenco/adigator-embedded/issues/213) (trip-count
guard family; §4.2 and §6 touch it),
[#217](https://github.com/pdlourenco/adigator-embedded/issues/217) (the
overmap-width defect whose fix, ADR-0036, prototyped part of the scatter
arithmetic),
[#206](https://github.com/pdlourenco/adigator-embedded/issues/206) (reverse
support matrix — its embedded column depends on §3).

**Associated ADRs:**
[ADR-0018](../decisions/ADR-0018-casadi-independent-oracle.md),
[ADR-0019](../decisions/ADR-0019-rolled-embeddable-path-scatter-deferred.md)
(the deferral this analysis scopes),
[ADR-0030](../decisions/ADR-0030-csc-sparse-pattern-contract.md),
[ADR-0033](../decisions/ADR-0033-strict-shared-coder-config.md) (the strict
Coder profile E2 compiles under),
[ADR-0034](../decisions/ADR-0034-generated-code-emission-hygiene.md),
[ADR-0035](../decisions/ADR-0035-embeddability-gate-calibrated-to-hand-written.md),
[ADR-0036](../decisions/ADR-0036-overmap-directed-pruning-rolled-printing-run.md).

---

## 1. Where `n` is baked into a generated file today — the five sinks

Any symbolic-N design must resolve each of these; they are the complete list
of places the analyzed size becomes a literal.

**S1 — Loop headers.** `lib/adigatorForInitialize.m:279–280` prints
`for c = 1:%d` from `MAXLENGTH`; Tier 1 replaces the literal with the
parameter name when `adigatorLoopboundMatch` (value-keyed,
`lib/adigatorLoopboundMatch.m:19`) finds a bound. Already runtime under
Tier 1 — this sink is solved.

**S2 — Size literals in remaps and allocations.**
`lib/@cada/cadaPrintReMap.m:133/163/175` prints `zeros(%d,1)` at `nzover`;
lines 204–228 print `(1:%d,...)` truncations/extensions from `func.size`
literals. Every overloaded op prints sizes the same way (via `func.size`
integers).

**S3 — Index tables.** `lib/cadaUtils/cadaindprint.m` stores every index
vector as a *numeric literal* in `ADIGATORDATA.DATA.IndexK` →
`Gator<d>Data.IndexK` (`.mat` in classic mode, inlined literals via
`embedding/structure_to_embed_mfile.m` in embed modes). There are no
expression-valued indices anywhere in the data path.

**S4 — Per-iteration tables.** For rolled loops,
`lib/@cada/adigatorAnalyzeForData.m` collects one column per iteration
(`REFINDS`, `[NUMinds × prod(FORLENGTHS)]`, lines 151/201) and — when
`GetDataDependencies` says the indices actually vary with the iteration —
emits a table referenced as `Gator1Data.IndexK(:,cadaforcountJ)` (the
`DataName`/`CountName` splice in `AssignReferenceNames`, `:2588` — with
`DataName` built at `:2562` — and its sibling at `:2687`; note the different
block at `:122–129` splices `IndName(CountName)`, a scalar *trip count*, not
an index column). The column *count* is the
analyzed trip count; the column *contents* are literal index vectors. This is
simultaneously the Tier-1 ROM padding cost (tables are `Nmax` wide regardless
of runtime `n` — the R17 finding) and the hard blocker for symbolic N (a data
table cannot have a symbolic number of columns).

**S5 — Derivative-pattern metadata.** `nzlocs` lists, `nzover` counts, output
`*_size`/`*_location`/CSC metadata (contracts C-1/C-2, ADR-0030) are explicit
integer data derived from patterns computed at the analyzed size.

## 2. The one symbolic-dimension mechanism that already exists, and its exact boundary

Vectorized mode threads a symbolic size through the *entire* printer today:
`func.size` holds `Inf` for the free dimension, and every print site branches
on `isinf` to emit `size(x,1)` instead of a literal — visible in
`cadaPrintReMap.m:54–80` (the `isinf` classification that computes `vecDim`)
and `:130/158/173` (the `zeros(size(f,1),%1.0f)` prints that consume it). This works
because of three enforced invariants:

1. The free dimension never enters a sparsity pattern — derivatives are
   stored per-block (`[N × nz]` data, pattern of one block), so
   `nzlocs`/`nzover` stay N-independent.
2. No reduction across it — refused at `lib/@cada/sum.m:90–91`
   (`'Cannot sum over vectorized dimension'`), i.e. an enforced error, not
   only a guide restriction.
3. No loop over it — refused outright in `lib/adigatorForInitialize.m:64`
   and `:109` ("Cannot loop over vectorized dimension", in both the unroll
   and overmap arms).

**[M] E4** catalogued the boundary with 29 single-op probes: **12 accepted, 17
refused**. The fence is *wider* than the three sites above — subsref (`x(1)`,
`x(end)`, `if x(1)`: "Invalid vectorized subsref"), subsasgn (`y(1)=…`:
"Invalid vectorized subsasgn"), the colon form
(`x(2:end)`: "may only use colon as 1:N, 1:1:N, or N:-1:1"), catenation along the
free dimension (`[x;x]`), and `prod`/`max`/`norm` all carry designed messages
too, for 11 named refusals in all. Accepted: elementwise ops, `x'`, `x(:)`,
`[x,x]`, `repmat`, and `length`/`numel`/`size` used as values.

> **Correction (see `ANALYSIS.md` §1.3n / B40).** An earlier revision of this
> paragraph said four ops — `mean`, `reshape(x,[],1)`, `x'*x`, `cumsum` — "are
> overloaded yet fail with generic MATLAB errors rather than a named refusal".
> That was wrong on all four, and was inferred from the error identifiers
> without checking whether the overloads exist. Corrected:
>
> - `mean` and `cumsum` have **no `@cada` overload at all** — like `diff`/`sort`
>   they sit *outside* the fence, and fail identically in non-vectorized mode.
> - `reshape` and `mtimes` **do** carry designed vectorized refusals
>   (`reshape.m:120–122`, `mtimes.m:130–131`); the probes bypassed them.
>   `reshape(x,[],1)` dies on the unsupported `[]` dimension placeholder and
>   fails the same way on a plain `[3 1]` input (verified) — not a vectorized
>   defect.
> - The one genuine hole is **`x'*x`**: `mtimes` keys its guard on the *result*
>   dimensions (`:129`), so a contraction *over* the free dimension with a
>   finite result slips past it into `true(…,Inf)` → `MATLAB:nonaninf`.
>   Semantically this is `sum`'s case and wants `sum`'s refusal.
> - Separately, **none** of the eleven named refusals carries an error
>   identifier — all are bare `error('…')`, so none is programmatically
>   catchable, unlike `adigator:loopbound:rangemismatch`. That is the half §4.2's
>   "refuse loudly with a named id" posture actually bears on, and it is what
>   Tier 2 inherits along with the fence.

**This is the load-bearing observation for Tier 2:** the printer's
symbolic-size plumbing exists and is proven; what has never existed is
symbolic *sparsity* — and invariants 2–3 are precisely the fence around
that. Tier 2's content is not "make sizes symbolic" (done, for one
dimension); it is "let a loop/reduction cross the symbolic dimension", which
is exactly where per-iteration patterns (S4) and pattern-dependent counts
(S5) arise.

## 3. R21 — fixed-size scatter: precise mechanism

### 3.1 What the code does today (the shape to be replaced)

Inside a rolled loop's printing run, every operand carries its FOR overmap
(post-#217/PR #221, pruned to the *target* overmap where scalar expansion would
over-widen). Each iteration's derivative statement therefore operates at
**`nzover` width**: the accumulator update for the canonical
`J = Σₖ φ(x(k))` gradient is an `nzover`-length vector op per iteration, with
per-iteration gathers through S4 tables. Cost: O(`n·nzover`) runtime = O(n²)
at `nzover ≈ n`; under Tier-1 padding, O(`n·Nmax`). ADR-0019 defers exactly
this.

### 3.2 Target emission

The overmap pass (RUNFLAG 1) knows the final location set before anything
prints (ADR-0019 records this from the #80 spike; `cadaOverMap` /
`cadaUnionVars` compute it). The scatter form inverts the current order —
*compute narrow, remap late*:

- Operands inside the loop keep their **per-iteration** width `nz_k` (no lift
  to `nzover` before the op).
- Each op's result is written into the overmap-sized accumulator through a
  per-iteration **position map**:
  `yd(Gator1Data.IndexK(:,c)) = yd(Gator1Data.IndexK(:,c)) + contrib;`
  where the column holds the overmap rows of iteration `c`'s nonzeros —
  `[nz_k × niters]`, replacing today's `[NUMinds × niters]` index tables
  feeding `nzover`-wide ops.
- For the allocation shape `nz_k` is O(1) — **[M] E6**: on the padded
  `scostfun_lb` gradient at `Nmax = 64`, `nz_k = 1`, and a hand-written scatter
  form reproduces the generated file's values *exactly* (max abs difference `0`
  at n = 1, 2, 8, 16, 32, 64; central-FD agreement ~8e-9; padded tail exactly
  zero) while cutting ROM 4400 → 160 B (27.5×), `.rdata` 4128 → 16 B, and stack
  352 → 96 B (3.7×). So the update is O(1) per iteration: O(n) runtime, O(1)
  extra stack, and the table narrows to `[1 × niters]` (and see §5 — here, to
  nothing: the position map is the affine family `col(c) = c`). *Runtime itself
  was not timed — E6 measured values, ROM and stack.*

### 3.3 Choke points and blast radius

- **`lib/@cada/cadaPrintReMap.m`** — the single point where "lift to
  `nzover`" is emitted (`zeros(nzover,1)` + `Dind` scatter, lines 120–177).
  The ADR-0019 spike already identified it. The change is not local to it,
  though: the decision *not* to lift must be made where operands enter ops.
- **`lib/@cada/cadaOverMap.m:192–198`** (the remap condition #217/PR #221 mirrored in
  `lib/@cada/private/cadaOverMapTargetNz.m`) — the gate that decides a variable is about to be
  remapped; the scatter path reuses exactly this gate to decide "defer the
  remap, record the position map instead". #217 did the read-only half of
  this (pass the target pattern *down* into the op); scatter is the
  read-write half (keep the op narrow, push the *result* up). The #217
  machinery (`cadaOverMapTargetNz` + the `ismember(...,'rows')` alignment in
  `cadaRepDers`) is a working prototype of the pattern-intersection
  arithmetic scatter needs everywhere.
- **`lib/@cada/cadabinaryarraymath.m` / `lib/@cada/private/cadaRepDers.m` and
  the union logic** — every binary op inside a loop currently assumes both operands
  are at compatible (overmapped) widths; with narrow operands, the
  union/alignment arithmetic runs at `nz_k` instead. This is the
  ~15–20-file blast radius ADR-0019 names; #217 touched four of them
  read-only.
- **`lib/adigatorForIterEnd.m`** — loop-boundary union of iteration
  variables into the overmap; must record position maps per iteration
  instead of (or alongside) forcing remaps.
- **Beyond `@cada`:** `embedding/structure_to_embed_mfile.m`,
  `embedding/adigatorSlimEmbeddedDeriv.m`,
  `embedding/adigatorStripDeadOutputIndices.m` all pattern-match generated
  text/data with literal-table assumptions — they see different table shapes
  and (in the §5 extension) expressions. Budget them into the diff. Note
  `structure_to_embed_mfile.m:210` already range-compresses whole-array
  arithmetic progressions (`numel ≥ 16` ⇒ `a:s:b`); generator recognition
  generalizes that from *whole arrays* to *column families*, so the two must not
  be built independently.
- **Emission detail worth knowing before measuring anything:** in inline (`'i'`)
  mode there is **no** `<wrapper>_data.c` — the static tables are emitted inside
  `<wrapper>.c`. `measureErtFootprint`'s header comment describes them as living
  in `_data.c`, which holds for the classic/`'d'` shapes but not for the inline
  artifacts this analysis is about (**[M] E5**).

### 3.4 Hazards specific to scatter — the ones that decide the design

**HZ-1: duplicate scatter targets (the principle-1 trap).** MATLAB's indexed
assignment drops duplicate writes: `yd([1 1]) = yd([1 1]) + [a b]` adds only
`b`. Today's overmap-width path is immune — contributions are summed as full
vectors. The scatter path is safe **only if each iteration's position-map
column has unique rows**; a repeated subscript inside one iteration breaks it
*silently*. Whether any emitted position-map column can carry duplicate rows *at
all* is exactly E3's question — the binary-op pattern arithmetic unions
coincident locations before emission, so the answer may well be "never"; the
fallback costs nothing if it is. **[M] E3 (bounded)**: a static census over the
emitted tables of seven cases over four functions — `scostfun_lb`, `scostfun`,
a two-subscript
`x(k)*x(k-1)`, and an adversarial `x(k)*x(k) + x(k)` written to force a repeat —
gradient and Hessian, found **zero** duplicate rows in any per-iteration column
(14–24 columns per case). That is *necessary, not sufficient*: it reads the
tables today's emission built, and the scatter map is derived from the same
overmap, so the RUNFLAG-1 census E3 specifies is still the one to run before the
uniqueness proof is relied on. The design must either
(a) prove per-column uniqueness at RUNFLAG 1 and **fall back to the current
remap emission per site when it fails** (fail-closed, the #226/#227 posture),
or (b) emit accumulation-safe forms (`accumarray`-style — but ERT support
must be checked, and the generated code is likely worse). Recommendation:
(a). It also gives the rewrite an incremental landing path: scatter becomes
an *optimization applied where proven safe*, with the existing path as the
always-correct fallback. That converts ADR-0019's "highest correctness
stakes in the repo" into "per-site opt-in with a static safety proof", the
same shape ADR-0036 used.

**HZ-2: read-modify-write on struct fields (Gap-A family).**
`yd(idx) = yd(idx) + t` is exactly the read-then-add shape that tripped ERT
when the operand was a static struct field (#80 Gap A, fixed by routing
through a local temp). Scatter accumulators must be **locals**, never
`Gator*Data` fields; position-map *reads* from `Gator1Data` are fine. **[M] E6**:
ERT accepts indexed read-modify-write on a local with a runtime index under the
strict no-heap profile — the E6 prototype's `ydx(k) = ydx(k) + …` compiled and
measured clean.

**HZ-3: loopbound padded semantics.** Accumulator init
`yd = zeros(nzover,1)` stays outside the loop; skipped iterations under
`1:N` simply never write — the structural-zero tail is preserved by
construction. No hazard, but `SLoopboundPaddingTest`/`ILoopboundTest` must
be re-run over the new emission (license-free, so hosted CI covers them).

**HZ-4: contract C-3.** The `Index*`/`Data*` Gator-data layout is a binding
contract surface ([`../DESIGN.md`](../DESIGN.md) §Contracts). A table-shape
change means the contract updates *first*, same PR, per `CLAUDE.md` §3 —
this is not optional ceremony; `util/adigatorParseTape.m` and the
slim/embed tooling read that layout.

### 3.5 Verification apparatus (already in place)

The CasADi independent oracle (ADR-0018, #87), the Monte-Carlo campaign with
`oracleFiniteDiff`/`oracleDerOutputInvariance`, the `SStackScalingTest` /
ADR-0035 gate (scatter should move the *unrolled* and padded columns), and
`IRolledOvermapWidthTest`'s growth-law style, which generalizes directly to
"per-iteration table width is O(`nz_k`)".

## 4. R6 Tier 2 — three routes, and which one is actually buildable

**Route A — extend the vectorized `Inf` machinery to loop dimensions.** Lift
invariant 3 (allow `for k = 1:N` over a symbolic N) and invariant 2 (allow
reductions). Everything in §2 that makes vectorized mode sound then breaks:
per-iteration patterns need a symbolic representation. Without S4 resolved
this is not incremental — it is Route C wearing Route A's clothes. Viable
only for the loop-free subset (all sizes `a·N+b`, *no* rolled loop, *no*
pattern that depends on N except block replication) — which vectorized mode
already covers. Route A alone adds approximately nothing.

**Route C — true symbolic sparsity core** (the #11 Level-3 class).
`func.size` entries and `nzlocs` become symbolic objects (affine forms
`a·N+b`; patterns as parameterized families), with a union/product/
composition algebra over them. Handles everything, including `1:N-1` affine
headers (the B39 expressive gap; #6's own Tier-2 text). Blast radius:
effectively all of `@cada` plus the flow analyzers — the sparsity algebra is
a new kernel, and every one of the ~200 overloads consults patterns. This is
a rewrite of the tool's core idea (concrete-instance abstract
interpretation) into a parametric one: months, and every line
principle-1-exposed. Not recommendable as the first move under any schedule.

**Route B — expression re-emission with a build-time constant (the buildable
one).** Keep the engine exactly as it is: analysis stays concrete, run at
`Nmax` (or a reference size). Change what gets *printed*: every S2/S3/S4/S5
literal that is a function of N is emitted as an **expression of the bound
parameter** instead of a number — `zeros(N,1)` instead of `zeros(64,1)`,
`reshape(1:2*N,2,N)`-style generators instead of baked index tables, `N` in
the CSC metadata. The generated `.m` is then generic in N at the MATLAB
level; at build time the integrator passes `N` (or the family's `Nmax`) as
`coder.Constant`, and Coder constant-folds every expression at build time —
**[M] E2, and the outcome beats what this paragraph originally predicted**
("folds back into the `static const` tables today's files carry"). A minimal
generic kernel (`zeros(N,1)`, an `uint32(reshape(1:1:N,N,1))` index generator,
`for k = 1:N`, a scatter update) compiled under the strict profile with
`coder.Constant(64)` produces ROM **48 B**, `.rdata` **0**, and **zero**
`static const` declarations: the affine generator is not folded *into* a table,
it is **eliminated** — Coder proves `idx(k) == k`, collapses it into the loop
induction variable, and auto-vectorizes the body. The runtime-`N` control costs
144 B with `.rdata` 16 B and keeps a `tmp_data[64]` materialization loop. So
*where the generator is affine*, Route B does not reproduce today's tables — it
deletes them. Scope: measured on the identity family `idx(k) = k`, the easiest
case for Coder to collapse into an induction variable; other affine families and
all non-affine tables are untested, and §5 step 2 keeps the table on a miss.
The bound moves from generation time to
build time, which is exactly the R6 modularity ask (one qualified source
artifact per unit family; N a configuration parameter of the *build*),
without symbolic sparsity ever existing inside adigator.

The engineering question Route B turns on: **where do the expressions come
from**, given the analysis only ever saw concrete numbers? Two mechanisms,
and they compose:

- **B1 — provenance tracking (exact, narrow).** At the sites where a size is
  *known* to be the bound — Tier 1 already identifies them
  (`adigatorLoopboundMatch` names the loop; the bound parameter's
  `func.value` is `Nmax`) — propagate a taint: "this integer is `N`" / "this
  is `a·N+b`", carried alongside the concrete value (a two-field affine tag
  on `func.size` entries and on lengths flowing into `cadaindprint`). Print
  sites check the tag and emit the expression. This is *incremental*:
  untagged values print as literals exactly as today, so partial coverage
  degrades to Tier 1, never to wrongness. The tag algebra is trivial (affine
  forms are closed under +, scalar ·, and length concatenation); anything
  non-affine drops the tag. This is a *shadow* of Route C at the size level
  only — patterns stay concrete.
- **B2 — two-point reconstruction (the verifier, and the fallback for
  tables).** Generate at two (better three, pairwise-coprime — e.g.
  7/11/13, avoiding collisions like `n == Nmax`) sizes. Require the emitted
  *code text* to be identical modulo numeric literals and table contents —
  if not, symbolic N is structurally unsupported for this function:
  **refuse** (the B39/#227 posture). Fit each differing literal to `a·N+b`
  (or a declared polynomial degree for genuinely quadratic objects like
  dense-Hessian metadata); fit each S3/S4 table to per-entry affine forms in
  (position, iteration). Anything that does not fit ⇒ refuse. Then the
  **held-out check**: evaluate the reconstructed generic file at a fourth
  size and require byte-identical output to a fresh generation at that size.
  That last step is what makes B2 trustworthy despite being inference: it
  converts "we guessed the law" into "the law reproduces generation exactly
  at a size it never saw" — a mechanical, per-function certificate, and it
  runs license-free (it compares generated text, not compiled artifacts).

  **[M] E1 — B2's text-identity predicate needs canonicalization, and the
  anchors above are wrong.** As specified, B2 compares emitted text "modulo
  numeric literals and table contents". Against today's emitter that predicate is
  **length-sensitive in two places**, neither of which reflects derivative
  structure:

  | flip | at | site |
  |---|---|---|
  | index table `[…]` → `a:s:b` | `numel ≥ 16` | `embedding/structure_to_embed_mfile.m:210` |
  | `y.dx = […]` → `Gator<d>Data.Data<k>` | `numel ≥ 10` | `lib/@cadastruct/subsasgn.m:105` and `:181` |

  Measured by sweeping n = 6…20; diffing the n = 9 and n = 10 Hessians confirms
  the statement sequence is otherwise identical, so it is pure printing policy.
  The 7/11/13 + 17 anchors **straddle both cuts**, so B2 would have reported
  "structure drifts ⇒ refuse" on functions that reconstruct perfectly. Re-run
  with every anchor above both thresholds (17/19/23, **29 held out**): structure
  identical for all three anchor cases, **0** non-affine scalars
  (107/10, 245/15, 75/8 constant/affine), and **0** held-out misses.

  Fix — either works, the second is preferred because the first hard-codes a
  hidden coupling to two magic numbers in unrelated files:

  1. constrain B2's anchors (and E1's) to sit above both thresholds; or
  2. **canonicalize before comparing** — both forms are deterministic functions
     of the array's own contents (length, plus integrality and, for the range
     form, an exact arithmetic-progression test) and never of derivative
     structure, so B2 can normalize `a:s:b` ↔ literal list and `Data<k>` ↔
     inline literal and diff the canonical text. Note the guards are wider than
     the length cut alone: `structure_to_embed_mfile.m:210–216` also requires
     real, finite, integer-valued, `< 2^53` **and** `all(diff(A) == diff(A)(1))`;
     `subsasgn.m:105/181` also require `all(floor(b(:)) == b(:))`. The
     canonicalization holds regardless of which guard fired — but do not build
     the predicate from the length cut alone.

  Without this, B2's measured refusal rate is an artifact of emitter formatting
  and would argue for Route C on false evidence.

Recommended composite: **B1 for sizes** (exact where it applies, no
inference), **B2 as the generation-time certificate and the table-generator
inference** (with the canonicalization above), Route A's existing `Inf`
plumbing untouched. Route C only if B2's refusal rate turns out to matter on
real unit families — and E1 now shows that rate must be measured *after*
canonicalization, or it measures the printer rather than the design.

### 4.1 Tier-2 per-sink resolution (Route B composite)

| Sink | Resolution |
|---|---|
| S1 headers | Already runtime (Tier 1). Affine headers `1:N-1` additionally become expressible (§6). |
| S2 size literals | B1 tags → expressions; B2 certifies. |
| S3 static tables | B2 generator inference, or — after R21 + §5 — most vanish. |
| S4 per-iteration tables | **The hard one.** A symbolic column count is unrepresentable as data. Resolved only by R21's shape change (columns become `nz_k`-wide position maps) *plus* generator recognition (§5): a table whose column `c` is an affine function of `c` is emitted as the expression of `cadaforcountJ`, eliminating the table and its N-dependence at once. Without R21, Tier 2 must refuse any function whose loop has iteration-dependent indices — nearly every interesting one. **This is the R21↔Tier-2 coupling, with its mechanism explicit.** |
| S5 pattern metadata | B1/B2 expressions; CSC `Nnz` and the pattern arrays as generators. Contracts C-1/C-2 (ADR-0030) must gain a "generic-N form" clause first. |

### 4.2 Tier-2 obligations beyond the engine

- **Guards.** A generic-N file needs a *floor*, not an equality: small-`n`
  structural collapse (patterns that saturate, ops that take scalar special
  cases at n ∈ {1,2}) means B2's law only holds for `n ≥ n_min`; the file
  must open with `assert(N >= n_min);` — a new guard shape, which under
  ADR-0034 decision 4 means recognizers + the lockstep test extended in the
  same PR, pinned to third order. The B36 `==` guard and Tier-1 `<=` guard
  machinery (#210/#211, #213) is the template; all three shapes are mutually
  exclusive per name and the emitters must enforce that.
- **Re-differentiation refuses.** Feeding a generic-N file back through
  `adigator()` breaks every assumption the trip-count re-diff machinery has
  (literal headers, literal tables). Refuse loudly with a named id, pinned —
  `util/adigatorCheckTripCountRediff.m` is the pattern.
- **ADR-0035 gate rows.** A generic file built at `N = n` must land within
  the existing K× of hand-written at that n; add sweep cases.
- **Contract-first ordering** (`CLAUDE.md` §3): C-1/C-2/C-3 and
  `adigatorDerivativeConventions.m` all gain generic-N clauses *before* the
  emitters change.

## 5. The combined "engine v2" — why the order is scatter → generators → Tier 2

R21 with the generator extension does most of Tier 2's work as a side
effect:

1. **Scatter** (R21 proper): per-iteration widths drop to `nz_k`; tables
   become `[nz_k × niters]` position maps. Targets O(n) runtime, unrolled
   bounded stack, reverse-mode embeddability — **[M] E6** for the footprint
   half (ROM 27.5×, stack 3.7×, values exact on a hand-written prototype);
   the O(n) *runtime* claim remains inferred from the emitted shape, not
   timed. N stays concrete.
2. **Generator recognition** (small, on top): at RUNFLAG 2, before
   `cadaindprint`, test each position-map column family for
   `col(c) = a·c + b` (an exact integer check). Hit ⇒ emit the expression of
   `cadaforcountJ`, no table. For the allocation anchor the emitted update
   collapses to `yd(c) = yd(c) + contrib;` — *zero* index ROM (**[M] E2**
   measured a hand-written equivalent, since nothing emits this form today:
   48 B, `.rdata` 0, no table), which also
   shrinks the Tier-1 padding penalty: R17 attributes the padded ROM's
   `n`-independence to `Nmax`-sized `static const` tables, and generators
   delete the tables they fire on. **[M] E5 sizes it: 93.1%.** The padded
   `scostfun_lb` gradient at `Nmax = 64` is **4400 B = 272 B `.text` +
   4128 B `.rdata`**, and that `.rdata` is essentially one declaration —
   `static const signed char iv[4096]` (4096 B = 93.1% of total ROM), the
   `[64 × 64]` per-iteration position map of S4. Across the exact-`n` sweep
   `.rdata` is **exactly n² bytes** (16/64/256/1024/4096 at n = 4/8/16/32/64)
   while `.text` is 384/176/192/192/192 — `n`-independent from n = 16 up, with
   a larger frame at n = 4. (ROM totals 400/240/448/1216/4288 reproduce
   `bench/SHOWCASE.md`'s exact-`n` column.) Generator recognition still
   only fires on affine column families; miss ⇒ keep the table (fail-closed).
3. **Tier 2** (Route B): with S4 already expression-valued, B1+B2 only have
   S2/S3/S5 left — the tractable sinks.

Two consequences worth stating plainly: **(i)** step 2 **materially weakens** the
quantitative case for Tier 2, because the padding penalty that moved the R6
evidence toward "go" is made of the tables step 2 removes — **[M] E5**: the share
is **93.1%** on the anchor the penalty is measured on, i.e. step 2 does not merely
dent the figure, it removes almost all of it. So *if* the engine-v2 sequence starts,
`bench/loopboundPaddingPenalty.m` should be re-measured after step 2 before
those figures are leaned on as Tier-2 evidence. This is an observation for
the R6 gate, not a new precondition on it. **(ii)** each step is independently shippable and
independently verifiable, and step 1 carries the fail-closed fallback
(HZ-1), so the "highest correctness stakes" rewrite never has a big-bang
landing.

## 6. What closing the gap opens

**Functionality:**

- Reverse-mode embeddability (reverse requires `unroll=1`; scatter bounds
  its stack) — unblocks the R18/R19 chain and the embedded column of the
  #206 support matrix.
- O(n) rolled runtime; padded runtime O(n) instead of O(n·Nmax) — Tier 1
  becomes cheap enough that *more* families can simply use it.
- Affine loop headers: once generator emission exists, `for b = 1:N-1` is
  expressible (emit the header expression + position maps in `c`),
  converting the B39 refusal (#213 route 4a) into support (route 4b) and
  reopening B36 route 2 (struct-field bounds) with less ceremony.
- Generic-N artifacts: one qualified source per unit family, N as build
  configuration — the modularity ask behind R6; generation-in-build also
  becomes trivial since generation no longer needs to run per-N.
- The B2 certificate machinery (generate at k sizes, diff, fit, held-out
  check) is a reusable V&V instrument independent of Tier 2 — it detects
  *any* unintended n-dependence in emission, a bug class (#217 was one)
  nothing currently guards structurally.

**Problems:**

- HZ-1 duplicate-scatter silent wrongness — the single worst risk; the
  fail-closed per-site fallback is the mitigation.
- Contract-surface churn (C-1/C-2/C-3, `adigatorDerivativeConventions.m`,
  ADR-0030) — three binding documents move; drift risk across the long
  sequence unless each step lands contract-first.
- Small-`n` piecewise laws → wrong generic files without the `n_min` floor
  guard; the floor itself is a new user-visible restriction to document.
- Re-diff of generic files unsupported → must refuse; higher-derivative
  users of Tier 2 get there via the `adigatorGenHesFile`-style routes only.
- The embed tooling (`structure_to_embed_mfile`, slim, strip) parses literal
  tables; expression-valued data breaks its assumptions — audit before
  step 2, not after.
- Coder behavior becomes load-bearing: constant folding of generator
  expressions (E2) and read-modify-write acceptance on locals (E6) are
  properties of the *toolchain*, now verified once on R2024a + MinGW under the
  strict profile — and requiring re-verification per toolchain, since nothing in
  CI can check them ([`../CI_PLAN.md`](../CI_PLAN.md) §3.2 applies to every
  codegen claim in this analysis; Coder is unlicensed on hosted runners).

## 7. Experiments for the MATLAB session

Each: what to run → what each outcome means. These gate the design.

> **All six were run on 2026-08-02** (MATLAB R2024a, Coder + Embedded Coder
> licensed, MinGW; ADR-0027 `size -A` / `gcc -Os -fstack-usage`; strict no-heap
> `adigatorCoderConfig`). Outcomes are recorded per experiment below; in each
> bullet the text above **Result** is the original specification, verbatim, so
> its future tense is deliberate. The harnesses (`lbsum`, the `x(k)*x(k)+x(k)`
> probe, the E2 generic kernel, the E6 hand-written scatter) were scratch files
> and are **not retained in the tree** — re-running means re-writing them from
> the descriptions here.

| # | Outcome | One-line result |
|---|---|---|
| E1 | **design passes, criterion failed** | structure stable + held-out exact *once anchors clear two emitter thresholds*; B2 needs canonicalization (§4) |
| E2 | **passes, beats prediction** | `coder.Constant(64)` ⇒ 48 B ROM, `.rdata` 0, **no** table (generator eliminated, not folded) |
| E3 | **no duplicates** (bounded form) | 0 duplicate rows over 7 anchors incl. an adversarial repeat; RUNFLAG-1 census still owed |
| E4 | **catalogued** | 12 accept / 17 refuse; fence wider than §2 states; one hole (`x'*x` contraction) and no refusal carries an error id |
| E5 | **93.1%** | padded 4400 B = 272 `.text` + 4128 `.rdata`; one `static const signed char iv[4096]`; `.rdata` = n² bytes in the exact-`n` sweep |
| E6 | **passes decisively** | exact values vs generated; ROM 4400→160 (27.5×), stack 352→96 (3.7×); HZ-2 confirmed |

All E5/E6 figures are the `scostfun_lb` gradient at `Nmax = 64`, inline (`'i'`)
mode, one anchor — not a corpus average.

- **E1 — structural stability + literal fit.** Generate
  `examples/jacobians/loopbound/lb_alloc.m` / the `scostfun` anchor
  (gradient + Hessian) at n = 7, 11, 13, 17. Diff generated text modulo
  literals; fit literals/tables to affine forms; held-out check at n = 17.
  *All-affine + identical structure* ⇒ Route B viable as specified;
  *structure drifts* ⇒ Tier 2 needs refusal-heavy scoping (or Route C).
  Also directly measures the refusal rate B2 would have.
  **Result — the design passes, the criterion above does not.** At 7/11/13/17
  structure *does* drift, but only from two emitter formatting thresholds
  (`structure_to_embed_mfile.m:210`, `numel ≥ 16`; `@cadastruct/subsasgn.m:105`
  and `:181`, `numel ≥ 10`) — pinned by sweeping n = 6…20, and the n = 9 vs
  n = 10 statement sequences are otherwise identical. Re-run at 17/19/23 with
  **29 held out**: structure identical for `scostfun` gradient, `scostfun`
  Hessian and a rolled `lbsum` gradient; **0** non-affine scalars; **0**
  held-out misses. So the criterion as written would have argued for Route C on
  a printer artifact — see the B2 canonicalization requirement in §4.
  *Spec nit:* `lb_alloc.m` has two outputs, so it is not usable as the
  single-output gradient anchor named here; a self-written `lbsum` stood in.
- **E2 — constant folding.** Hand-write a minimal generic file
  (`zeros(N,1)`, a `reshape`-generator index, loop `1:N`), compile with
  `coder.Constant(64)` under `util/adigatorCoderConfig.m`; inspect the C for
  `static const` tables and the absence of runtime index computation.
  *Folds* ⇒ Route B's build-time story holds; *does not* ⇒ generators cost
  runtime ROM/cycles and the design needs a pre-build MATLAB "specialize"
  step instead (still viable, one artifact less elegant).
  **Result — folds, and better than "folds".** `coder.Constant(64)`: ROM 48 B,
  `.text` 48, `.rdata` **0**, **zero** `static const` declarations — the affine
  index generator is *eliminated* (Coder proves `idx(k) == k`, folds it into the
  induction variable, auto-vectorizes), not merely baked into a table. Runtime-`N`
  control: ROM 144 B, `.rdata` 16 B, plus a residual `tmp_data[64]`
  materialization loop. Route B's build-time story holds.
- **E3 — duplicate-index census.** Instrument RUNFLAG 1 to log
  per-iteration remap-target columns with duplicate rows across the
  example + test corpus. *Rare/never* ⇒ the HZ-1 fallback is a corner case;
  *common* ⇒ scatter needs the accumulation-safe emission designed up
  front.
  **Result (bounded form) — none found.** Rather than instrument the engine, a
  static census read the tables the current emission built for seven cases over
  four functions
  (`scostfun_lb`, `scostfun`, a two-subscript `x(k)*x(k-1)`, and an adversarial
  `x(k)*x(k) + x(k)`), gradient and Hessian: **0** duplicate rows in any
  per-iteration column, 14–24 columns per case. Supports HZ-1's own guess and
  therefore fallback (a). **This is necessary, not sufficient** — it reads
  today's tables, and the scatter map is derived from the same overmap, so the
  RUNFLAG-1 census specified above is still owed before the uniqueness proof is
  relied on.
- **E4 — vectorized refusal boundary.** Catalog exactly which ops error on
  the `Inf` dimension (sum, scalar subsref, loop, …). Defines what Tier 2
  must *not* promise and cross-checks §2's invariants.
  **Result — 12 accept / 17 refuse of 29 probes; see §2.** The fence is wider
  than §2 states — subsref, subsasgn, the colon form, catenation and
  `prod`/`max`/`norm` all carry designed messages, 11 named refusals in all.
  Two real gaps, **corrected** from this bullet's first revision (see the
  correction box in §2, and `ANALYSIS.md` §1.3n / B40): the one hole is `x'*x`,
  where `mtimes` keys its guard on the *result* dimensions and so misses a
  contraction *over* the free dimension; and none of the 11 refusals carries an
  error identifier, so none is programmatically catchable. *Method note:* the first
  single-process batch produced three spurious `MATLAB:FileIO:InvalidFid`
  verdicts, one of which turned the **accepted** `y = x.^2` into a false refusal;
  all three were re-run in fresh processes and the table above reflects those.
  The obvious explanation — that a failed generation leaves the engine's print
  FID closed and poisons later ops — **was tested and does not hold**: in one
  session, good → refused → good → good all behave correctly through plain
  `adigator()`, a refused generation leaves **0** open fids and the global count
  unchanged, and replaying the batch's opening sequence reproduces no failure.
  B16's error-path cleanup (`adigatorClearTransformGlobals` at
  `adigator.m:993/1000`) holds. So this is a **harness artifact of undetermined
  mechanism**, not an engine defect — recorded here as a caution, not a bug.
  Run one process per op, or at minimum re-run every `InvalidFid` in isolation.
  Worth noting separately: `UCoreErrorHygieneTest` pins "no leaked fids, clean
  globals after a failure" but **not** "a subsequent generation succeeds in the
  same session" — the property that appeared to have broken. It holds today
  (measured); it is simply unpinned.
- **E5 — table share of the padding penalty.** Decompose the padded 4400 B
  ROM: bytes in `[· × Nmax]` tables vs everything else. Quantifies how much
  step 2 (generators) undercuts the Tier-2 motivation — the §5(i)
  re-measure, available *now* without building anything.
  **Result — 93.1%.** Padded `scostfun_lb_Grd` at `Nmax = 64` reproduces 4400 B
  exactly: **272 B `.text` + 4128 B `.rdata`**, the `.rdata` essentially one
  `static const signed char iv[4096]` (the `[64 × 64]` S4 position map). The
  exact-`n` sweep gives `.rdata` = **n² bytes** (16/64/256/1024/4096 at
  n = 4/8/16/32/64) against `.text` of 384/176/192/192/192 — `n`-independent
  from n = 16 up, with a larger frame at n = 4. ROM totals
  (400/240/448/1216/4288) reproduce `bench/SHOWCASE.md`'s exact-`n` column, so
  the split is consistent with the committed figures rather than a fresh
  measurement of them. *Method note:* the decomposition
  is the `.text`/`.rdata` **section split**, not a per-object one — in inline
  mode there is no `<wrapper>_data.c` to separate (see §3.3).
- **E6 — scatter-by-hand prototype.** Hand-edit one generated
  rolled-gradient file to the §3.2 scatter form; verify values against
  CasADi/FD, ERT-compile, measure stack/runtime/ROM. Validates the target
  emission (including HZ-2) before any engine line changes — the cheapest
  possible de-risk of the whole sequence.
  **Result — validates it.** Hand-written §3.2 form vs the padded generated
  gradient at `Nmax = 64`:

  | | ROM | `.text` | `.rdata` | stack |
  |---|---:|---:|---:|---:|
  | generated (today) | 4400 | 272 | 4128 | 352 |
  | hand scatter (§3.2) | **160** | 144 | **16** | **96** |
  | *ratio* | **27.5×** | 1.9× | **258×** | **3.7×** |

  Values are **exactly** the generated file's at n = 1, 2, 8, 16, 32, 64
  (max abs difference `0`), central-FD agreement ~8e-9, padded tail exactly zero
  (HZ-3 holds by construction). `nz_k = 1`, and the position map is the affine
  family `col(c) = c` — which by E2 costs nothing. HZ-2 confirmed.
  *Not measured:* runtime. E6 asks for stack/runtime/ROM; this run has values,
  ROM and stack, so §3.1's O(n·nzover) → O(n) claim stays inferred from the
  emitted shape rather than timed.

---

**Bottom line (how, in one paragraph).** R21 is a per-site inversion at the
`cadaOverMap`/`cadaPrintReMap` boundary — compute at per-iteration width,
scatter the result through a position map, with a fail-closed fallback to
today's emission wherever per-column uniqueness cannot be proven. Tier 2 is
*not* a symbolic core: it is expression re-emission (provenance tags for
sizes, two-point reconstruction with a held-out certificate for tables) over
an unchanged concrete engine, with the bound folded back in at build time
via `coder.Constant` — and it only becomes tractable after R21's shape
change plus affine-generator recognition have eliminated the per-iteration
tables, which is the concrete content of "one combined engine-v2 effort"
(ADR-0019 / R21 ↔ R6). Each of the three steps ships and verifies
independently; E1/E2/E6 are the three results that could falsify the design,
and E5 is the number that could shrink Tier 2's motivation before anyone
builds it.

**All six have now been run (2026-08-02); the four that could move the design
resolve as follows.** E2 and E6 pass — E6 decisively
(values exactly equal to today's artifact, 27.5× ROM, 3.7× stack, HZ-2
confirmed), E2 better than this document predicted (generators compile to *no*
table rather than a folded one). E1 falsified **its own criterion** rather than
the design: structure is stable and the held-out certificate exact once anchors
clear two emitter formatting thresholds, so B2 gains a canonicalization
requirement (§4) — without it, B2's refusal rate measures the printer instead of
the design. E5 returns **93.1%**, which sharpens §5(i) from "could materially
weaken" to "does": step 2 removes almost all of the padded ROM the Tier-2
motivation rests on. Net: the design survives, §5's sequencing argument gets
stronger, and the *quantitative* case for Tier 2 specifically gets weaker — a
question for the R6 gate, which this analysis still does not make.
