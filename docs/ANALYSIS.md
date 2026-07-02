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
> **B19/B21/B22 remain open, B20 is a documented limitation** (B18 no longer
> reproduces); they are the subject of ROADMAP R26. Where a
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

`adigatorDerivativeConventions.m` (the new conventions spec) contradicts both
itself and the implementation:

- **Jacobian section (lines 30-40):** displays the standard `m×n` Jacobian and
  the usage `Jacobian_x(f) * x` (which requires `m×n`), but states
  `size(...) = [length(x) length(f)]` = `n×m`. The implementation produces
  `m×n`. The size line is wrong (and is mislabeled `size(Gradient(f))`).
- **Hessian section (lines 17-27):** `f: Rn -> Rm` should read `f: Rn -> R`;
  `size(Gradient(f)) = [length(x) length(f)]` should read
  `size(Hessian_x(f)) = [length(x) length(x)]`.
- Line 36 typo: last Jacobian row reads `dfm/dx1 ... dfn/dxn` (`dfn` → `dfm`).
- The summary block (lines 53-58) is internally inconsistent with the
  generalization table (e.g. `any(c,r=1) & any(c,r>1) → r*c x n*m` covers the
  `r=1` row that the table assigns `c×m`/`c×n` shapes).
- The same comment blocks are pasted into `adigatorGenJacFile.m` and
  `adigatorGenHesFile.m` with the same errors; the Jac-file header
  (lines 50-58) still documents the upstream behavior and does not mention
  that with the `'Grd'` appendix a *column* gradient is returned.
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

**Fix (ROADMAP R9 B.3, [ADR-0011](decisions/ADR-0011-adigator-error-path-cleanup.md)).**
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

### 1.3c Core-transform bugs found via an embedded struct-parameter field report (B17–B21)

A local (proprietary, un-committed under `docs/known-bugs/`) report of failures
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
add a regression guard only.

**B19 — index over-approximation inside `while`+`if` (open).** Indexing a
constant table by a loop counter inside `while n <= N` with nested `if (n>1)` /
`if (m>1)` guards fails generation with `Cannot do strictly symbolic
referencing/assignment`; the report's workaround re-asserts the loop bound
inside each guard (`if and(cond, n<=N)`). Suspected: the index-range / overmap
analysis over-approximates the counter past `N`. Reproduces on HEAD. Needs
tracing — may resolve to the same symbolic-index limitation as B20, or a genuine
loop-range fix.

**B20 — data-dependent (runtime) indexing (limitation; make the error
actionable).** Indexing a variable by a value computed at runtime
(`ref_data(ref_idx,3)` with data-dependent `ref_idx`) is not expressible in
static forward AD with compile-time sparsity (the pattern would be
runtime-dependent). It already errors (`Cannot do strictly symbolic
referencing/assignment` — principle 1, not silently wrong) but cryptically.
*Disposition (decided):* keep the error, make it **actionable** (name the
construct, point to the logical-weight-sum idiom) and document the limitation +
idiom in the user guide. Reproduces on HEAD.

**B21 — user `load(...)` emitted verbatim into the inline/coderload file
(C-4, open).** When the differentiated function itself contains
`S = load('x.mat')`, the embedded `'i'`/`'l'` pipeline passes the `load` through
into the generated file, breaking the dependency-free guarantee (contract C-4).
Orthogonal to B17 — surfaced while testing B17's load provenance (B17's runtime
`.f` fix is independent and still applies, since the struct is materialized in
the body either way). *Disposition:* capture the loaded constants as embedded
data, or document that parameters must be pre-loaded and passed as inputs.
Reproduces on HEAD.

**B22 — constant-*cell* element analog of B17 (high severity, same class;
open).** The B17 fix guards struct fields; a numeric element of a constant
*cell* assigned in the body reaches `structParse` with `structflag=1` and is
**not** marked derivative-free. Reproduced on HEAD (found during the B17
review, #102): `C = {M, g}; y = C{1}*x + C{2}*x;` emits `C{1}.f` and crashes at
runtime (`Dot indexing is not supported … C{1}.f`) — identical silent-broken-
codegen class to B17, cell instead of struct. *Fix:* mirror B17 — mark constant
cell elements derivative-free so they print bare — as a fast-follow to #102 with
its own cell pinning test. Note `structParse`'s per-field constant marking must
apply on the `structflag=1` (cell/nested) path too, not only the top-level
struct arm.

### 1.4 Genuine fixes in this fork (verified, for the record)

- `cadaunarymath.m` derivative-rule corrections (`asec`, `acsc`, `asecd`,
  `acscd`, `acosh`, `asech`, and the `sind/cosd/...` family): the new forms
  are branch-correct for negative arguments (e.g.
  `d/dx asec(x) = 1/(x²√(1-1/x²)) = 1/(|x|√(x²-1))`) and the degree-mode
  factor is now correctly `π/180` *with degree-mode trig on the RHS* instead
  of `180/π` with radian trig — both upstream errors. Covered by
  `unit_tests/test_unarymath_rules.m` (finite-difference check).
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
| B18 (constant/aux-param conditional) | **Fixed (no longer reproduces)** — generates + matches FD ~1e-10 both branches (likely R8). Needs a regression guard only. |
| B19 (while+if index over-approximation) | **Open** — reproduces (`Cannot do strictly symbolic referencing/assignment`); needs tracing (loop-range analysis vs. B20-class limitation). ROADMAP R26. |
| B20 (data-dependent indexing) | **Won't-fix as a limitation → actionable error + docs** (decided; ADR to accompany the R26 fix) — keep the error, make it point to the logical-weight-sum idiom; document the limitation. ROADMAP R26. |
| B21 (user `load` verbatim in inline file) | **Open** — C-4 violation, orthogonal to B17 (found via B17's load-provenance test). Capture load'd constants as data, or require pre-loaded params. ROADMAP R26. |
| B22 (constant-cell element `.f`) | **Open** — same class as B17 for constant *cells* (the `structParse` `structflag=1` path is unguarded). Found during the #102 review; reproduces on HEAD. Fix mirrors B17 (mark constant cell elements derivative-free) as a fast-follow to #102 with a cell pinning test. ROADMAP R26. |

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
`jac_output='nonzeros'` (R5) already removes the per-call dense scatter (returns
the nonzero vector, exports the pattern once), and a *fully* index-free forward
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
  Jacobian. Wire into `unit_tests/`.
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
evidence behind [ADR-0016](decisions/ADR-0016-matrix-free-products-efficiency-path.md);
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
