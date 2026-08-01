# ADiGator-embedded: implementation & math-documentation analysis

Analysis of the embeddable derivative-generation fork of ADiGator (v1.5),
covering (1) bugs, (2) optimization opportunities for embedded targets, and
(3) a path to reverse-mode differentiation. Line numbers refer to the state
of branch `claude/adigator-analysis-46lir7` (base commit `e9ffeff`).

Background used throughout: a generated derivative `y.dX` is the vector of
possible nonzeros of the *unrolled* Jacobian (size `[prod(ysize), prod(xsize)]`,
column-major linearization on both sides), ordered by ascending linear index;
`y.dX_location` has one column per dimension listed in `y.dX_size`
(see `lib/@cada/adigatorPrintOutputIndices.m` and User Guide §"Evaluating
Derivative Files"). `Gator*Data.Index*` fields hold index vectors
(`cadaindprint.m`), while `Gator*Data.Data*` fields hold **numeric value
constants used in arithmetic** (`cadamatprint.m`).

---

## 1. Bugs

> **Status (read first).** The bug descriptions in §1.1–1.3 are the original
> analysis and are written in the present tense of when they were found. Their
> **current disposition is tracked in [§1.5 Fix disposition log](#15-fix-disposition-log)**:
> every bug **B1–B16** is **Fixed**, **Mitigated**, or **Won't-fix (benign)**.
> (B16, §1.3b, was surfaced by the issue-#38 Monte-Carlo hygiene fuzzer and
> fixed in ROADMAP R9 B.3.) **B17–B22** (§1.3c) are a newer batch: B17–B21 were
> triaged from a local (proprietary) embedded field report, B22 was found during
> the B17 review — **B17 is now fixed** (the §1.3c description predates the fix);
> **B19 is partially resolved (plain `while`-counter → the actionable B20 symbolic-index error; the `if`-guarded shape has a residual over-approximation rough edge, #108 — both principle-1-safe); B20 is a documented limitation (with an actionable error); B21/B22 are fixed** (B18 no longer
> reproduces); they are the subject of ROADMAP R26. **B23–B26** (§1.3d) are the
> newest batch, from the 2026-07-04 repo-wide code-quality review
> ([`2026-07-04-code-quality-review.md`](2026-07-04-code-quality-review.md))
> — **all four are now Fixed** (B23 #126, B24 #130, B25/B26 #132; the
> reverse-mode matrix-division *adjoint* is a separate follow-up, R30/#128), each
> pinned; see §1.5. Tracked in issue
> [#117](https://github.com/pdlourenco/adigator-embedded/issues/117) / ROADMAP
> R28 (workstream 1; workstreams 2–5 in #118–#121 remain). Where a
> description below names a file/line (e.g. B1's old
> `adigatorGenDerFile_embedded.m` location), §1.5 records where the code
> actually lives now (`embedding/prune_adigator_mat.m`).

### 1.1 Embedded pipeline (new code)

**B1 — `Data*` constants are down-cast to integers (high severity).**
`prune_adigator_mat` (`embedding/adigatorGenDerFile_embedded.m:209-216`)
down-casts *every* integer-valued, non-sparse numeric field to
`uint32`/`int32`. This is safe for `Index*` fields, but `Data*` fields are
value constants printed into arithmetic, e.g. for `y = A*x` with `A = eye(2)`
the generated code contains `cada1f1 = Gator1Data.Data1*x.f;`. After
down-casting, `uint32 * double` either errors at runtime ("Integers can only
be combined with integers of the same class, or with scalar doubles") or, in
scalar cases, silently propagates an integer class and *rounds all subsequent
derivative values*. Integer-valued constant matrices (identities, selection
matrices, +/-1 stencils) are extremely common.
*Fix:* apply the down-cast only to fields matching `Index*`
(`startsWith(idxName,"Index")`); leave `Data*` as `double`.

**B2 — `fprintf` format defect in the generated data-function header.**
`embedding/structure_to_embed_mfile.m:38` uses a format string containing a
single (unescaped) `%` and no trailing `\n`:
`'%% Auto-generated ... on %s\n% Helper file for ADiGator generated derivatives'`.
MATLAB discards everything from the invalid conversion (`'% H...'`) onward, so
the "Helper file" comment is silently dropped today — and under any
implementation that printed the remainder literally, `S = struct();` from the
next `fprintf` would be appended to a comment line, producing a broken data
function. *Fix:* escape as `%%` and terminate with `\n`.

**B3 — multi-match line deletion in the patcher is wrong.**
`embedding/adigator_patch_derivative.m:43-47`:

```matlab
for ii=1:length(idx)
    txt(idx+inc) = [];   % uses the WHOLE idx vector every iteration
    inc = inc - 1;
end
```

For a single match this works; for two or more matches the first iteration
already deletes all matched lines, and subsequent iterations delete arbitrary
*shifted* lines. Currently only one `if isempty(...); ADiGator_LoadData(); end`
block exists per file, so the bug is latent — but it will fire if the loader
guard ever appears in subfunctions. *Fix:* delete once with
`txt(idx) = []` (no loop), or index `idx(ii)+inc`.

**B4 — patcher assumes unique pattern matches.**
`adigator_patch_derivative.m:56-60`: `fidx = find_in_file(txt,patterns,1,0,'%')`
returns *all* lines containing both `'function'` and the subfunction name;
`txt(1:fidx)` then errors if more than one line matches (e.g. a subfunction
name that is a substring of another, or a comment-free line that both declares
and mentions a function). Substring matching via `contains` is fragile —
anchor on a regexp like `^\s*function\b.*\b<name>\s*\(`.

**B5 — `structout` can be undefined.**
In `prune_adigator_mat` (`adigatorGenDerFile_embedded.m:178-228`), if none of
`funnames` is a field of the loaded struct, `structout` is never assigned and
the function errors with a confusing message. Initialize `structout = struct();`.

**B6 — pruned `.mat` loses re-differentiation metadata.**
Pruning removes the `Derivative`/non-`Gator*Data` fields that
`adigatorFunctionEnd.m` saves for `DERNUMBER > 1`. Fine for runtime, but the
pruned `.mat` can no longer be used as the input of a further `adigator` call.
Worth a printed warning or a `_pruned` filename suffix.

### 1.2 Dimension handling in the Jacobian/gradient/Hessian wrappers

**B7 — vector-function Hessian row index uses `n` where the layout needs `m`
(inherited from upstream, still present).**
`util/adigatorGenHesFile.m:376` emits, for `m = numel(y) > 1`:

```matlab
xyind1 = (xind1-1)*n + yind;      % n = numel(x)
Hes = zeros(m*n, n); Hes((xind2-1)*(m*n) + xyind1) = y.dXdX;
```

The documented layout (header line 58: `size(Hes) = [m*n n]`) and the
sparsity pattern returned to the user
(`output.HessianStructure`, line 489: `HesRow = (HesLocs1(:,2)-1)*m + HesLocs1(:,1)`)
both use row `= (x1-1)*m + y`. With multiplier `n`:
- if `n > m`: the row index can exceed `m*n` → runtime "index out of bounds";
- if `n < m`: distinct `(y, x1)` pairs collide → **silently wrong Hessian**;
- only `m == n` coincidentally works.
Unaffected: the dominant scalar-objective case (`m == 1` takes the
`rowind = xind1` branch) — which is why this has survived. *Fix:* multiply by
`m`, and add a vector-output Hessian test.

**B8 — matrix-function-of-scalar Hessian branch dead/wrong (inherited,
flagged by an in-code comment but not fixed).**
`adigatorGenHesFile.m:319`: `elseif any(n == 1)` is always true inside the
`n == 1` branch, so the sparse projection (lines 322-326) is unreachable.
Worse, for a true matrix output (`r,c > 1`) line 321 emits
`Hes(y.dXdX_location) = y.dXdX;` where `y.dXdX_location` is an `nnz×2`
*subscript* matrix; MATLAB treats it as linear indices over all its elements →
wrong placement / size mismatch. *Fix:* branch on `any(ysize == 1)` (as was
done at lines 339/351) and convert subscripts with
`(loc(:,2)-1)*ysize(1) + loc(:,1)` for the matrix case.

**B9 — sparse vs. full layout inconsistency for non-scalar "gradients".**
`adigatorGenHesFile.m:453` (v1.5 change) transposes only the sparse branch:

```matlab
Grd = sparse(row,col,y.dX,m,n)';   % -> n×m  (denominator layout)
...
Grd = zeros(m,n); Grd((col-1)*m+row) = y.dX;   % full branch -> m×n
```

For a vector-valued `y` the wrapper therefore returns `n×m` or `m×n`
depending on the (size/density-dependent) sparse heuristic. It also disagrees
with `adigatorGenJacFile.m:339`, which never transposes. Decide one layout per
convention table and apply it in both branches (and only when the *gradient*
convention is requested).

**B10 — `output.JacobianStructure` wrong/erroring for remapped shapes
(inherited).**
`adigatorGenJacFile.m:276-286` remaps `dydxsize` to the matrix shape for
"scalar function of matrix variable" (`dydxsize = xsize`) and "matrix function
of scalar variable" (`dydxsize = ysize`), but line 361 still builds

```matlab
sparse(nzlocs(:,1), nzlocs(:,2), 1, dydxsize(1), dydxsize(2))
```

with `nzlocs` indexing the *unrolled* `[prod(ysize) × prod(xsize)]` Jacobian.
Column indices up to `n*m` are then placed in a matrix declared `n×m` (or row
indices up to `r*c` in `r×c`) → `sparse` errors or produces a wrong pattern.
The remapped cases need `ind2sub`-style decomposition like the wrapper body
does.

**B11 — char-comparison of `embed_mode` is brittle.**
`opts.embed_mode == 'c'` (`adigatorGenJacFile.m:337`,
`adigatorGenHesFile.m:322,378,451`) errors inside `&&` if a user sets
`embed_mode = 'classic'` (non-scalar logical). Use
`strncmpi(opts.embed_mode,'c',1)` or validate the option up front.

**B12 — option parsing lower-cases the field on the wrong side.**
`adigatorGenDerFile_embedded.m:66`, `adigatorGenJacFile.m:95`,
`adigatorGenHesFile.m:94`:

```matlab
opts.(lower(f)) = varargin{1}.(lower(f));   % RHS should be varargin{1}.(f)
```

Any option supplied with the documented upper-case spelling
(`adigatorOptions` help uses `OVERWRITE`, `EMBED_MODE`, ...) in a hand-built
struct errors with "Unrecognized field name".

**B13 — `Gfid` is never closed; the file is immediately read back.**
`adigatorGenHesFile.m:463` runs `fclose(fid)` after the
`for fid = [Gfid,Hfid]` loop, closing only `Hfid`. Upstream this was just a
handle leak, but the embedded pipeline immediately `readlines`-es and rewrites
the Grd wrapper (`adigatorGenDerFile_embedded.m`), risking a partially
flushed file. *Fix:* `fclose(Gfid); fclose(Hfid);`.

**B14 — file-name collision between gradient and Hessian modes.**
`adigatorGenDerFile_embedded('gradient',...)` produces `myfun_Grd` /
`myfun_ADiGatorGrd`; `...('hessian',...)` also produces both. Generating one
after the other silently overwrites the other's files with differently-shaped
outputs (Jac-file gradient wrapper vs. Hes-file gradient wrapper).

### 1.3 Math documentation defects

**Fixed (#118, 2026-07-06).** The four genuine defects below were corrected in
`adigatorDerivativeConventions.m` and the copied `adigatorGenJacFile`/
`adigatorGenHesFile` tables to match contract C-1 (text-only; no behavioural
change). The fifth bullet — the "summary block is inconsistent" claim — was
**re-examined and retracted**: it is a valid generalization of the table (see
that bullet). Disposition row in §1.5.

`adigatorDerivativeConventions.m` (the new conventions spec) contradicted both
itself and the implementation:

- **Jacobian section (lines 30-40):** displays the standard `m×n` Jacobian and
  the usage `Jacobian_x(f) * x` (which requires `m×n`), but states
  `size(...) = [length(x) length(f)]` = `n×m`. The implementation produces
  `m×n`. The size line is wrong (and is mislabeled `size(Gradient(f))`).
- **Hessian section (lines 17-27):** `f: Rn -> Rm` should read `f: Rn -> R`;
  `size(Gradient(f)) = [length(x) length(f)]` should read
  `size(Hessian_x(f)) = [length(x) length(x)]`.
- Line 36 typo: last Jacobian row reads `dfm/dx1 ... dfn/dxn` (`dfn` → `dfm`).
- ~~The summary block (lines 53-58) is internally inconsistent with the
  generalization table.~~ **Retracted (#118).** The example given —
  `any(c,r=1) & any(c,r>1) → r*c x n*m` vs the table's `c×m`/`c×n` for the `r=1`
  row — compares *equal* quantities: for `r=1`, `r*c = c` and `n*m` reduces to
  `m` (n=1) or `n` (m=1), so `r*c×n*m` **is** `c×m`/`c×n`. The block is a correct
  generalization of the table (both express `[numel(f) × numel(x)]`); left
  unchanged.
- The same comment blocks were pasted into `adigatorGenJacFile.m` and
  `adigatorGenHesFile.m` with the same errors — **fixed in #118**. (The earlier
  claim that the *file headers* still carried them was already stale: the
  headers were fixed; only these body tables were not.) The Jacobian file help
  header does not mention that with the `'Grd'` appendix a *column* gradient is
  returned — separate user-facing doc item, out of #118 scope.
- The User Guide (§ adigatorGenHesFile) never states the gradient orientation;
  upstream returned `1×n`, v1.5 returns `n×1` — a silent behavioral break for
  existing callers worth documenting prominently (fminunc/fmincon accept
  both, but user code doing `g*d` will break).

### 1.3a Core-library bug found via PR #1

**B15 — `OuterLoopMaxLenght` undefined-variable crash.**
`lib/@cada/adigatorAnalyzeForData.m:62` referenced the misspelled (and
therefore undefined) variable `OuterLoopMaxLenght` inside
`if size(ForLengths,2) < OuterLoopMaxLength`, so any transformation with
nested rolled `for` loops whose inner-loop length table is shorter than the
outer loop's maximum crashed with "Unrecognized function or variable".
Identified in (now closed) PR #1. **Fixed** along with two comment typos
referring to the nonexistent `RemoveUnneededIndices` (the function is
`RemoveUnneededData`).

### 1.3b Core-library bug found via the Monte-Carlo hygiene fuzzer (issue #38)

Originally `adigator.m` declared `global ADIGATOR ADIGATORFORDATA ADIGATORDATA
ADIGATORVARIABLESTORAGE` at entry and only released them with
`clear global ADIGATOR ...` on the **success path**. The sole `try/catch`
(around the initial user-function eval) restored the path and rethrew but did
not clear those globals; there was no `try/catch`/`onCleanup` around the main
transformation body, where the output file handle (`Dfid`) and the temp dir's
path entry are also held. So when a user function errored mid-transformation,
the session was left with stray `ADIGATOR*` globals, the temp dir still on the
path, and (for functions that fail after `Dfid` opens) a leaked file handle —
a **REQ-T-07** violation ("raise clean errors, restore the MATLAB path, close
all file handles, and leave no stray globals"; the B13 family, previously noted
"currently unpinned" in `CI_PLAN.md`). Surfaced by the issue-#38 `oracleHygiene`
prototype on its first run.

**Fix (ROADMAP R9 B.3, [ADR-0011](../decisions/ADR-0011-adigator-error-path-cleanup.md)).**
Release now happens on **every** exit (normal return or error), in two parts.
The four transformation globals are cleared by a **non-declaring helper
subfunction** (`adigatorClearTransformGlobals`, which runs `clear global …`
without itself declaring those globals) — called once at the end of the body and
once in a `catch` that wraps the body and rethrows. The decisive constraint,
found empirically and confirmed in-situ against the real `adigatorGenJacFile`
flow: a literal `clear global` issued from `adigator`'s **own** frame — which
*declares* the four globals via the top `global` statement — is unreliable on the
**success** path; it re-registers the names *empty* instead of removing them,
leaving a stray (empty) `ADIGATOR`. (The error path's identical in-frame clear
happened to release cleanly, so the leak was success-path-only and stayed
invisible until a *positive*-path `who('global')` check existed — the gated
`UCoreErrorHygieneTest`, which caught it.) Clearing from a helper frame that
never declares these globals releases them on both paths. As defense-in-depth,
the runtime-data global `ADiGator_<name>` is eval-declared in its own subfunction
(`adigatorLoadRuntimeData`), keeping `adigator`'s frame free of an eval-declared
global; an earlier cut that relied on this move-out plus an in-frame clear still
leaked on success, which is why the helper-clear is the load-bearing fix. The
temp dir and the file handles adigator opens (the user source files, per-function
temp files and generated file, found as the delta of the open-fid set against an
entry snapshot, so a caller's own open files are untouched) are released by an
`onCleanup` registered once `filekeeping` has created the temp dir, capturing
what it needs **by value** so it holds no `global` declaration (a callback that
re-declares a still-live global would re-register it empty — the trap the first
cut hit). The runtime data global `ADiGator_<name>` is deliberately **not**
cleared — the generated file needs it. Pinned by **`UCoreErrorHygieneTest`**
(gated `tests/unit`, success *and* error path) and, in the extended suite, the
`mcGenNegative` / `oracleHygiene` pair plus `MCSmokeTest.successLeavesNoOpenHandles`:
malformed fixtures must error, and neither path may leave `who('global')`, the
path, or the open-fid set changed.

### 1.3c Core-transform bugs found via an embedded struct-parameter field report (B17–B22)

A local (proprietary, un-committed under `docs/analyses/`) report of failures
differentiating a struct-parameter-heavy dynamics function through
`adigatorGenDerFile_embedded('jacobian',…,'i')`. Each was triaged against HEAD
with a **non-proprietary** repro; the four groups turned out to be four distinct
root causes, not one.

**B17 — spurious `.f` on constant-struct field references (high severity;
silent broken codegen).** When a struct *constant* is assigned in the function
body — inline (`P = struct(...)`) or from a load (`S = load('x.mat'); P =
S.field`) — the non-overloaded `adigatorVarAnalyzer` `structParse`
(`lib/adigatorVarAnalyzer.m`) turns each numeric field into a `cada` named
`P.field` **classified derivative-bearing** (`VARINFO.NAMELOCS(:,3) ≠ Inf`),
while the struct assignment itself is printed **verbatim**
(`adigatorVarAnalyzer.m:243-248`). So `cadafuncname.m:39` prints `P.field.f` on
every use (as an `mtimes` operand, a subfunction-call input, etc.), but the
verbatim struct has **no `.f` field** → the generated derivative errors at
runtime ("Reference to non-existent field 'f'"). Generation succeeds silently;
only *running* the file reveals it. Contrast that survives: a numeric-array
constant (`K = magic(3)`) is lifted to `K.f = magic(3)` (backed, runs), and
aux-input struct fields are marked derivative-free (`Inf`) so they print bare —
local constant-struct fields are the only ones with the verbatim-vs-lifted
mismatch. Whole-struct passthrough (`q = P.sub`, a sub-struct field) also prints
bare and works.
*Fixed (Option 1):* `structParse` (`lib/adigatorVarAnalyzer.m`) now marks a
numeric (non-cada) struct field — a compile-time constant by construction —
derivative-free (`NAMELOCS(:,3)=Inf`), so `cadafuncname` takes its bare branch
(`:29-31`) and prints `P.field` consistent with the verbatim struct. A
derivative-carrying field is a `cada` (the `isa(x,'cada')` branch) and is
untouched, so R8 struct inputs are unaffected. Pinned by
`tests/integration/IConstStructFieldTest.m` (classic + inline + **load**
provenance, checked against the analytic Jacobian) and verified non-regressing
against the full unit+integration gate (`IStructInputTest`/`IShapeMatrixTest`/
`IEmbedModesTest` incl.).

**B18 — `if` on constant/aux struct-parameter fields (no longer reproduces).**
An `if` whose condition is arithmetic on constant/aux struct fields
(`if (P.a+P.b+P.c)==0 … else <subfunction> … end`) formerly aborted the
transformation. On HEAD it generates and matches finite differences to ~1e-10 on
both branches (most likely resolved by R8 struct-input support). *Disposition:*
regression guard only — pinned by `tests/integration/ICondAuxParamTest.m`
(ADiGator traces both branches and emits a runtime conditional; the Jacobian is
checked against the analytic `M` / `M + a*I` and finite differences for both
parameter selections).

**B19 — `while`-loop counter used as a matrix index (partially resolved; a
residual over-approximation rough edge, [#108](https://github.com/pdlourenco/adigator-embedded/issues/108)).**
Two related shapes, both principle-1-safe (they **error**, never miscompute):

- **Plain `while`-counter index** (`while n<=N; …A(n)…; n=n+1; end`) → the B20
  symbolic-index limitation. ADiGator **deliberately does not unroll `while`
  loops** (`unroll=1` errors "Cannot unroll 'while' loops"), so the counter is a
  runtime (symbolic) subscript. **Resolved:** it raises the actionable
  `adigator:symbolicIndex` error, which now also points to the **`for`-loop
  fix** (a `for` loop *is* unrolled, so the counter is a compile-time constant
  and it generates correctly); genuinely data-dependent indices use the B20
  logical-weight-sum rewrite.
- **`if`-guarded `while`-counter index** (the *original report's* exact shape,
  `while … if (n>1) … A(n) … end … end`) → an internal **index
  over-approximation**: it currently surfaces a raw `MATLAB:badsubscript`
  ("Index in position 2 exceeds array bounds") in the wrapper-build
  (`adigatorGenJacFile`, empty/malformed `nzlocs`), *before* the symbolic-index
  detection, so it does **not** get the actionable message. This is a **residual
  rough edge** — principle-1-safe (it errors, never silently wrong) but cryptic.
  A fix (make it actionable, or resolve the over-approximation in the
  `if`+`while` analysis) is a deeper core investigation, tracked on #108; it is
  **not** a simple guard (a genuinely zero-derivative function shares the
  empty-`nzlocs` site and must return a zero Jacobian, not error).

Pinned by `tests/integration/ISymbolicIndexTest.m` (plain `while`-counter →
actionable error; `for` equivalent generates + differentiates; `if`-guarded
shape → *errors*, the principle-1 invariant, robust to the specific id). ADR-0024.

**B20 — data-dependent (runtime) indexing (limitation; make the error
actionable).** Indexing a variable by a value computed at runtime
(`ref_data(ref_idx,3)` with data-dependent `ref_idx`) is not expressible in
static forward AD with compile-time sparsity (the pattern would be
runtime-dependent). It already errors (`Cannot do strictly symbolic
referencing/assignment` — principle 1, not silently wrong) but cryptically.
*Resolved as a documented limitation* ([ADR-0024](../decisions/ADR-0024-data-dependent-index-actionable-error.md)):
data-dependent indexing stays unsupported, but the error is now **actionable** —
a shared helper `cadaErrorSymbolicIndex` (called from both `@cada/subsref` and
`@cada/subsasgn`) names the construct, explains why static forward AD cannot do
it, shows the logical-weight-sum rewrite, and carries the id
`adigator:symbolicIndex`. Pinned by `tests/integration/ISymbolicIndexTest.m`
(the dynamic index raises the actionable error; the logical-weight rewrite
generates and differentiates correctly). The user-guide note landed with #113
under §Debugging ("Errors Regarding 'Strictly Symbolic' Inputs"), not a separate
Limitations section.

**B21 — user `load(...)` emitted verbatim into the inline/coderload file
(reclassified: warn-and-allow, ADR-0023 rev).** When the differentiated function
itself contains `S = load('x.mat')`, the embedded `'i'`/`'l'` pipeline emits the
`load` verbatim into the generated file — the file is then not self-contained
(the original C-4 concern). Orthogonal to B17 — surfaced while testing B17's load
provenance. *Disposition (revised 2026-07-04):* **reclassified from "C-4
violation → hard block" to "warn-and-allow"** ([ADR-0023](../decisions/ADR-0023-embed-source-scan-gate.md)
rev). Embed is *no more restrictive than classic*: `'l'`/`'i'` emit the user
`load`/`global` verbatim (exactly as classic) and only **warn**
(`adigator:embed:unsupportedConstruct`) that the file is not self-contained and
may not code-generate until the construct is removed — the user may use it
provisionally and make both the original and derivative embeddable later
(pre-loading the data and passing it as an auxiliary input). Embeddability is the
user's responsibility; the tool flags it but does not stop. Constructs classic
itself rejects (bare `load(...)`) still error from the core, unchanged. Capturing
`load`'d constants as embedded `Data*` remains a possible future enhancement.
Pinned by `tests/integration/IEmbedUnsupportedTest.m` (warn + generate +
embed-vs-classic numeric equality).

**B22 — constant-*cell* element analog of B17 (high severity, same class;
fixed).** The B17 fix guards struct fields (`structParse`'s `~structflag` arm); a
numeric element of a constant *cell* assigned in the body reaches `structParse`
with `structflag=1` and was **not** marked derivative-free. Reproduced on HEAD
(found during the B17 review, #102): `C = {M, g}; y = C{1}*x + C{2}*x;` emitted
`C{1}.f` and crashed at runtime (`Dot indexing is not supported … C{1}.f`) —
identical silent-broken-codegen class to B17, cell instead of struct. **Scope,
established empirically:** the affected path is the *verbatim-emitted* constant
container — flat cells (`iscell`, line ~407) and structs nested in cells (both
recurse with `structflag=1`). Constant *struct arrays* (`numel(x)>1`, line ~382)
were initially suspected but do **not** exhibit the bug: they take the *lifting*
path (each field emitted as `P(i).A.f = <value>`, so the `.f` is backed) and are
already correct. *Fixed:* the `structflag=1` numeric arm now marks the element
derivative-free (`NAMELOCS(:,3)=Inf`), so `@cadastruct/subsref` propagates a bare
reference. Pinned by `tests/integration/IConstCellFieldTest.m` (flat cell +
struct-nested-in-cell, classic + inline, vs analytic Jacobian; plus a positive
guard that struct arrays stay correct). Verified against the baseline: the two
cell cases crash without the fix, the struct-array guard passes with or without.
This is the **classic**-mode correctness fix; in **embed** modes (`'l'`/`'i'`)
the same constant cell is emitted verbatim and generates, accompanied by the
source-scan **warning** ([ADR-0023](../decisions/ADR-0023-embed-source-scan-gate.md)
rev 2026-07-04, the same gate that reclassifies B21) that a cell may still be
rejected by MATLAB Coder downstream — the two are complementary: cells are
correct in `'c'` and now numerically identical in `'l'`/`'i'` (verbatim), with a
warning that flags the reduced embeddability.

### 1.3d Silent-wrong-output bugs found via the 2026-07-04 code-quality review (B23–B26)

A repo-wide code-quality review (five parallel deep-read passes plus
independent hand-verification; full report with all medium/low findings in
[`2026-07-04-code-quality-review.md`](2026-07-04-code-quality-review.md))
found four principle-1-class bugs, all verified against the code at `188d8d1`.
Tracked in issue
[#117](https://github.com/pdlourenco/adigator-embedded/issues/117), ROADMAP
R28; each fix lands with its pinning test per `CI_PLAN.md` policy.

**B23 — `HessianStructure`/`HessianLocs` silently corrupted for a matrix
function of a scalar variable (high).** `util/adigatorGenHesFile.m:484-488`
mutates `ysize` for the remap (`remapcase = 2`) but — unlike
`adigatorGenJacFile`, which consults `remapcase` when building
`JacobianStructure` (the B10 fix) — never consults it in the Hessian-metadata
block: at `:610` `HesPat = zeros(ysize)` allocates `r×1` while `HesLocs1(:,1)`
holds linear indices into the unrolled `r×c` output, so MATLAB grows the array
and `output.HessianStructure` becomes a column with `HessianLocs` column
indices all 1. The emitted wrapper is correct (built pre-mutation), so a
consumer scattering `der_output='nonzeros'` values through `HessianLocs`
reconstructs a silently wrong Hessian (REQ-T-03). Half-ported copy of the B10
fix. Unpinned because `IShapeMatrixTest` never asserts the exported structures
(see issue [#119](https://github.com/pdlourenco/adigator-embedded/issues/119)).

**B24 — reverse mode applies the elementwise `./` adjoint to true matrix
division `/` (high; fixed via an unsupported-error guard).**
`util/adigatorGenRevGradFile.m:323` classifies `/` as binary and `:715-720`
emitted the elementwise adjoint for `{'./', '/'}` alike, while
`lib/@cada/mrdivide.m` prints genuine `A/B` (square `B`) into the forward tape —
for same-size operands the elementwise adjoint ran and yielded a silently wrong
gradient (reproduced: wrong value *and* wrong size). The `*` case has exactly
the missing shape guard; `\` correctly errors. *Fixed:* the `{'./','/'}` case
now guards `op=='/' && bsz≠[1 1]` and raises `adigator:revgrad:unsupported`
(matching `\` and the active-exponent `^`), so a genuine matrix division fails
fast at generation time instead of miscomputing — the principle-1-safe interim
behavior per the maintainer decision. `'./'` and scalar `'/'` are elementwise
and keep the correct adjoint. The proper matrix adjoint (`A·inv(B)` family, via
a solve) is deferred to **ROADMAP R30 / [#128](https://github.com/pdlourenco/adigator-embedded/issues/128)**;
the guard names that issue and relaxes to it when it lands. Pinned by
`IRevGradTest` (matrix `/` errors; scalar `/` still matches FD).

**B25 — N-D parameter reference: position-2 base subscript never validated
(fixed).** `lib/@cada/subsref.m` (`NDRefTranslate`): positions ≥3 get
integer/range checks and reject non-numeric subscripts; `base = s.subs{2}` got
none. Empirically, a numeric out-of-range base (e.g. `B(1,5,2)` on a declared
`[3 4 5]`) is caught by adigator's initial native evaluation (`MATLAB:badsubscript`),
so it is not silent — but a **logical** base (`B(1,true,2)`) *is* silently
coerced to numeric and folded to the wrong element, which native evaluation does
**not** catch. *Fixed:* the base is now validated like the positions ≥3 — a
logical (or other non-numeric/non-cada) base raises `adigator:ndparam:slice`,
and an out-of-range numeric/`cada` base raises `adigator:ndparam:subsOutOfRange`
(the latter also covers the `emptyflag` dead-branch path native evaluation skips).
The base may still be a vector (`B(i,1:2,k)`). Pinned by `INDParamTest`
(`ndp_logbase`).

**B26 — `length()` of an N-D declared parameter silently returns the fold
length (fixed).** `lib/@cada/length.m` returned `max(func.size)` over the 2D
*fold* dimensions with no `ndsize` guard, while `size.m:125-130` rejects the
ambiguous case for exactly the declared-shape-vs-fold reason; declared `[3 4 5]`
gave `length(B)` = 20 instead of 5, so `for k = 1:length(B)` silently iterated
the wrong count. *Fixed:* `length` now mirrors the `size` guard and raises
`adigator:ndparam:length`, pointing the user at the fixed declared dimensions as
constants. A bare linear `end` (`B(end)`) resolves through the `end` overload →
`length()`, so it is guarded too (it linear-indexed the fold pre-fix, also a
silent wrong element). Pinned by `INDParamTest` (`ndp_length`, `ndp_end`). The
PR #14 guard landed in `size` but not its sibling.

### 1.3e Silent-wrong-derivative bug found via the #120 loopbound decision (B27)

**B27 — `loopbound` inner runtime-bound loop exit-variable derivative silently
zeroed at `n < Nmax` (high; fixed).** The
runtime-bound-loop exit-variable union (`lib/adigatorForIterEnd.m:477` — the
for-loop analogue of the break/continue exit unions) is applied to **outermost**
loops only, gated by `~ADIGATORFORDATA(ForCount).PARENTLOC` (and `DERNUMBER==1`,
so the Hessian level is uncovered too). An **inner** runtime-bound loop whose
exit variable has an **iteration-dependent derivative sparsity** — a
gather/scatter indexed by the loop counter, read after the loop (e.g.
`for a=1:N; w = x(a)^2; end; y = w`, so `dy/dx` is nonzero only at the
runtime-last column `N`) — is therefore not unioned: the `Nmax` file evaluated at
`n < Nmax` returns the correct **value** but a silently **zeroed derivative**.
The directly-generated (no-loopbound) file is correct at every `n`, so the defect
is specific to the loopbound path. This settles the #120 doc-vs-impl drift (the
`adigatorOptions` doc promised inner-loop exit unions; the impl only delivers
outermost) as **reading 2** — a wrong derivative, not a doc over-claim.
Iteration-*invariant* exit derivatives (`v = x.^2*a`) and padding-benign
accumulators (sums — `ILoopboundTest.nestedRuntimeBoundsWithNDParam`) are
correct, which is why it escaped the existing tests. **Fix (2026-07-10):** the
exit-variable union now extends to inner runtime-bound loops. Removing
`~PARENTLOC` alone did **not** fix it because the inner loop's exit *set* was
never computed — `SAVE.FOR(:,2)` (the "used after the loop" mark) is built for
the outermost span only (`adigatorAssignOvermapScheme.m`), and `LASTOCC` is only
partially populated during the overmap run where `adigatorForIterEnd` runs. So
the exit set is now computed in `adigatorAssignOvermapScheme` (the nested-loop
branch, where `LASTOCC` is final post-empty-eval) and stored per loop as
`INNEREXITCOUNTS`; `adigatorForIterEnd` drops the `~PARENTLOC` gate and unions
those exits — **return-only** (the saved-object overwrite / `SAVE.FOR` slot
numbering stay outermost, so outermost generation is byte-identical). The baked
`y.dx = y.dx(Nmax)` constant gather becomes a proper union accumulation
(`y.dx = zeros(Nmax,1); … y.dx = y.dx + w.dx`), correct at every `n ≤ Nmax`.
Pinned by `ILoopboundTest` — the `nestedRuntimeBoundInnerExitDerivative` tripwire
self-healed into a hard guard swept over 4 truncation points, plus
`innerRuntimeBoundUnderFixedOuter` (runtime-bound inner under a fixed outer, so
the outer union can't mask the inner), `innerExitReadAfterEnclosingLoop` (the
inner exit is also an outermost save target, exercising the saved-object
overwrite), and `tripleNestedRuntimeBoundInnerExit` (depth-3). **Re-differentiating a loopbound
file** was characterized in
[#173](https://github.com/pdlourenco/adigator-embedded/issues/173) and is now
**resolved** ([ADR-0028](decisions/ADR-0028-second-order-loopbound.md)): a Hessian
*of* a loopbound derivative is a first-class output. **PR A** (#176) made the
interim state fail-loud (`adigator:loopbound:rediff` replaced the accidental
`Cannot process statement`) and whitelisted the guard for `slim_embed` (keep-always
in `adigatorParseTape`/`adigatorFieldSlice`, so a loopbound derivative whose slice
genuinely fires — a vector-output Jacobian — now slims through the full engine
instead of fail-safe-bailing). **PR B** made the runtime-header + `assert`
re-emission and the exit-union **derivative-level-agnostic** (dropping the
`DERNUMBER==1` gates in `adigatorForInitialize` outer+inner blocks and
`adigatorForIterEnd` when the loopbound value matches) and drops-and-regenerates
the gradient file's source `assert` in `adigatorPrintTempFiles` (the loop
machinery re-synthesizes it — single source of truth). One subtlety the spike
surfaced: the inner-loop header at `DERNUMBER==2` had been emitting a malformed
`for c=1:(1:N)` from the range object, silently mis-running the inner loop; the
inner-block restructure fixes it, and the B27 `INNEREXITCOUNTS` union then applies
at second order with no further change. So the `Nmax` Hessian at `n<Nmax` matches
the `n`-sized program exactly with a zero padded tail — validated vs analytic,
direct-`n`, CasADi, and FD for single-level, nested inner-exit, triple-nested, and
coupled off-diagonal Hessians. Re-differentiating a loopbound file *without* the
option set still fails loud with `adigator:loopbound:rediff` (the guard cannot be
re-synthesized); reverse mode does not apply (it needs unrolled loops, failing with
`adigator:fwdtape:controlflow`). Pinned by `ILoopboundTest`
(`loopboundHessianMatchesNsizedProgram`, `nestedLoopboundHessianInnerExit`,
`coupledLoopboundHessianOffDiagonal`, `userAssertOfGuardShapeFailsLoud`;
`slimKeepsLoopboundGuard` + `slimEngineSlicesLoopboundJacobian` for the PR A slim
path). Nth derivative (`DERNUMBER>=3`) rides the same level-agnostic gates but is
not yet swept (roadmap R22/#85).
[#162](https://github.com/pdlourenco/adigator-embedded/issues/162), ROADMAP R28.

### 1.3f Numeric literal in a rolled-loop concatenation printed as `.f` (B28)

**B28 — a numeric literal in a `vertcat` inside a rolled-loop print context
emitted as a spurious `.f` (medium; fixed).** A vertical concatenation that
contains a numeric literal, `T = [1; x; x^2]`, emitted while the printer is in a
**rolled-loop context** — an `unroll=0` `for`, or a subfunction printed as a loop
because it is called from ≥2 sites (`FunAsLoopFlag`) — printed the literal as a
bare `.f`: `T.f = [.f; x.f; cada1f1];`. Generation passed but the generated file
failed to run (`Invalid use of operator`). This is the residual tail of the
B17/B22 constant-`.f` family — the constant *struct-field* and *cell-element*
cases are fixed; the adjacent constant *literal* was the remaining leak. It is a
broken-file bug (loud at compile/run), not a silent wrong derivative.

**Root cause.** `@cada/vertcat.m`'s loop-print path (`ForVertcat`, reached at
`RUNFLAG==2` when `FORINFO.FLAG=1`) remapped a `Num2Overloaded` literal — which
carries a valid name (`cadamatprint` → `'1'`) but `id=[]` — through
`cadaPrintReMap`, whose id-less rescue (`if ~varID; funcstr = x.func.name; end`)
**misfired for `[]`** (`~[]` is an empty logical, so the `if` is false). The
literal fell through to `cadafuncname([])`, where `NAMES{[]}` expands to a
zero-element comma-separated list, returning literally `'.f'`. `@cada/horzcat.m`
never had the bug: it skips the remap for numerics via an `else` that `vertcat`
lacked — a latent **upstream** asymmetry (`vertcat.m`, `horzcat.m`,
`cadaPrintReMap.m`, `cadafuncname.m` are byte-identical to upstream). The gate is
the rolled-loop context, **not** whether the concat folds — a fully-folded
constant reproduces identically (fixture `foldedConstRolledLoopVertcat`), which
is why the seven flat (unrolled) mirrors first tried on #168 all failed.

**Fix (three parts).** (1) **Root:** port horzcat's `else` into `vertcat`'s two
loop-print remap sites, so a `Num2Overloaded` numeric keeps its own name and is
not remapped with an empty id. (2) **Rescue:** `@cada/cadaPrintReMap.m` now tests
`isempty(varID) || ~varID` (mirroring the derivative branch's `if varID`), so an
id-less operand keeps its own name instead of asking `cadafuncname` for one. (3)
**Chokepoint (principle 1):** `cadafuncname` now errors
(`adigator:cadafuncname:emptyVarID`) on an empty id rather than silently deriving
`'.f'` from `NAMES{[]}` — a future id-less leak fails loud at generation time
instead of producing a broken file. The chokepoint never fires across the full
`ci_local` suite (288 tests), confirming no legitimate flow relied on the old
behavior. Pinned by `tests/integration/IConcatLoopLiteralTest.m` (F2 minimal
rolled loop, F3 folded constant, and a horzcat control guarding the asymmetry),
each generated through embed `'i'`, run, and matched to finite differences.
B28 is a late sibling of the B17/B22 embedded-field-report family; ROADMAP R26.

### 1.3g `@cadastruct` fallback-naming branch defects found via the V&V surface inventory (B29-B31, B33-B34)

**B29-B31, B33-B34 - undefined variables / a typo on the rarely-taken
`@cadastruct` derivative-naming branch (low; fixed).** Building the
shipped-surface overload inventory (`docs/vv/cada-surface-inventory.md`) for the
coverage-floor work (ADR-0032) surfaced three defects on the
`RUNFLAG==2 && nameloc<=0` fallback-naming branch of the `@cadastruct`
concatenation / transpose overloads - the path taken when a struct-valued
differentiated variable is concatenated/transposed at a print site that has no
user-assigned name and must synthesise one. Fixing them surfaced **two more**
(B33, B34), for five in total. As found, all five **fail loud** (they throw on an
undefined variable); none was a silent wrong derivative. They were 0%-covered
because no test drove that branch - TS-I-27 now does. *(Line numbers below are
pre-fix.)*

- **B29 - `@cadastruct/vertcat.m:18`.** The `else` (nameloc<=0) arm builds the
  fallback name with `sprintf(['cada',NDstr,'s%1.0f'],...NAMELOCS(yid,2))`, but
  **`NDstr` is never assigned** in the function and **`yid` is not in that
  workspace at all** (it is a `parseinput` subfunction local) -> throws.
- **B30 - `@cadastruct/ctranspose.m:18`.** The identical line; this file has no
  subfunctions at all.
- **B31 - `@cadastruct/repmat.m:30`.** `EMTPYFLAG` typo for `EMPTYFLAG` - the
  correct spelling appears three times in the same file, and the misspelling
  occurred exactly once repo-wide. Pre-fix the reference would throw
  *"Reference to non-existent field"* in both the empty-eval and the real case
  (static spelling guard only - no test drives that branch).
- **B33 - `@cadastruct/horzcat.m:38`.** Byte-identical broken line to B29/B30;
  not flagged by the inventory, found by the fix sweep.
- **B34 - `@cadastruct/subsref.m:199`.** The same line in the *main* `subsref`
  body - the most-used overload of the class. Subtler: this file **does** assign
  `NDstr`, but at line 489 inside the `ForSubsRef` **subfunction** - a different
  scope - so the use at 199 is still undefined. (The uses at 569/632 *are* inside
  `ForSubsRef` and were always fine, which is why a per-file "is it assigned?"
  check misses it.) `@cadastruct/subsasgn.m` was checked and is **clean** (its
  assignment at 767 and use at 844 are both inside `ForSubsAsgn`).

**Reachability - proven, not assumed.** The branch is **live user-reachable**: a
struct-array concat whose ctranspose is passed straight to a function,
`y = hlp([s; s]')`, drives it and throws `Unrecognized function or variable
'NDstr'`. (Note the `'` - `.'` would route to `transpose`, which never had the
defect.) That settles fix-vs-guard in favour of **fix**. Precisely, it is the
**`[s; s]` concat** result that is the unnamed intermediate, so the reproducer
drives **`vertcat`**'s arm; the `ctranspose` result becomes the function-call
input `cadainput2_1`, which has a NAMES entry and takes the *named* arm. So B29
is the one **dynamically** pinned (reverting it alone re-breaks TS-I-27 -
verified); B30, B33 and B34 are pinned by the static `NDstr`-scope guard, which
does fail on the pre-fix shape.

**The replacement expression: `DERNUMBER`, not `NVAROFDIFF` (principle 1).** The
class contains *two* naming conventions, and the sibling form is the wrong one to
copy. `transpose`/`reshape`/`repmat` build the name from `ADIGATOR.NVAROFDIFF`;
the deleted `NDstr` stood for `ADIGATOR.DERNUMBER` (that is its definition
wherever it *is* assigned, e.g. `subsref.m:489`), which is also what
`vertcat`/`horzcat` already compute as `numder` for their sibling temp names and
what every other name emitter in the tool uses. The prefix's job is **cross-pass**
disambiguation: a Hessian re-differentiates pass 1's *output file*, in which
pass-1 names are literal variables. `DERNUMBER` changes across those passes
(1 -> 2); **`NVAROFDIFF` does not** (same inputs), so choosing it could emit a
pass-2 name that aliases a live pass-1 variable - a duplicate assignment in the
generated file, where the later write silently wins. That would convert a loud
throw into a **silently wrong derivative**, which is precisely the trade
principle 1 forbids. All five sites therefore use `DERNUMBER`. Note the two
conventions coincide when `NVAROFDIFF == DERNUMBER` (any first derivative of a
single variable), which is why a value check alone cannot discriminate them -
TS-I-27 pins it with a **two-variable-of-differentiation** fixture, where
`nvod == 2` and `DERNUMBER == 1`: it asserts `cada1s...` is present *and*
`cada2s...` is absent, the negative half being what actually discriminates.

**Open follow-up (live hazard, not tidy-up).** `transpose.m`, `reshape.m` and
`repmat.m` still build the name from `NVAROFDIFF`. Leaving the class with two
conventions carries the same aliasing hazard in those three sites *and* creates a
cross-convention one the mixture alone produces (a pass-1 `NVAROFDIFF` name can
equal a pass-2 `DERNUMBER` name when `nvod == 2`). Harmonizing all seven is
deliberately **not** done here: it changes emitted identifiers whenever
`nvod ~= DERNUMBER` (i.e. any Hessian), so it is a change to shipped output that
deserves its own diff, ADR and regeneration pass rather than riding along with a
throw-fixing PR. Grouped with the loopbound `1:N` unbounded-emission defect as
one "generated-code emission hygiene" workstream.

**Disposition - fixed.** Verified to produce a **correct derivative**, not merely
to stop throwing: the reproducer evaluates to `2*sum(x)` with gradient `[2 2 2]`,
matching the analytic value exactly and finite differences to 2.8e-10. Pinned by
`tests/integration/IStructArrayNamingTest.m` (TS-I-27), which drives the
unnamed-intermediate arm end-to-end, asserts the emitted name prefix, and adds a
static guard stating the real invariant - *no `@cadastruct` function scope may
use `NDstr` without assigning it* (comment-stripped, so a comment naming the old
pattern cannot trip it; this guard is what caught B34). Sibling of the B17/B22
embedded-field-report struct-layer family. See §1.5.

### 1.3h Hessian generation crashes on a structurally-zero (linear-objective) Hessian (B32)

**B32 — `adigatorGenHesFile` crashes generating the Hessian of a locally-linear
scalar objective (low; fixed).** The Hessian of a linear objective is
well-defined and zero (`∂²/∂x² (a.'x) = 0`), but generating it threw
`Index in position 2 exceeds array bounds` in `util/adigatorGenHesFile.m` at
`HesLocs1 = dydxlocs(dydxdxlocs(:,1),:)`. Minimal reproducer: `y = x(2)` (also
`y = sum(x)`, `y = a.'*x`). It is a **broken-generation** bug (loud at generation
time), not a silent wrong derivative. Found by the #38 Phase C expression-tree
fuzzer (`mcGenExprTree`) on its first campaign — a locally-linear scalar case is
a natural draw the existing generators (quadratic-only Hessians) never produced.

**Root cause.** For a structurally-zero Hessian the second-derivative object has
no nonzeros, and `adiout2.(…).deriv.nzlocs` is `[]` (0×0), so `dydxdxlocs(:,1)`
indexes a nonexistent second column. Even past that point the value emission
scatters from the runtime `<deriv>dxdx_location` field (`Hes(idx) = y.…dxdx`) —
a field the generated struct does **not** carry when there is no second
derivative, so the *generated* file would then fail at run time with
`Unrecognized field name "…dxdx_location"`.

**Fix (two parts, `util/adigatorGenHesFile.m`).** (1) Normalize the empty
second-derivative locations to the canonical `0×2` shape at the read site, so the
Hessian CSC pattern (`adigatorBuildCSC`, which accepts a structurally empty
`0×2`) builds an empty (zero-`Nnz`) `output.HessianCSC` instead of crashing. (2)
Short-circuit the value emission when `dydxdxnnz == 0`: emit a literal
`Hes = zeros(<returned shape>)` (or the empty `0×1` value stream for
`der_output='csc'`) and skip the scatter entirely, so the generated file never
references the absent `…dxdx_location` field. Shapes mirror the non-zero
branches (n==1 → the output shape; else the `[m*n × n]` fold). Pinned by
`tests/integration/IZeroHessianTest.m`: linear objectives generate + run to an
exact zero Hessian (classic), the file uses the literal-zero short-circuit (no
`dxdx_location` scatter), a mixed quadratic+linear and a `v.'*v` dot still give
the correct non-zero Hessian, `der_output='csc'` returns an empty stream with
`HessianCSC.Nnz == 0`, and both embed modes generate without error. The
generated artifact is also codegen-guarded (`tests/system/SCodegenTest.m`,
license-gated): the inline zero-Hessian compiles + runs to zeros via MEX
(REQ-T-05) and builds under the strict ERT target in both matrix
(`Hes = zeros(n,n)`) and csc (`Hes = zeros(0,1)`, zero-sized) modes (REQ-T-10),
so "generates" is verified to mean "ships". See §1.5.

### 1.3i A `loopbound` derivative is not embeddable — the runtime bound is guarded too late (B35)

**B35 — the runtime-bound guard is emitted at the loop header, leaving every
earlier bound-dependent size unbounded (medium; fixed).** No `loopbound`
derivative could be compiled with static memory allocation, i.e. under the
no-heap regime an embedded target actually runs in. Embedded Coder rejected the
generated file outright:

```
Computed maximum size of the output of function 'colon' is not bounded.
Static memory allocation requires all sizes to be bounded.
The computed size is [1 x :?].
```

It is a **broken-generation** bug in the embedded sense (loud at codegen time,
never a wrong value): interpreted execution and MEX are unaffected, and the
derivative values were always correct — which is why the whole `loopbound`
family (§1.3f/§1.3g, `ILoopboundTest`) was green while the artifact it produced
could not ship.

**Root cause.** `adigatorForInitialize` emits `assert(N <= Nmax)` immediately
before the runtime-bound loop header. But the bound is a **whole-function**
precondition, not a per-loop one: the same parameter sizes expressions that
execute *before* the loop. Two kinds, both present in the reproducer:

- the user's own allocation — `v = zeros(N,1);` ahead of `for a = 1:N`;
- the loop-variable range the machinery materializes for itself,
  `cadaforvar1.f = 1:N;`, which exists only to be indexed at
  `cadaforvar1.f(:,cadaforcount1)`.

Reaching Coder with no upper bound on `N`, each is a variable-size array of
unknown extent. With dynamic memory allocation enabled (the default, and what
`bench/loopboundPaddingPenalty` had been using) they silently became heap
`emxArray`s — so the padded artifact *appeared* to build while quietly requiring
a heap; with it disabled, generation failed at the first such line.

**Fix (`lib/adigatorFunctionInitialize.m`).** Hoist the guard: emit
`assert(<name> <= <max>);` for every declared `loopbound` parameter as the first
statement of the main function body, right after the
`% ADiGator Start Derivative Computations` marker. `adigator.m` already validates
each name to be an input of the main function, so all of them are in scope there.
That bounds every `N`-dependent expression in the file at its analyzed maximum,
and the artifact becomes heap-free. The per-loop guards stay: they are what the
re-differentiation path keys on (§1.3g, `adigatorPrintTempFiles`), and a
redundant `assert` costs nothing in the generated C.

**Measured effect** (`scostfun_lb` gradient, inline `i`/ERT, `Nmax = 64`): padded
ROM 4624 → 4400 B (−224), stack 240 → 352 B (+112 — the range is now
stack-resident rather than heap-allocated; the delta is not a straight transfer,
a `1:64` double range is 512 B, so Coder is also folding/aligning), heap
requirement gone. The `Nmax`-padding penalty is otherwise
unchanged in shape (`bench/SHOWCASE.md`; the R6 evidence line in
`docs/ROADMAP.md` carries the re-measured figures). Pinned by
`tests/integration/ILoopboundTest.m::guardPrecedesEveryBoundDependentSize` (a
license-free text pin that the guard precedes every reference to the bound) and
`tests/system/SRolledErtCodegenTest.m::loopboundGradientErtCodegenStaticMemory`
(the end-to-end proof, Coder-gated, so **local-only** — see `CI_PLAN.md` §3.2).

**Subfunction reach (a real dependency, not a hypothetical).** The hoisted guard
is gated on `FunID == 1`, so it lives in the main function only. A user
*subfunction* that does its own pre-loop `N`-dependent sizing therefore relies on
Coder carrying the caller-established bound across the call — nothing in this
fork emits a second guard there. It does carry: probed directly on R2024a, a
callee's `zeros(N,1)` and `1:N` both build under static memory allocation given a
caller-side `assert(N <= 8)`. Recorded here rather than only in a test comment
because it is a standing assumption about a third-party tool, not about this
code; if a future Coder release stops propagating, the symptom is the B35 failure
one level down — loud at codegen, never a wrong derivative.

### 1.3j A loop range over a runtime-named scalar is unbounded even *without* `loopbound` (B36)

**B36 — a non-`loopbound` file whose loop range names a runtime input emits an
unguarded `1:N` (medium; fixed,
[#210](https://github.com/pdlourenco/adigator-embedded/issues/210)).** Found by
the B35 fix sweep, when the padding
benchmark's *exact-`n`* baseline — generated **without** the `loopbound` option —
turned out to fail the same way under static memory allocation:

```
Computed maximum size of the output of function 'colon' is not bounded.
The computed size is [1 x :?].
```

**Mechanism.** In `scostfun_lb(x,N)` the trip count `N` is an ordinary function
input. Passing a plain numeric `n` to `adigator` fixes the *analysis* trip count
but does **not** make `N` a compile-time constant: it stays a named input of the
generated function, so the loop-variable range still prints as `cadaforvar1.f =
1:N`. Without the `loopbound` option there is no declared maximum, so B35's
hoisted guard does not fire and nothing bounds it.

**Why this is the wider defect — measured, and principle-1 in one direction.**
The emitted range and the emitted loop header **disagree**: the header is a
literal (`for cadaforcount1 = 1:5`, the analyzed count) while the range is
`cadaforvar1.f = 1:N` (runtime). Generating `lb_fun` at `n = 5` and calling the
result at other `N`:

| call | result |
|---|---|
| `N = 5` (the analyzed value) | `J.f = 70` — correct |
| `N = 3` (below) | `Index in position 2 exceeds array bounds` — **loud** |
| `N = 8` (above) | `J.f = 70`, `numel(v.f) = 8` — **runs silently**; the true 8-term value is 240 |

The `N > n` direction is the serious one: the file computes the *analyzed*
problem while the caller asked for a bigger one, returns an output vector of the
requested length with the tail never written, and reports nothing. That is a
wrong derivative delivered quietly — `REVIEW_CONTEXT.md` principle 1 — not the
loud failure B35 was.

The generated file's index tables are sized for the analyzed `n`, so calling it
with any other `N` is outside its envelope, and unlike a `loopbound` file
**nothing says so**. B35 gives the `loopbound` case a guard; this case has
neither a guard nor a fold.

**Fix — state the specialization.** The generated file now opens with
`assert(N == n);`, one per main-function input that a loop range names, at the
same position and for the same reason as B35's `assert(N <= Nmax)`: the
parameter also sizes user expressions ahead of the first loop. An **equality**,
not an inequality — the file was specialized to a single trip count, not padded
to a maximum, and the two claims are opposites. Four pieces:

- `adigatorPrintTempFiles` harvests every identifier in a main-function loop
  range as the temp files are printed. It deliberately over-collects; the useful
  filter is downstream.
- `adigator.m` keeps only candidates that are main-function inputs bound to a
  plain **integer** scalar and are not already declared `loopbound` (whose padded
  `<=` semantics are the deliberate opposite), yielding `OPTIONS.TRIPCOUNTGUARD`.
- `adigatorFunctionInitialize` emits them in the body prologue beside B35's.
- `util/adigatorLoopboundGuard` gains the equality shape (`eqTemplate`/`eqMatch`)
  and a loose `anyMatch`; `adigatorPrintTempFiles`'s re-differentiation
  classifier and `adigatorParseTape`'s slim keep-always whitelist both switch to
  it. **This half is the load-bearing one.** A generated file carrying
  `assert(N == n);` is the *source* of the next derivative pass, and the
  classifier only recognized `<=` — an unrecognized `assert(...)` falls past that
  branch into the generic `Cannot process statement:` error, so without this
  every Hessian of a named-trip-count function would have stopped generating.
  (Loud, but with the least actionable message in the file.)

**Order matters at 2nd order and beyond.** At level 1 the parameter name comes
from the loop range. From level 2 the source file's loop header is already a
literal, so nothing can re-derive it; the name survives only because the previous
level's guard is recognized, dropped, and re-recorded for re-emission. Verified
to **3rd order** on `sum(x_k^3)`: exactly one guard per level, and
`f`/`dx`/`dxdx`/`dxdxdx` = `100`/`3k²`/`6k`/`6` analytically exact.

**Consequences.**

- The `N > n` silent-wrong call now errors. This is a **user-visible break** in
  the correct direction: code that relied on the old silence gets an assertion
  failure instead of a wrong derivative.
- The exact-`n` artifact builds under static memory allocation, so
  `bench/loopboundPaddingPenalty` finally runs with
  `EnableDynamicMemoryAllocation = false` — ADR-0034 decision 2 is now enforced
  where it was written rather than deferred.
- **The padding-penalty numbers moved a lot.** With `N` pinned to a constant the
  exact-`n` files become fully fixed-size and shed the `emxArray` machinery they
  had been carrying (ROM 640→400 at n=4, 560→240 at n=8; stack 160→80), while the
  padded file keeps a genuinely runtime `N`. The measured penalty roughly
  **doubled** at small `n` (11.0×/18.3×/3.6× at n=4/8/32, was 6.9×/7.9×/2.9×) —
  every earlier figure was taken with the heap on. See `bench/SHOWCASE.md` and
  the R6/R17 rows in `docs/ROADMAP.md`; this strengthens the case for #6 Tier 2.

Pinned by `tests/integration/ISpecializedTripCountTest.m` and the shape lockstep
in `tests/unit/ULoopboundGuardTest.m`.

**Re-differentiating at a *different* trip count** cannot be made to work — the
source file's headers and tables serve the value it was generated at — and is
rejected before generation by `util/adigatorCheckTripCountRediff`. Note this is
a **diagnosis**, not a new safety property: the emitted guard is self-protecting,
because it executes during adigator's own initial test evaluation of the source
and throws there anyway. The check exists so the user sees *why* instead of a
bare `Assertion failed`, matching the actionable-rediff pattern of #173 PR A.

**Residual scope — the remaining shapes are still specialized and still
unguarded.** "Fixed" above means the direct form (a main-function input named in
a main-function loop range), not every route to a specialized trip count:

1. **Pass-through into a subfunction** — `main(x,N)` calling `sub(x,N)` whose
   loop is `for k = 1:N`. The harvest is gated to the main function so a
   subfunction's parameter cannot shadow a same-named main input with a
   different value and forge a false guard; the cost is that a genuine
   pass-through is missed. This is the most likely real-world shape of the three.
   **Fixed (issue #213 route 1)** by *interprocedural resolution* rather than by
   loosening that gate — see §1.3l below.
2. **A bound reached through a struct field** — `for k = 1:p.N` with `p` a struct
   input. `p` is not numeric and `N` is not a top-level input name, so neither
   qualifies.
3. **A non-integer scalar input in the range** — `for k = 1:round(1/h)`. Excluded
   deliberately: a floating-point equality assert is not a shape worth emitting.

The remaining two keep the original silent-wrong behaviour above the analyzed count. The
guard's *absence* is the tell, so they are detectable, but they are not fixed.

### 1.3k The rolled printing run composes loop overmaps as if independent (B37)

**B37 — a rolled second-derivative pattern is computed as the cross product of
two loop overmaps, so an interior temporary is O(n²) where the exported pattern
is O(n) (high, embeddability; fixed,
[#217](https://github.com/pdlourenco/adigator-embedded/issues/217),
[ADR-0036](../decisions/ADR-0036-overmap-directed-pruning-rolled-printing-run.md)).**
Found by the ADR-0035 embeddability gate on first contact: the rolled Hessian of
`sum_k exp(x_k) + 2x_k` carried **37,552 B of stack at n=64 — 63.4×** the
hand-written `diag(exp(x))` — while ERT-code-generating cleanly and passing
`SRolledErtCodegenTest`. This is the "hollow milestone" (ADR-0019/ADR-0033) with
numbers attached: exit-success is necessary, not sufficient.

**Mechanism.** A rolled `for` is walked twice, and the passes do not see the same
thing. The **overmap run** walks the body once per iteration with the *exact*
per-iteration derivative patterns and unions them (`cadaOverMap` →
`cadaUnionVars`, which unions exact locations). The **printing run** walks the
body *once* — one printed body must serve every iteration — so every loop-body
operand carries its overmap instead. The printing run therefore composes two
unions **as if they were independent**, losing the correlation between them.

For `exp(x(k))` the second-derivative pattern is `{(k,k)}` in iteration `k`, so
the union is the n-nonzero **diagonal**, and that is what the tool exports
(`SCscMetadataTest`/TS-S-08 pins `Nnz = 8` at n=8). But with both factors of the
product rule n-wide in the printing run, `times` produced the full n×n cross
product. Instrumenting both runs shows it directly — per-iteration nonzeros
`1,1,…,1` unioning to `8`, then a single event at n=8:

```
SHRINK  scostfun_ADiGatorHes  der=cada1f2dxdx  nzx=64  nzover=8  nzd=8
```

`cadaPrintReMap` squeezed the 64 straight back to 8 — *one statement later*,
after the generated code had already gathered n² doubles onto the stack:

```matlab
cada2tempdx = cada2f1dx(Gator2Data.Index1);      % n^2 doubles, inside the loop
cada1f2dxdx = cada2tf1(:).*cada2tempdx;          % n^2
cada1f2dxdx = cada1f2dxdx(Gator2Data.Index3,1);  % ... and back down to n
```

**Two dead ends worth recording**, because both look like refutations and are
not. `der_output='csc'` changes the stack by −2.7% and leaves the exponent
alone: fitting `a·n²+b·n+c` shows the quadratic and constant terms are identical
across output modes and only the linear term moves, so the object is *interior*,
upstream of output assembly. And ROM is *modest* (640 B at n=8), which argues
against an inflated index table until you notice the tables are **down-cast to
`int8`** (ADR-0001): n² entries cost 64 B in ROM and 512 B on the stack the
moment they are gathered into a `double` temp.

**Fix.** Hand the emitting operation the overmap its result is about to be
remapped into (`lib/@cada/private/cadaOverMapTargetNz.m`) and let it drop the
doomed locations before printing them — the *same* truncation `cadaPrintReMap`
performs a statement later, which is why the helper returns `[]`, and the caller
prunes nothing, unless that remap is actually going to happen. Applied in
`cadaRepDers` (scalar-derivative expansion, where `nnz(scalar) × numel(array)`
is what turns quadratic) via the two call sites in `cadabinaryarraymath`.

Scope was set by measurement. Instrumenting every `cadaPrintReMap`
over-approximation across the whole corpus found **18 events**: 17 with this
defect's signature (`nzx = n²`, `nzover = n`), all on the scalar-expansion path,
across six fixtures and reaching **third order** (`cada1f2dxdxdx`) — so the fix
is not Hessian-specific, and the largest is `nzx = 4096` against `nzover = 64`,
which is the 37.5 KB in one line of log; and one that is different in kind, a *first-order*
Jacobian's growing concatenation (`ForHorzcat`, `V.dx` at 700 → 600 in the
`polydatafit` example), a bounded ~17% over-approximation with no growth-law
character, left alone deliberately. *(Amended 2026-08-01: that shape has since
been removed from the corpus — `polydatafit`'s growing concatenation was
rewritten to pre-size its matrix after the example audit found the user function
does not ERT-codegen — so the count above is historical and #222 is closed as
moot.)* `cadaRepDers`'s third caller (`subsasgn`) and
the `IF` overmap are likewise out of scope — see ADR-0036.

**Result.** Generated stack 768/9616/37552 → **160/352/608** B at n = 8/32/64
against 144/336/592 hand-written: 5.33×/28.62×/63.43× → **1.11×/1.05×/1.03×**.
The series becomes exactly `96 + 8n` — affine, and byte-for-byte the same series
ADR-0035 measured for the *vectorized* Hessian of the same maths. So the
subscripted formulation now costs what the vectorized one costs, which also
answers ADR-0035's open caveat that part of the gap might be intrinsic to the
rolled path: none of it was.

Pinned by `tests/integration/IRolledOvermapWidthTest.m` (license-free — the n²
gather went *through* an n² static index table, so `Gator2Data`'s width tracks
the defect exactly, and a genuinely dense rolled Hessian is checked to be left
alone) and `SStackScalingTest::subscriptedHessianMatchesVectorizedTwin`
(Coder-gated, local-only), which was the self-healing `KnownIssue` pin and is now
an ordinary parity assertion.

### 1.3l A trip count passed through into a subfunction is unguarded (B38)

**B38 — a loop bound handed to a subfunction specializes the file without
saying so (medium-high; principle-1 residue of B36; fixed,
[#213](https://github.com/pdlourenco/adigator-embedded/issues/213) route 1).**
B36 (§1.3j) closed the *direct* form — a main-function input named in a
main-function loop range. This is the same silent-wrong failure one call deep:

```matlab
function y = main(x,N),  y = sub(x,N); end
function y = sub(x,N),   y = 0; for k = 1:N, y = y + x(k)^2; end, end
```

`N` **is** a main input, so it is guardable in principle. It was missed because
the harvest is gated to the main function (`ADIGATOR.TRIPCOUNTSCAN`), and that
gate is load-bearing: without it a subfunction parameter that *shadows* a
same-named main input with a different value would forge `assert(N == 3)` into a
function whose own `N` is 5, rejecting every correct call. Pinned by
`ISpecializedTripCountTest::subfunctionLoopDoesNotForgeAGuard`. So the fix could
not be a looser gate — that reintroduces the forge.

**Mechanism — resolve, don't loosen.** A subfunction's loop range naming one of
its *own parameters* records `(FunID, parameter position)` instead of being
discarded. Every call site records its literal argument text per position. After
all functions are printed, a parameter earns a guard only if **every** recorded
call site passes the *same bare identifier*, which the existing filter then
requires to be a main input bound to a plain integer scalar. The guard emitted
is the ordinary main-scope `assert(N == n);` #211 already ships, so every
recognizer, the slim whitelist, `adigatorCheckTripCountRediff` and the
re-differentiation machinery are untouched.

Resolution follows the **argument**, so the callee's spelling never leaks into
main's scope: `main(x,M)` calling a subfunction whose parameter is spelled `N`
guards **`M`**. But an argument's text is only a name in the **caller's** scope,
so it is matched against main's inputs *only when the caller is the main
function*. Resolving a site inside another subfunction would be name equality —
the shadowing forge one hop deeper, and it forges on **correct** code:

```matlab
function y = main(x,N),   a = scale(x,N); b = energy(x); y = a+b; end
function y = scale(x,N),  y = sum(x)*N; end
function y = energy(x),   N = numel(x); y = accum(x,N); end   % a LOCAL N
function y = accum(x,N),  y = 0; for k = 1:N, y = y+x(k)^2; end, end
```

main's `N` is an unrelated multiplier and the file is valid for every `N`, so
any guard on it rejects correct calls. Transitive resolution through an
intermediate subfunction is the strictly-more-capable version and is
deliberately **not** attempted: declining costs a missed guard, guessing costs a
false assertion. Pinned by `twoHopCallSiteDoesNotForgeAGuard`.

**Fail-closed on everything else**, each pinned: a non-bare argument
(`sub(x,N-1)` — the callee loops `N-1` times, so `assert(N == n)` would state
the wrong specialization), a local (`sub(x,N2)`), a callee never called, and —
the case the implementation lookup forced — **two call sites that disagree**.
ADiGator prints one body per *function*, not per call site, so a callee reached
with two different inputs has no single value to assert; guarding either would
reject correct calls through the other. For the same reason call-site arguments
are recorded at **every** call site, not just the main function's: recording
only main's would let a callee also reached from another subfunction look
consistently-called and forge a guard the other caller never satisfies. Each
record carries its **caller's id** as well as the argument text — the site
list gives agreement, the caller id gives scope, and both are needed.

**Boundary, and it is not this defect's.** Chaining `adigator()` by hand over a
generated file that *calls a subfunction* fails (`MATLAB:structRefFromNonStruct`)
— with no trip count, no bound parameter and nothing this feature touches. So
the third-order pin the direct form carries cannot be written for this shape.
The supported path is unaffected: `adigatorGenHesFile` reaches second order by
its own route, and there the guard survives at exactly one per level with
`sum(x³) → 3x² → diag(6x)` analytic-exact and the oversized call still erroring.
The limitation itself is pinned by
`reDifferentiatingASubfunctionCallingFileIsUnsupported`, so if a future change
fixes it the test goes red and the third-order pin can be restored.

**Residual, shared with B36's direct form:** the guard states the value of the
main input *at entry*. A user who reassigns that input before the call (or
before the loop, in the direct form) would get a guard comparing against the
entry value while the loop runs on the reassigned one. Not introduced here, and
not addressed here.

Pinned by `tests/integration/ISpecializedTripCountTest.m` (§1.3l; issue #213).

### 1.4 Genuine fixes in this fork (verified, for the record)

- `cadaunarymath.m` derivative-rule corrections (`asec`, `acsc`, `asecd`,
  `acscd`, `acosh`, `asech`, and the `sind/cosd/...` family): the new forms
  are branch-correct for negative arguments (e.g.
  `d/dx asec(x) = 1/(x²√(1-1/x²)) = 1/(|x|√(x²-1))`) and the degree-mode
  factor is now correctly `π/180` *with degree-mode trig on the RHS* instead
  of `180/π` with radian trig — both upstream errors. Covered by
  `tests/legacy/test_unarymath_rules.m` (finite-difference check).
- `adigatorGenJacFile` vector-function-of-scalar allocation fixed from
  `zeros(dydxsize(2),1)` (= `zeros(1,1)`) to `zeros(dydxsize(1),1)`.
- `any(ysize) == 1` → `any(ysize == 1)` (two occurrences) in
  `adigatorGenHesFile` — upstream always took the vector branch even for
  matrix-valued operands.

### 1.5 Fix disposition log

| Item | Status |
|------|--------|
| B1 (`Data*` down-cast) | **Fixed** — down-cast restricted to `Index*`; pruner extracted to `embedding/prune_adigator_mat.m`; pinned by `tests/unit/UPruneMatTest.m`. The fix landed together with integer/logical class preservation in `structure_to_embed_mfile.m` (salvaged from PR #1) — the two are coupled: preserving integer classes in the inline emitter without restricting the down-cast would have *extended* the corruption to inline mode. |
| B2 (format string) | **Fixed** — pinned by `tests/unit/UEmbedMfileTest.m`. |
| B5 (`structout` undefined) | **Fixed** in the extracted pruner. |
| B15 (`OuterLoopMaxLenght` crash) | **Fixed** (see §1.3a). |
| B16 (transformation state leaks on the error path) | **Fixed** (see §1.3b, ADR-0011) — `adigator.m` now clears the `ADIGATOR*` globals via a non-declaring helper subfunction (`adigatorClearTransformGlobals`) on both the normal path and in a `catch` that rethrows (a literal clear from `adigator`'s own declaring frame proved unreliable on the success path), with the runtime-data `eval`-global load isolated in `adigatorLoadRuntimeData` as defense-in-depth, and releases the adigator-owned handles + path/temp dir via a by-value `onCleanup`, on every exit. Surfaced by the issue-#38 `oracleHygiene` prototype; the success-path global leak was caught by the gated `UCoreErrorHygieneTest`. Pinned by `UCoreErrorHygieneTest` (gated) + the `mcGenNegative`/`oracleHygiene` pair and `MCSmokeTest.successLeavesNoOpenHandles` (extended) (REQ-T-07). |
| B7 (vector-output Hessian row multiplier) | **Fixed** — `(xind1-1)*m + yind` in `adigatorGenHesFile`, consistent with the documented `[m*n × n]` layout and `output.HessianStructure`. Covered by `hesVectorOutput*` in `tests/integration/IShapeMatrixTest.m`. |
| B13 (`Gfid` never closed) | **Fixed** — both wrapper fids closed in `adigatorGenHesFile`. |
| B8 (matrix-of-scalar Hessian branch) | **Fixed** — branch on `any(ysize == 1)`, subscripts converted to linear indices, unreachable sparse branch removed. The `hesMatrixOfScalar` case in `IShapeMatrixTest` auto-flipped to a regression guard. |
| B9 (sparse-branch gradient transpose) | **Fixed** — transpose removed; sparse and full branches now both emit the m×n Jacobian convention, consistent with `adigatorGenJacFile`. Guarded by `grdSparseBranchOfVectorOutput`. |
| B10 (`JacobianStructure` vs remapped shapes) | **Fixed** — the remap is recorded and the unrolled `nzlocs` are decomposed with `ind2sub` into the displayed shape. Guarded by `jacScalarOfMatrix` / `jacMatrixOfScalar`. |
| Pruner near-integer tolerance | **Fixed** — exact `isequal(A,round(A))` check (salvaged from PR #1). |
| `coder.load` path override | Optional `mat_filepath` argument added to `adigator_patch_derivative` (salvaged from PR #1, but defaulting to the file *name* so generated code stays relocatable). |
| Test hygiene | `adigator.m` now clears its transformation-state globals on exit; `updatestruct` warns on lossy type coercion (salvaged from PR #1). |
| B3 (patcher multi-match deletion) | **Fixed** — matched guard lines deleted in one operation; pinned by `tests/unit/UPatchTest.m` (synthetic file with two loader guards and sentinel lines). |
| B4 (patcher header matching) | **Fixed** — function headers located by an anchored regexp on the definition line; a lookalike subfunction whose name contains the target as a substring is exercised in `UPatchTest`. |
| B6 (pruned `.mat` re-differentiation) | **Mitigated** — explicit notice printed when pruning strips the higher-order metadata. |
| B11 (`embed_mode` comparisons) | **Fixed** — `adigatorNormalizeEmbedMode` validates and normalizes (`classic`/`coderload`/`inline`, any case) at option-parse time in `adigatorOptions` and all three generators; pinned by `tests/unit/UOptionsTest.m`. |
| B12 (option-field case folding) | **Fixed** — parsers read the user's struct with the field name as given and lower-case only the destination; end-to-end upper-case-spelling case in `UOptionsTest`. |
| B14 (gradient/Hessian `_Grd` collision) | **Won't fix (documented as benign)** — `adigatorGenJacFile(...,'Grd')` and `adigatorGenHesFile` generate *equivalent* `myfun_Grd`/`myfun_ADiGatorGrd` files (same first derivative, same column-gradient convention), so the overwrite cannot change results. Noted in `adigatorGenDerFile_embedded` help. |
| §2.1 item 1 (precomputed linear indices) | **Implemented for the wrappers** — in embed modes (`l`/`i`) the Jacobian/gradient/Hessian wrappers emit literal generation-time scatter-index vectors instead of runtime `_location` arithmetic (classic mode unchanged). This is the corrected re-implementation of closed PR #1's "Level 1": the index derivation matches `output.HessianStructure`/the conventions exactly, and the `sparse*LiteralScatter` cases in `IEmbedModesTest` verify cross-mode numeric equality. |
| §2.1 items 3–4 (index dedup, range compression) | **Implemented in the inline emitter** — `structure_to_embed_mfile` deduplicates identical sibling arrays (one copy, aliasing the rest) instead of repeating literals, and emits integer-valued arithmetic progressions as `a:s:b` (constants as `repmat`), with class casts preserved (single-precision class preservation fixed along the way). **ERT-safety (#80):** the shared copy is bound to a **local temp** and the aliases reference that temp (`c_S_…_IndexN`), never the sibling struct field — `S.x.B = S.x.A` reads the struct then adds field B, which strict Embedded Coder rejects (it surfaced as the rolled-Hessian `Index5` failure at n≥32); the temp keeps the single-copy benefit with no read-then-add. Pinned by `dedupAliasesRepeatedSiblings`/`rangeCompression` in `UEmbedMfileTest` (the former asserts the ERT-safe-temp form + no struct-field self-alias). |
| §2.1 item 2 (`uint16` narrowing) | **Rejected** — `uint16` saturates at 65535, which index *arithmetic* in generated code can plausibly reach for moderate problem sizes (a 300-variable Jacobian already has unrolled indices near 10⁵), turning overflow into silent saturation. `uint32` (range ~4·10⁹) is kept as the narrowing floor. |
| CI plan Phase 4 (ratchets) | **Implemented** — `ci_lint` gains a findings-count ratchet against `tests/lint_baseline.txt`, and a new `ci_coverage` step reports the aggregate line rate of `lib`/`util`/`embedding` (Cobertura artifact) and gates against `tests/coverage_baseline.txt`. Both baselines self-bootstrap: absent file → report-only; the first CI run supplies the numbers to commit. |
| PR #1 architectural commits (direct emission + literal linidx) | Discarded — right direction (§2.1) but defective: `compute_wrapper_linidx` called with swapped size arguments at both call sites, second differentiation cannot parse `persistent`/`coder.*` statements, inline mode references a nonexistent struct level, and classic mode was left inconsistent with embed modes. To be reimplemented once TS-I-01 exists. |
| B17 (constant-struct field `.f`) | **Fixed** (Option 1) — `structParse` (`lib/adigatorVarAnalyzer.m`) marks numeric (constant) struct fields derivative-free (`NAMELOCS(:,3)=Inf`), so `cadafuncname` prints a bare `struct.field`; derivative-carrying (`cada`) fields are untouched (R8 unaffected). Pinned by `tests/integration/IConstStructFieldTest.m` (classic + inline + load provenance, vs analytic). ROADMAP R26. |
| B18 (constant/aux-param conditional) | **Fixed (no longer reproduces)** — generates + matches FD both branches (likely R8). Pinned by `tests/integration/ICondAuxParamTest.m` (an `if` on aux struct-param fields with a subfunction branch, both parameter selections vs analytic + FD). |
| B19 (while-counter index) | **Partially resolved** (both shapes principle-1-safe — they error, never miscompute). Plain `while`-counter → the B20 symbolic-index limitation, now raising the actionable error pointing to the `for`-loop fix. `if`-guarded `while`-counter (the reported shape) → an internal index over-approximation that still surfaces a raw `MATLAB:badsubscript` — a **residual rough edge** tracked on [#108](https://github.com/pdlourenco/adigator-embedded/issues/108) (not a simple guard; zero-derivative functions share the empty-`nzlocs` site). Pinned by `tests/integration/ISymbolicIndexTest.m` (incl. the `if`-guarded shape *errors*). ROADMAP R26. |
| B20 (data-dependent indexing) | **Resolved as a documented limitation** ([ADR-0024](../decisions/ADR-0024-data-dependent-index-actionable-error.md)) — data-dependent indexing stays unsupported, but the error is now actionable (`cadaErrorSymbolicIndex`, id `adigator:symbolicIndex`, points to the logical-weight-sum idiom). Pinned by `tests/integration/ISymbolicIndexTest.m`. ROADMAP R26. |
| B21 (user `load` verbatim in inline file) | **Reclassified: warn-and-allow** ([ADR-0023](../decisions/ADR-0023-embed-source-scan-gate.md) rev 2026-07-04) — embed is no more restrictive than classic, so `'l'`/`'i'` emit a user `load`/`global` verbatim (as classic) and only **warn** (`adigator:embed:unsupportedConstruct`) that the file is not self-contained; the user may use it provisionally, or pre-load and pass as an aux input to make it embeddable. Constructs classic itself rejects (bare `load(...)`) still error from the core. Capture-as-`Data*` is a future enhancement. Pinned by `tests/integration/IEmbedUnsupportedTest.m` (warn + generate + embed-vs-classic equality). ROADMAP R29. |
| B22 (constant-cell element `.f`) | **Fixed** — **classic:** the `structParse` `structflag=1` arm marks constant cell / nested-in-cell elements derivative-free (struct *arrays* take the lifting path, already correct); pinned by `IConstCellFieldTest`. **Embed (`l`/`i`):** the constant cell is emitted verbatim and generates, with a source-scan **warning** that a cell may still be rejected by MATLAB Coder ([ADR-0023](../decisions/ADR-0023-embed-source-scan-gate.md) rev 2026-07-04); pinned by `IEmbedUnsupportedTest`. ROADMAP R26/R29. |
| B23 (Hessian `*Structure`/`*Locs` corruption, matrix-of-scalar) | **Fixed** — `util/adigatorGenHesFile.m` snapshots the true output shape (`HesOutSize`) before the remapcase block mutates `ysize`, and the Hessian-metadata block allocates the pattern with it (#126, §1.3d). Pinned by `IOutputModesTest/hessianNonzerosMatrixOfScalar`; the general exported-structure assertions landed in `IShapeMatrixTest` (#160) ([#117](https://github.com/pdlourenco/adigator-embedded/issues/117), [#119](https://github.com/pdlourenco/adigator-embedded/issues/119)). ROADMAP R28. |
| B24 (reverse-mode `/` elementwise adjoint) | **Fixed (unsupported-error guard)** — `case {'./','/'}` now guards `op=='/' && bsz≠[1 1]` → `adigator:revgrad:unsupported` (matching `\`), so a genuine matrix division fails fast instead of silently miscomputing (§1.3d); `'./'`/scalar `'/'` keep the elementwise adjoint. Pinned in `IRevGradTest` (matrix `/` errors; scalar `/` matches FD) ([#117](https://github.com/pdlourenco/adigator-embedded/issues/117)). The proper matrix adjoint is deferred to ROADMAP R30 / [#128](https://github.com/pdlourenco/adigator-embedded/issues/128). ROADMAP R28. |
| B25 (N-D base subscript unvalidated) | **Fixed** — `lib/@cada/subsref.m` `NDRefTranslate` now validates the position-2 base like positions ≥3: a logical/non-numeric base → `adigator:ndparam:slice` (the genuine silent-wrong case native evaluation misses), an out-of-range numeric/`cada` base → `adigator:ndparam:subsOutOfRange` (covers `emptyflag`); numeric literal OOB was already caught by native eval (§1.3d). Pinned in `INDParamTest` (`ndp_logbase`) ([#117](https://github.com/pdlourenco/adigator-embedded/issues/117)). ROADMAP R28. |
| B26 (`length()` returns the ndsize fold length) | **Fixed** — `lib/@cada/length.m` now mirrors the `size.m` `ndsize` guard → `adigator:ndparam:length` (was silently returning the 2D-fold length, §1.3d). Pinned in `INDParamTest` (`ndp_length`) ([#117](https://github.com/pdlourenco/adigator-embedded/issues/117)). ROADMAP R28. |
| B27 (loopbound inner-loop exit derivative zeroed) | **Fixed** — the exit-variable union now extends to INNER runtime-bound loops. `lib/adigatorAssignOvermapScheme.m` records each inner loop's exit set (`INNEREXITCOUNTS` — assignments whose last use is after the loop, computed there because `LASTOCC` is final post-empty-eval but only partial in the overmap run), and `lib/adigatorForIterEnd.m` drops the `~PARENTLOC` gate and unions those exits (return-only; the outermost-only saved-object overwrite and `SAVE.FOR` slot numbering are untouched, so outermost generation stays byte-identical). Was: an inner runtime-bound loop's counter-indexed exit derivative was baked to a constant `y.dx = y.dx(Nmax)` gather reading a structurally-zero slot at `n<Nmax`, silently zeroing the gradient (§1.3e). Closes #120 as reading 2. Pinned by `ILoopboundTest` — `nestedRuntimeBoundInnerExitDerivative` (self-healed from the `KnownIssue` tripwire, swept over 4 truncation points) plus three hardening variants: `innerRuntimeBoundUnderFixedOuter`, `innerExitReadAfterEnclosingLoop` (the exit-also-outermost-save-target path), and `tripleNestedRuntimeBoundInnerExit` (depth-3). **Second order:** re-differentiating a loopbound file is now supported ([#173](https://github.com/pdlourenco/adigator-embedded/issues/173), [ADR-0028](../decisions/ADR-0028-second-order-loopbound.md)) — PR A (#176) made it fail-loud + slim-whitelisted the guard; PR B made the runtime-header/assert re-emission + exit-union derivative-level-agnostic, so a loopbound Hessian at n<Nmax matches the n-sized program (§1.3e). [#162](https://github.com/pdlourenco/adigator-embedded/issues/162). ROADMAP R28. |
| B28 (numeric literal in a rolled-loop concat printed `.f`) | **Fixed** — `@cada/vertcat.m`'s loop-print (`ForVertcat`) remapped a `Num2Overloaded` literal (valid name, `id=[]`) through `cadaPrintReMap`, whose `~varID` rescue misfired for `[]` (`~[]` is an empty logical), so `cadafuncname([])` returned the spurious `'.f'` (`NAMES{[]}` is a zero-element CSL); `@cada/horzcat.m`'s `else` (skip the remap for numerics) is why row-concats never surfaced it — a latent upstream asymmetry (§1.3f). Fixed by porting the `else` into vertcat's two loop-print sites, repairing the `cadaPrintReMap` rescue (`isempty(varID) || ~varID`), and a `cadafuncname` chokepoint (`adigator:cadafuncname:emptyVarID`) that fails loud on an empty id (never fires across the 288-test `ci_local`). Pinned by `tests/integration/IConcatLoopLiteralTest.m` (F2 minimal loop + F3 folded constant + horzcat control, generated through embed `'i'`, run, FD-matched) ([#168](https://github.com/pdlourenco/adigator-embedded/issues/168)). A late sibling of the B17/B22 embedded-field-report family; ROADMAP R26. |
| §1.3 math-doc conventions (D1) | **Fixed** — `adigatorDerivativeConventions.m` (the binding conventions file, CLAUDE.md §3) contradicted contract C-1: Hessian section `f: Rn -> Rm` (→ `R`), the Jacobian/Hessian size captions mislabeled `size(Gradient(f)) = [length(x) length(f)]` (Jacobian read n×m, contradicting C-1's m×n), and the `dfn`/`dfm` row typo. Corrected to match C-1, plus the same defects copied into `adigatorGenJacFile`/`adigatorGenHesFile` — text-only, no behavioural change. The §1.3 "summary block inconsistent" claim was **retracted** (it is a valid generalization of the table). ([#118](https://github.com/pdlourenco/adigator-embedded/issues/118)) ROADMAP R28. |
| B29-B31, B33-B34 (`@cadastruct` fallback-naming branch: undefined `NDstr`/`yid`, misspelled empty-eval flag) | **Fixed** - five sites in the `RUNFLAG==2 && nameloc<=0` fallback-name arm (`vertcat`/B29, `ctranspose`/B30, `repmat`/B31, `horzcat`/B33, `subsref`/B34 - the last two found by the fix sweep, not the inventory) used `NDstr` in a scope that never assigns it; for `subsref` the file's only assignment is inside the `ForSubsRef` **subfunction**, which is why a per-file check misses it. The arm is **user-reachable** (`hlp([s; s]')` throws pre-fix), so it is fixed, not guarded. That fixture drives **`vertcat`**'s arm - the `[s; s]` concat result is the unnamed intermediate, while the `ctranspose` result is a function-call input that gets a NAMES entry and takes the *named* arm - so B29 is the one pinned dynamically; B30/B33/B34 are pinned by the static scope guard. Rebuilt with **`DERNUMBER`** - what the deleted `NDstr` stood for - and deliberately **not** the `NVAROFDIFF` used by the `transpose`/`reshape`/`repmat` siblings: `NVAROFDIFF` is invariant across the two Hessian passes, so it could alias a live pass-1 variable and silently win the assignment, converting a loud throw into a wrong derivative (principle 1). Verified correct, not merely non-throwing (`2*sum(x)` -> `[2 2 2]`, analytic-exact, FD 2.8e-10). `subsasgn.m` checked and clean. Harmonizing the three remaining `NVAROFDIFF` siblings is an **open follow-up** (changes shipped emitted identifiers; own ADR). Pinned by `tests/integration/IStructArrayNamingTest.m` / TS-I-27 (§1.3g). |
| B32 (Hessian generation crashes on a zero/linear-objective Hessian) | **Fixed** — `util/adigatorGenHesFile.m` crashed at `HesLocs1 = dydxlocs(dydxdxlocs(:,1),:)` when the second-derivative `nzlocs` was `[]` (a structurally-zero Hessian, e.g. `y = x(k)`), and the value emission then scattered from an absent runtime `…dxdx_location` field. Fixed by normalizing the empty locs to `0×2` (so the empty CSC pattern builds) and short-circuiting the value emission to a literal `Hes = zeros(shape)` (empty `0×1` for `der_output='csc'`), skipping the scatter. Found by the #38 Phase C `mcGenExprTree` fuzzer; pinned by `tests/integration/IZeroHessianTest.m` (§1.3h). |
| B35 (a `loopbound` derivative is not embeddable — runtime bound guarded too late) | **Fixed** — `adigatorForInitialize` emitted `assert(N <= Nmax)` at the loop header only, so every bound-dependent size *ahead* of the loop (the user's `zeros(N,1)`; the `cadaforvar<k> = 1:N` loop-variable range the machinery materializes) reached Coder unbounded: heap `emxArray`s with dynamic memory allocation on, outright rejection with it off. Fixed in `lib/adigatorFunctionInitialize.m` by hoisting one guard per declared bound to the first statement of the main function body (all `loopbound` names are validated main-function inputs, so they are in scope there); the per-loop guards stay for the re-differentiation path. Padded ROM −224 B, stack +112 B, heap requirement gone. Pinned by `ILoopboundTest::guardPrecedesEveryBoundDependentSize` (license-free) and `SRolledErtCodegenTest::loopboundGradientErtCodegenStaticMemory` (Coder-gated, local-only) (§1.3i). |
| B38 (a trip count passed through into a subfunction is unguarded) | **Fixed** — B36's principle-1 residue one call deep: `main(x,N)` handing `N` to a subfunction that loops on it specialized the file without saying so, because the harvest is gated to the main function. That gate could not simply be loosened — it is what stops a shadowing subfunction parameter forging a guard with the wrong value (`subfunctionLoopDoesNotForgeAGuard`). Fixed by **interprocedural resolution** instead: a subfunction's loop range naming its own parameter records the position, every call site records its **caller's id** and its literal argument, and a guard is earned only when every site is *in the main function* and passes the same *bare identifier* — so `main(x,M)` guards `M` even when the callee spells the parameter `N`, while a site inside another subfunction (whose argument names something in ITS scope) declines rather than forging on correct code. Emits the ordinary main-scope `assert(N == n);` #211 already ships, so no recognizer, whitelist or re-diff path changes. Fail-closed on an expression, a local, a callee never called, or **disagreeing call sites** (adigator prints one body per function, not per call site). Guard survives to 2nd order via `adigatorGenHesFile`, analytic-exact; the 3rd-order pin the direct form carries is impossible for this shape because re-differentiating a subfunction-calling generated file fails for unrelated, pre-existing reasons — itself now pinned. Routes 2/3/4 remain (§1.3j). Pinned by `tests/integration/ISpecializedTripCountTest.m` (§1.3l; issue #213). |
| B37 (a rolled second-derivative pattern is the cross product of two loop overmaps) | **Fixed** — in the printing run of a rolled loop every operand carries its loop overmap, so `cadabinaryarraymath`'s scalar expansion (`cadaRepDers`) composed two n-wide unions as if independent and emitted the full n×n gather for a Hessian whose exported pattern is the n-nonzero diagonal; `cadaPrintReMap` then discarded 56 of the 64 one statement later, but only after the generated code had put n² doubles on the stack — 37,552 B at n=64, **63.4×** hand-written, while ERT-codegenning cleanly (the hollow milestone). Fixed by handing the emitting operation the overmap its result is about to be remapped into (`lib/@cada/private/cadaOverMapTargetNz.m`) so the doomed locations are dropped *before* they are printed — the same truncation, moved earlier, and guarded to fire only when that remap would actually have happened. Stack 768/9616/37552 → **160/352/608** B at n=8/32/64, i.e. exactly `96+8n`: affine, and the same series as the *vectorized* Hessian of the same maths, which also answers ADR-0035's caveat that part of the gap might be intrinsic to the rolled path (none of it was). Scope set by instrumenting every `cadaPrintReMap` over-approximation across the corpus — 18 events, of which the 17 with a growth law are all scalar expansion (the 18th is a bounded first-order `horzcat` case, §1.3k). Pinned by `tests/integration/IRolledOvermapWidthTest.m` (license-free) and `SStackScalingTest::subscriptedHessianMatchesVectorizedTwin` (Coder-gated, local-only), the latter having been the self-healing KnownIssue pin (§1.3k; issue #217, ADR-0036). |
| B36 (a loop range over a runtime-named scalar is unbounded even without `loopbound`) | **Fixed** — a file generated *without* the option still prints `cadaforvar1.f = 1:N` when the trip count names a function input (passing a plain numeric to `adigator` fixes the analysis count, not the input), so nothing bounds it and, unlike a `loopbound` file, nothing declares the envelope either. The emitted range and the emitted loop header disagree (literal header, runtime range): measured at `n=5`, calling with `N=3` is loud (index out of bounds) but `N=8` **runs silently** and returns the 5-term answer (70 vs a true 240) — a quietly wrong derivative, principle 1. Fixed by emitting `assert(N == n);` in the body prologue (an equality - the file is specialized, not padded), plus extending the shared guard shape and BOTH recognizers so re-differentiation still works: without the recognizer half every Hessian of a named-trip-count function would have stopped generating. Verified to 3rd order. Unblocked `bench/loopboundPaddingPenalty` under static memory allocation, which raised the measured padding penalty ~2x at small n (every earlier figure was heap-enabled). Fixed for the **direct** form (a main-function input named in a main-function loop range); three routes to a specialized trip count remain unguarded and are recorded as residual scope in §1.3j. Pinned by `tests/integration/ISpecializedTripCountTest.m` (§1.3j; issue #210). |

---

## 2. Optimizing the generated code for embedded use

### 2.1 Static data (size and access cost)

1. **Precompute linear indices offline.** The wrappers emit runtime index
   arithmetic on constant data every call, e.g.
   `Jac((y.dx_location(:,2)-1)*m + y.dx_location(:,1)) = y.dx;`.
   Since `_location` is constant, fold this into a single constant linear
   index vector at generation time: `Jac(JacIdx) = y.dx;` with
   `JacIdx = coder.const(...)`. This (a) removes per-call integer arithmetic,
   (b) halves the stored index data (one column instead of 2-4), and
   (c) eliminates the entire class of multiplier bugs (B7/B8/B10) by
   construction.
2. **Down-cast only `Index*` (see B1), and go to `uint16` when
   `max(idx) < 65536`** — typical embedded problem sizes fit, halving const
   tables again.
3. **Deduplicate index tables.** ADiGator frequently emits identical index
   vectors under different `Index*` names (same overmap reused). A
   content-hash pass in `prune_adigator_mat` can alias duplicates to one
   field before `structure_to_embed_mfile` emission; with `coder.const` the
   compiler may pool them anyway, but in `'i'` (inline) mode the *source text*
   shrinks dramatically.
4. **Range-compress index literals.** `cadaindprint` already collapses
   all-ones vectors; extend the inline emitter to recognize arithmetic
   progressions and emit `uint32(a:s:b).'` instead of 17-digit literal lists.
   In inline mode each number costs ~20 source bytes; contiguous gathers
   (`1:n`) are very common.

**What forward's index data *is*, and when it is removable.** Forward mode
represents a derivative as a *nonzero vector plus a constant map of where those
nonzeros live* in the assembled Jacobian/gradient. So a forward file carries,
near-universally, a `y.dX_location` table; and — for *matrix-bearing* operations
only (`mtimes`) — the `scatter → op → gather` projection tables. The two cases
differ:

- **Sparse derivatives** (the common embedded case): the location map *is* the
  sparsity structure — genuine, O(nnz), not removable. Forward is already
  near-optimal here.
- **Dense derivatives:** the location map degenerates to the contiguous
  identity. The forward gradient of a dense elementwise/reduction cost
  (`sum(exp(x)+2x)`, n=6) carries a *single* table, `Index1 = [1 2 3 4 5 6]` —
  the range `1:n` — with the body already fully vectorized
  (`y.dx = exp(x).*x.dx + …`) and `Data1` empty. (A fully dense *Jacobian's*
  location is likewise `1:(m·n)`, contiguous, just longer.) Two removals apply:
  **(a)** item 4 *range-compression* stores it as `uint32(1:n)` regardless of
  length; **(b)** *identity-location elimination* — when
  `y.dX_location == 1:numel`, the wrapper's `J(location) = y.dX` is the identity,
  so the table can drop and the wrapper emit `J = reshape(y.dX, …)` directly.
  Unlike R12's matmul scatter (whose precondition, an identity *scatter*, never
  arises — §3.5), the identity *location* genuinely does occur for dense outputs,
  so (b) is a tractable wrapper-level peephole.

**Priority: low.** Two distinct costs must not be conflated. The **location map**
is O(nnz), but for a fully dense output it is the contiguous identity — cheaply
range-compressed (item 4) or eliminated (b) at *any* length. The genuinely large
**O(n²) ROM** of a dense *matrix-bearing* derivative is a different thing: the
`scatter → op → gather` *projection plumbing* (§2.3, §3.5), whose scatter is
structured (never identity), so it is **not** removable by a peephole — R12 was
shelved for exactly this reason. So the location map is the only part this
clean-up reaches, and it is small once range-compressed. On top of that,
`der_output='csc'` (R5, respelled by #192/ADR-0030) already removes the per-call
dense scatter (returns the CSC value vector, exports the pattern once via
`output.*CSC`), and a *fully* index-free forward
dense gradient would mean re-deriving the dense closed form — which is exactly
what reverse mode does (§3.5: the reverse gradient of such a cost carries **zero**
static data). So forward dense-location elimination polishes the path one would
switch away from; the matrix-free / reverse work (R16–R18) is the real answer for
the dense case, while the sparse case genuinely needs its indices. Net: promote
item 4 if forward dense/contiguous ROM ever binds; otherwise this is documented
and deprioritized.

### 2.2 Dead code (the existing TODO)

The generated `*_ADiGator*` file always computes the function value *and all
lower-order derivatives* of every intermediate. When the user only consumes
`Jac`, large parts are dead:

- The robust approach is a **backward slice over the emitted statement list**:
  during printing, ADiGator knows for each statement which variables it
  defines/uses; record that, then keep only statements in the transitive
  fan-in of the requested outputs (`y.dX`, optionally `y.f`). Doing it inside
  the printer avoids fragile text-level analysis.
- A cheap interim version (as the TODO suggests) is an iterate-to-fixpoint
  `checkcode` pass deleting lines flagged "value assigned but never used" —
  works because the generated dialect has no side effects, but it cannot
  remove partially-used struct fields.
- Note the converse too: many `cada1f*` lines *are* needed by derivative
  rules (`dydx` depends on `x`), so slicing, not wholesale stripping, is
  required.

### 2.3 Runtime allocation and memory traffic

5. **Offer a triplet/CSC output mode instead of dense projection.** The
   wrapper does `Jac = zeros(m,n)` (a full memset) plus a scatter on every
   call. Embedded consumers (PIPG-style first-order solvers, QP/NLP solvers)
   want either the nonzero vector with a constant sparsity pattern, or
   matrix-vector products. Emit alternative wrappers:
   - `[vals] = myfun_JacNz(...)` plus constant `rows/cols` (or `colptr/rowind`
     CSC) exported once — zero per-call allocation;
   - `w = myfun_JacTvp(v, ...)` computing `J'*v` / `J*v` directly from the
     nonzero vector — what gradient-based embedded solvers actually need.
6. **Peephole pass to remove no-op gather/scatter.** Sparsity-union
   ("overmap") code of the form
   `cada1td1 = zeros(k,1); cada1td1(Index) = src; ...` is an identity copy
   whenever `Index` is `1:k` and `src` has length `k`. Detectable at
   generation time from the index constants; implemented as R7c
   (`adigatorPeepholeUnionCopy`, wired into the `slim_embed` driver).

   **Empirical reachability note (R10(b), issue #44 item 2).** A probe of ~40
   generated Jacobians/Hessians — straight-line, rolled (`unroll=0`), and
   unrolled (`unroll=1`) — found that this *ordered-identity full fill* does
   **not** actually arise in code this fork's emitter produces: real overmaps
   are always strict **partial** fills into a union-sized buffer (e.g.
   `Index=[1 2]` into `zeros(4,1)`, `[1 3 5]` into `zeros(6,1)`), and
   equal-pattern unions are added directly with no overmap buffer at all
   (`cadaOverMap` only allocates a buffer when the union genuinely grows). The
   rolled-loop scatters are loop-counter-indexed logical masks, a different
   shape the peephole bails on anyway. So the R7c collapse is
   **correct-but-unreachable** on current generated input — its collapse count
   is always 0 in `IEmbedSlimTest`/`SCodegenTest` (which is why `SCodegenTest`
   reports "collapsed 0 union copies" on the real `gapfun`). The collapse logic
   is exercised positively by the synthetic fixture in `IPeepholeDriverTest`
   (TS-I-08); the pass is retained as a guard for the pattern.

   **Re-vectorization post-pass — shelved (R12, ADR-0016).** The natural
   follow-on idea was a larger source-to-source pass fusing the
   `scatter → matrix-op → flatten → gather` plumbing that `cadamtimesderiv`
   emits. It was prototyped far enough to measure (§3.5) and then **shelved**:
   the fusion precondition — an *identity* scatter — does not arise (the scatter
   intrinsically maps the sparse nonzero-vector into structured positions of the
   dense operand matrix), and the ROM cost it would chase is intrinsic to
   assembled dense matrices, not removable by a peephole. The embedded-efficiency
   lever is the matrix-free product family instead (§3.5).
7. **Keep loops rolled (`unroll=0`) for code size**, but verify Coder
   compatibility of the rolled-loop Gator data (cell arrays indexed by loop
   counter): heterogeneous constant cells are supported by `coder.const`, but
   add a codegen smoke test (`codegen -args` in CI) per example to catch
   regressions early.

### 2.4 Pipeline hygiene

8. Close both wrapper fids (B13) before any read-back; better, have the
   generators return the text and let one writer own file IO.
9. Drop the `addpath`/`path(original_path)` dance in the generators by
   passing absolute paths to `exist`/`delete` and calling the user function
   via its handle; mutating the MATLAB path is process-global state that the
   try/catch only partially protects (e.g. `dbquit` still leaks it).
10. Stamp generated files with the adigator version + options hash so stale
    derivative/`.mat`/data-function triplets can be detected at load time —
    a real failure mode once files are committed into firmware repos.

---

## 3. A path to reverse-mode differentiation

### 3.1 Why and when

Forward mode costs O(n) passes (mitigated, but not removed, by ADiGator's
compile-time sparsity exploitation): for `f: Rn → R` with a *dense* gradient
(objectives are sums — `logsumexp`, least squares, Lagrangians), the forward
nonzero count of intermediates grows with `n`, so both code size and runtime
scale with `n`. Reverse mode computes the same gradient in O(1) function-cost
sweeps. For the embedded use case (objective gradients, `J'*v` products for
first-order solvers) this is the dominant win; Jacobians with `m ≈ n` or
strong column sparsity should stay forward.

### 3.2 Key observation: ADiGator already produces a static tape

After ADiGator's overloaded evaluation pass, the user program has been
resolved into a *linear sequence of primitive vectorized statements with
fixed sizes and precomputed constant index maps* (that is exactly what gets
printed to the derivative file). All control flow is either unrolled or
reduced to rolled `for` loops with per-iteration index tables
(`ADIGATORFORDATA`). This is precisely the "tape" a reverse sweep needs —
but available at *generation time*, so reverse mode can be emitted as static
source code with **no runtime taping and fully static memory**, which is
ideal for embedded targets.

### 3.3 Staged plan

**Stage 0 (no new mode, immediate):** for structured Jacobians use the
existing compression utilities (`adigatorColor`, `adigatorUncompressJac`)
to cut forward cost; document this as the stopgap.

**Stage 1 — persist the op list.** Extend the printing pass so every emitted
statement records `(opcode, input var ids, output var id, index-data refs,
operand sizes/sparsity)` into `ADIGATORDATA`. Most of this information is in
scope at each print site (`cadaunarymath`, `cadabinaryarraymath`, `mtimes`,
`sum`, `subsref`, `subsasgn`, `horzcat`, ...); the work is plumbing, not new
math. Gate it behind an option so normal generation is unaffected.

**Stage 2 — adjoint emitter.** Walk the op list backward and emit
`myfun_ADiGatorRGrd.m`:

- *Forward section:* re-emit only the function-value (`cada*f*`) statements
  (the slice from §2.2 gives exactly this), keeping intermediates needed by
  nonlinear adjoint rules live in fixed-size locals.
- *Elementwise unary ops:* reuse the `getdydx` rule table from
  `cadaunarymath.m` verbatim — the adjoint is `xbar += ybar .* dydx(x)`.
  (The recent rule-table fixes + `test_unarymath_rules.m` make this table a
  trusted single source of truth for both modes.)
- *Elementwise binary ops:* both partials already exist in
  `cadabinaryarraymath.m`.
- *Structural/linear ops* (`subsref`, `subsasgn`, `reshape`, `repmat`,
  `cat`, `sum`, `transpose`, sparse projection): the adjoint is the
  transposed index map, computable at generation time from the same constant
  index vectors the forward op uses — gathers become scatter-adds, `sum`
  becomes broadcast, `repmat` becomes `sum`. One care point: scatter-*add*
  with duplicate indices must be emitted as `accumarray`-style accumulation
  (or a generated loop), not plain indexed assignment; duplicates are
  detectable offline, so emit the cheap form when indices are unique.
- *Matrix ops:* `C = A*B` → `Abar += ybar*B.'`, `Bbar += A.'*ybar`;
  `mldivide` → solve with the transposed factor. These few ops cover the
  optimization-oriented examples in this repo.

**Stage 3 — control flow.** Start by supporting `UNROLL=1` only (embedded
users already favor static unrolled code); error out cleanly otherwise.
Then add rolled loops: emit `for i = N:-1:1` and index the per-iteration
tables (already stored per iteration for rolled loops) in reverse. `while`
loops stay unsupported in reverse (no static trip count — they're also a
codegen liability).

**Stage 4 — memory model.** Adjoint buffers have the same overmapped sizes as
their primal counterparts → total memory is a compile-time constant (sum of
intermediate sizes). No checkpointing machinery is needed; if code size
becomes the binding constraint, rolled loops (Stage 3) are the lever.

**Stage 5 — integration & validation.**
- New `DerType` `'gradient-reverse'` in `adigatorGenDerFile_embedded`; the
  existing pruning / `coderload` / inline post-processing applies unchanged,
  since the adjoint file consumes the same kind of `Index*`/`Data*` constants.
- Validation harness: for every example (`brownf`, `gapfun`, brachistochrone,
  `logsumexp`), assert `‖g_reverse − g_forward‖ ≤ tol` and compare against
  finite differences; add a vector-output `J'*v` check against the forward
  Jacobian. Wire into `tests/unit/`.
- Follow-up: Hessian-vector products as forward-over-reverse (differentiate
  the generated reverse file with the existing forward machinery) — gives
  `H*v` in O(1) sweeps for Newton-CG-type embedded solvers, versus the
  current forward-over-forward full Hessian.

### 3.4 Lower-risk alternative: transform the generated file

If modifying ADiGator's printer (Stage 1) is too invasive, note that the
*generated* forward file is itself a flat MATLAB program written in a tiny,
regular dialect (~30 statement shapes: elementwise ops, constant-index
gather/scatter, `mtimes`, `sum`, `zeros`, struct field moves), with all
indices constant. A small standalone source-to-source reverse transformer
over that dialect — parse each line, classify the statement shape, emit its
adjoint — achieves the same result without touching ADiGator internals, and
its restricted grammar makes it testable line-shape by line-shape. The cost
is sensitivity to the printer's textual conventions; pinning it with golden
files of generated code mitigates that.

### 3.5 Measured determination: matrix-free products are the embedded-efficiency frontier

The "vectorization / matrix algebra" question (#56) was settled by measuring
this fork's actual generated code rather than by reasoning. Recorded here as the
evidence behind [ADR-0016](../decisions/ADR-0016-matrix-free-products-efficiency-path.md);
it also reframes R12 and motivates R16–R19.

**Method.** For representative functions across the three derivative objects,
generate the derivative file(s) and measure two embedded-relevant quantities:
generated **statement count** (≈ compiled-C size) and total **static-data
elements** (the constant `Index*`/`Data*` tables ≈ constant ROM). Forward via
`adigatorGenJacFile`/`adigatorGenHesFile`; reverse via `adigatorGenRevGradFile`
(gradient) and `adigatorGenJtVFile` (J'·v).

**Result (static-data elements ≈ ROM, n = 64).**

| Object | sparse assembled | dense assembled | matrix-free product |
|---|---|---|---|
| Gradient (m=1) | — | fwd `_Grd` O(n): 83 | **`_RGrd`: 0** |
| Jacobian (m×n) | fwd `_Jac` ∝nnz: 131 (diag), 507 (band) | fwd O(mn): 12,419 (n×n), 98,435 (8n×n) | **`_JtV` (J'·v): 0** |
| Hessian (n×n) | fwd-o-fwd `_Hes`: 198 (diag) | fwd-o-fwd O(n²): 41,542 | H·v: not yet implemented |

For matrix-bearing scalar costs the forward gradient's static data grows
**O(n²)** (e.g. `sum((A·x)²)`: 323 → 1,263 → 4,923 → 19,443 for n = 10/20/40/80)
while the reverse gradient stays at **0** with flat statement count. Reverse
correctness was verified: reverse gradient = forward = analytic `(A+A')x` to
~1e-10 (a harness note: the forward `_Grd` wrapper is `[Grd,Fun]` — derivative
first — so the value is the *second* output; mixing this up looks like a forward
bug but is not).

**Reading.**

1. **Forward already vectorizes** (statement count is flat in n — `exp(x)` is one
   statement regardless of size). What it carries is the sparse-index ROM +
   scatter/gather plumbing, so "re-vectorize the generated code" is the wrong
   lever (§2.3, R12 shelved).
2. **The cost is governed by density and assembled-vs-matrix-free, not by AD
   mode.** Forward assembled data scales with `nnz` of the derivative. For
   **sparse** J/H — the common embedded case (banded/structured constraint
   Jacobians, structured Hessians) — forward + ADiGator's compile-time sparsity
   exploitation is already lean (131 / 507 / 198). For **dense** assembled
   matrices the O(n²) ROM is **intrinsic**: any representation of a dense n×n
   matrix is n² numbers; reverse does not avoid it (it would need *m* adjoint
   sweeps to assemble) and no peephole removes it.
3. **Matrix-free products carry ~0 ROM regardless of density** — confirmed 0 for
   `_RGrd` and `_JtV` across diagonal / dense-square / tall shapes. This is the
   one broadly-applicable embedded win, and it spans all three objects (J·v,
   J'·v, H·v), which is what matrix-free embedded solvers (Krylov, PIPG,
   Newton-CG) actually consume.

**Determination.** The assembled-matrix path is essentially solved (forward +
sparsity for sparse; dense O(n²) is intrinsic; R7 slimming is the marginal
lever). The open frontier is **completing the matrix-free product family**:
gradient (`_RGrd`) ✓ and J'·v (`_JtV`) ✓ exist; the gaps are **H·v** (via
forward-over-reverse — forward-differentiate the `_RGrd` file; the highest-
leverage piece, bringing zero-ROM to second-order embedded solvers) and **J·v**
(forward directional), then **rolled-loop reverse** (§3.3 Stage 3) so the
products reach the rolled allocation-over-time anchor. Reverse first needs
**embed-pipeline parity** (Stage 5) to be comparable through to C. These are the
R16–R19 rows; the C-level confirmation of the ROM finding is delivered by the
#73 all-axes harness over the #64/ADR-0014 codegen-equivalence machinery.

H·v's zero-ROM is *inferred by analogy* to `_RGrd`/`_JtV` (forward-over/reverse
over dense vectorized code); it is to be **measured** when implemented (R18), not
assumed.
