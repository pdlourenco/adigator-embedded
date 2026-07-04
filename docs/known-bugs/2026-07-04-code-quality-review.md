# 2026-07-04 repo-wide code-quality review

Reviewed at master `188d8d1` (findings re-verified against `abcc53f` after the
#112/#113 doc-sync merges). Scope: all fork-authored code (`embedding/`,
`util/`, the fork edits in `lib/`), the test suite, `docs/ROADMAP.md`,
`docs/ANALYSIS.md`, and the open issues — **code quality over features**, per
maintainer request. Method: five parallel deep-read review passes (one per
surface), followed by an independent hand-verification of every high-severity
finding and most medium ones; every claim below is backed by quoted code that
was re-read in place, not pattern-matched.

Unlike the sibling reports in this folder, this file contains **no proprietary
content** — everything is derived from the public repository (hence the
`.gitignore` whitelist entry).

Cross-references: bugs **B23–B26** are catalogued in
[`../ANALYSIS.md`](../ANALYSIS.md) §1.3d with dispositions in §1.5; remediation
is roadmap row **R28**; tracking issues
[#117](https://github.com/pdlourenco/adigator-embedded/issues/117) (B23–B26),
[#118](https://github.com/pdlourenco/adigator-embedded/issues/118) (D1),
[#119](https://github.com/pdlourenco/adigator-embedded/issues/119) (D2/T1),
[#120](https://github.com/pdlourenco/adigator-embedded/issues/120) (M11),
[#121](https://github.com/pdlourenco/adigator-embedded/issues/121) (hygiene
umbrella).

## Verdict

The fork's newest code (the slimming/tape stack, the ADR-0023 gate, the MC
harness, the R26 fixes) is in genuinely good shape — fail-closed,
well-commented, test-pinned. The quality debt concentrates in three places:
**(1)** the *metadata* surfaces (`*Structure`/`*Locs`) and rarely-exercised
shape corners, where two silent-wrong-output bugs of exactly the B7–B10 class
were confirmed; **(2)** the inherited `GenFiles4*` wrappers (verbatim-upstream,
commit `a774402`), which carry broken emission paths; **(3)** documentation
artifacts that are *binding* under the repo's own rules but defective — most
notably `adigatorDerivativeConventions.m`, which still contradicts contract
C-1. The pattern connecting the code findings: everything high-severity lives
where the test registry has a hole, and the registry holes are themselves
documented below (T1/D2).

---

## 1. High severity — principle-1 class (silent wrong output) → issue #117

### B23 — `HessianStructure`/`HessianLocs` corrupted for a matrix function of a scalar variable

`util/adigatorGenHesFile.m:484-488` + `:609-616`. The v1.5 shape-remap block
mutates `ysize` (`ysize = [ysize(1) 1]`) and sets `remapcase = 2` with the
comment *"remember the shape remap (see adigatorGenJacFile B10 fix)"* — but
unlike `GenJacFile`, which consults `remapcase` when building
`JacobianStructure` (lines 335/439/441), `GenHesFile` consults it only for the
gradient projection (:498-500) and never in the Hessian-metadata block. At
:610, `HesPat = zeros(ysize)` allocates `r×1` while `HesLocs1(:,1)` holds
linear indices into the unrolled `r×c` output; MATLAB grows the array on
out-of-range linear assignment, so `output.HessianStructure` becomes a column
vector and `ind2sub` (:615) yields `HessianLocs` with every column index = 1.
The emitted wrapper itself is correct (built pre-mutation, :406-414), so a
consumer scattering `der_output='nonzeros'` values through `HessianLocs`
reconstructs a **silently wrong Hessian**. Violates REQ-T-03 and principle 1.
Half-ported copy of the B10 fix — drift of exactly the duplicated
first-derivative projection block the REVIEW_CONTEXT red-flag list warns
about. Unpinned because `IShapeMatrixTest.hesMatrixOfScalar` checks `Hes` but
never the structure (T1).

### B24 — reverse mode applies the elementwise `./` adjoint to true matrix division `/`

`util/adigatorGenRevGradFile.m:323` + `:715-720`. The classifier regex accepts
`/` and the rule `case {'./','/'}` emits `cb./b` / `-(cb.*y./b)` for both
ops. `lib/@cada/mrdivide.m:267` prints genuine `A/B` (square `B`) into the
forward tape, so an active square-matrix division is classified `binary` and
gets the elementwise adjoint — which for same-size operands **runs without
error and produces a wrong gradient**. The `*` case has exactly the guard
that is missing here (`strcmp(info.op,'*') && ~isequal(asz2,[1 1]) &&
~isequal(bsz,[1 1])` → matrix rule, :706); `\` correctly falls through to the
`adigator:revgrad:unsupported` error. Contradicts the file's own header
contract ("anything unsupported on the active path errors at generation
time"). `oracleFwdRev` fuzzes scalar costs but never matrix division, so the
fuzzer cannot see it.

### B25 — N-D parameter reference: position-2 base subscript never validated

`lib/@cada/subsref.m:331-341` (`NDRefTranslate`). Subscripts at positions ≥3
get integer + range checks against `csz(jj)` on both the numeric and cada
paths (:361, :378-380); `base = s.subs{2}` gets neither (no integer check, no
range check against `csz(2)`, and a `logical` base is accepted and added
numerically to the offset). `B` declared `[3 4 5]`, user writes `B(1,5,2)` —
a hard out-of-bounds error in plain MATLAB — translates to fold column
`5 + (2-1)·4 = 9`, valid in the `3×20` fold, and **silently returns
`B(1,1,3)`**: wrong value, wrong derivative, from a typo the tool should
reject.

### B26 — `length()` of an N-D declared parameter silently returns the fold length

`lib/@cada/length.m:11,42` computes `max(x.func.size)` with no `ndsize` guard,
while `size.m:125-130` rejects `size(x,dim>1)` on `ndsize` vars for precisely
the declared-shape-vs-fold ambiguity. Declared `[3 4 5]` (fold `3×20`): MATLAB
`length(B)` is 5, the overload yields 20 — `for k = 1:length(B)` silently
iterates the wrong count. The PR #14 guard landed in one overload but not its
sibling. (Med-high: silent semantic divergence feeding loop bounds.)

### T1 — the compounding factor: metadata surfaces are systematically unasserted

`CI_PLAN.md:133` claims TS-I-01 (`IShapeMatrixTest`) asserts
"`JacobianStructure`/`HessianStructure` consistency" parameterized over the
shape matrix; the actual test has 12 hand-written methods, no `TestParameter`,
and **zero assertions on any exported structure** — every generation call
discards the output struct. That is why B23 existed undetected, and it leaves
the whole REQ-T-03 surface guarded only by the extended-suite
`oracleSparsitySuperset`. B23's fix must land together with structure
assertions (issues #117 + #119).

---

## 2. Medium severity → issue #121 (except M11 → #120)

### Generators & emission (`util/`)

- **M1.** `adigatorGenFiles4Fmincon.m:410-411, 445-446`,
  `adigatorGenFiles4Ipopt.m:348-349`: `fprintf` formats contain `%1.0d`
  conversions **with no arguments** — MATLAB truncates the emission at the
  first conversion, so the single-inequality/equality sparse branch
  (`n²≥250`, density ≤ 3/4) writes a syntactically broken `_Hes` file
  (`conHes = sparse(...,lambda.ineqnonlin*con.dxdx,` with no dims/closer).
  Loud at first call; the generator reports success. Verified. Inherited
  upstream, live here.
- **M2.** `adigatorGenFiles4Fminunc.m:104`: `if order` with `order ∈ {1,2}`
  is always true — order-1 names the gradient wrapper `_Hes`, includes
  `ObjD2FileName` in `AllFileNames` (so `overwrite=1` deletes a pre-existing
  `myfun_ADiGatorHes.m` it never regenerates), and the `_Grd` branch at :109
  is dead. Verified.
- **M3.** `adigatorGenFiles4Fmincon.m:490` vs `:498`: the constraint-gradient
  handle is `funcs.congrd` with auxdata but `funcs.consgrd` without.
- **M4.** `adigatorGenHesFile.m:262-265`: both fids get `Gfuncstr`, so the
  Hessian wrapper's help header shows the *gradient* signature and "Gradient
  wrapper file"; `Hfuncstr` (:259) is built and unused. Verified.
- **M5.** `util/error_restore_path.m:4`: `error(msg)` passes composed text as
  a *format string* (call sites embed user paths — a `%` or backslash mangles
  or throws) and carries no error ID, unlike the fork's newer `adigator:*`
  convention. Verified.
- **M6.** Hygiene asymmetry across the four generators: `GenRevGradFile`'s
  overwrite guard runs *after* full generation (:190-192) and its forward
  intermediates are deleted on the success path only (:227); no generator
  checks `fopen` for `-1`; emission sections are unprotected so a
  mid-emission error leaks the handle (B13 closed the success path only);
  `opts.echo` gates the banner in RevGrad only; `adigatorNormalizeEmbedMode`
  is applied in GenJac/GenHes only.

### Embedding pipeline

- **M7.** `embedding/prune_adigator_mat.m:107-114`: the `Index*` down-cast
  has **no range guard** — `uint32()` silently saturates above 2³².
  ANALYSIS §1.5 explicitly rejected `uint16` on exactly this argument and
  adopted 2³² as an *assumption*, but the code never checks it, while
  `structure_to_embed_mfile.m:212` does guard its own compression with
  `< 2^53`. Verified.
- **M8.** `embedding/adigatorGenDerFile_embedded.m:257-308`: in inline mode
  the source `.m`/`.mat` are **deleted before** the patched wrapper is
  written (four separate `writelines` calls, `data_*.m` cleanup last), with
  no `try`/`onCleanup` — any error in between leaves a truncated wrapper and
  nothing to regenerate from. Loud failure, dirty state; contrasts with
  `adigatorSlimEmbeddedDeriv`'s restore discipline.
- **M9.** `embedding/adigator_patch_derivative.m:98-115`: no `isempty(gidx)`
  guard after the B4 header fix — a missing `global` line yields a cryptic
  indexing error, and because the scan runs to EOF it could silently bind the
  *next* subfunction's global. Latent (the printer emits the global
  unconditionally, `adigatorFunctionInitialize.m:1011,1031`).

### Fork edits in `lib/`

- **M11 → issue #120 (decision needed).** Loopbound doc/implementation drift:
  `adigatorOptions.m:85-90` promises exit-variable unions for outer *and*
  inner rolled loops; the union block is gated `~PARENTLOC` (outermost only,
  `adigatorForIterEnd.m:477-480`). Either the doc over-claims or inner
  runtime-bound loops miss a union they need;
  `ILoopboundTest.nestedRuntimeBoundsWithNDParam` cannot discriminate (its
  inner loop feeds a padding-benign accumulator). Flagged per CLAUDE.md §3
  without picking a side.
- **M12.** `lib/@cada/cada.m:523-546` vs the `size.m` guard: `B(:,end)` on an
  ndsize var errors through the `size(…,dim>1)` rejection — yet the fold form
  is precisely what `subsref.m:355-358`'s own error message recommends. The
  two fork edits contradict each other's guidance.
- **M13.** `lib/@cada/cada.m:639`: `isvec = any(xsize<=1) ||
  any(isinf(xsize))` lets a *vectorized matrix* (`[Inf 3]`) bypass the C-5
  `adigator:norm:matrixNorm` policy error (it then dies later in `sum` with
  an unrelated message). Error-not-wrong-value today, but the contractual
  error surface is bypassed.
- **M14.** `adigator.m:139/344-345`: the ADR-0023 gate compares `embed_mode`
  with exact `strcmp(…,'l'/'i')` but the core's 4-arg option ingestion never
  normalizes — `struct('embed_mode','inline')` passed directly to the core
  **silently disables the C-4 source gate**. All shipped wrappers normalize
  first, so it needs misuse — but it is exactly the B11 brittle-comparison
  shape the red-flag list names.

### Test suite

- **M15.** REQ-T-04's "no runtime `load`" clause is never statically asserted
  for `'l'` mode — every check (`IEmbedModesTest.m:63-74`,
  `IRevEmbedTest.m:53-57`, `oracleCrossMode.m:39-44`) tests `coder.load`
  presence, but a raw `load(` cannot be caught by `contains` (it matches
  `coder.load`); needs `(?<!coder\.)\bload\(`. A patcher regression leaving a
  bare `load` would pass all static *and* numeric checks (the `'l'` `.mat`
  legitimately exists) and surface only under codegen — which no test runs on
  `'l'` files. Principle 2's weakest link.
- **M16.** `SCodegenTest.m:99-106`: the REQ-T-10 ERT half is gated by a plain
  `if license(...)` — on a Coder-only runner it silently doesn't run and the
  test is green, indistinguishable from covered. `SRolledErtCodegenTest.m:27`
  does it right (`assumeTrue` → visible Filtered). Its only ERT assertion is
  also just `isfolder('codegen_lib')`.
- **M17.** `ISmokeTest.m:49` evaluates the classic wrapper without clearing
  `ADiGator_gapfun_ADiGatorGrd`; `IEmbedModesTest` (alphabetically earlier)
  leaves that global populated, so the smoke test's `.mat`-load leg is
  **silently skipped by run order** — a prune regression could hide.
  `IEmbedModesTest.m:99-101` documents the exact dance ISmokeTest is missing.
- **M18.** The montecarlo docstrings promise an "FD oracle carries the value
  check" (`mcCase.m:26-27`, `oracleKnownDeriv.m:7-8`, `mcGenShapeFuzz.m:7,40`)
  — **no FD oracle exists** (`oracles/README.md:58` admits it's a later
  phase), and `mcGenShapeFuzz` is in the default campaign, so its cases get no
  value oracle at all: a wrong-valued derivative on a fuzzed shape (the
  historical B7/B10 class) passes. Relatedly, `CI_PLAN.md`'s "tolerance-free
  oracles" is undercut by `oracleKnownDeriv.m:19`'s `1e-9` tolerances on
  exact-by-construction cases.

---

## 3. Low severity (index; details on request) → issue #121

*Code:* dead `strcmp(NameAppendix,'Jac')` fossil branches in
`GenHesFile:520-535`; the `250`/`3/4` sparse-projection thresholds hard-coded
at 8+ sites with one drifted comparison (`Fsolve:167` uses `<` vs `<=`
elsewhere); `GenHesFile:599`'s hidden cross-directory dependency on
`embedding/updatestruct` (`IOutputModesTest:16` works around it);
`adigator_patch_derivative` — loop at :126-134 ignores its own loop variable
(idempotence-dependent), dead `avoid_start` parameter with inverted-looking
logic, LoadData removal deletes to EOF on an unstated layout assumption,
internal write-back at :140-142 is wasted I/O; `structure_to_embed_mfile`
docstring + one error ID still carry the pre-rename `emit_data_helper_file`
identity; contradictory `\b`-regex attributions between
`adigatorReferencedIndex.m:54` (wrong: blames Octave) and
`adigator_patch_derivative.m:149` (right: MATLAB); `updatestruct.m:33` dead
variable + latent cell-coercion; `DerType` dispatch case-sensitive while the
adjacent option surface is case-normalized; `cadaErrorSymbolicIndex` wired
into only subsref/subsasgn while `@cada/sparse.m` (5 sites) and
`@cada/diag.m:46` still raise the pre-B20 cryptic message with no ID;
`structParse` has no trailing else (constant `logical`/`char` fields get no
B17-style marking — plausibly the same unbacked-`.f` shape, untested) and
asymmetric empty-numeric handling between arms; dead `.`-subscript branch in
`subsref.m:275-284`; subsasgn's N-D guard fires in `EMPTYFLAG` dead branches
while subsref deliberately skips; `cada.m:11-15` changelog omits the
`norm`/`isnan` fork additions; ADR-0023's cell scan detects `{}`/brace
indexing only (`num2cell`/`cell(n)` bypass the gate's literal wording).

*Tests:* tautological `verifyGreaterThanOrEqual(count, 0)` in
`IEmbedSlimTest:160` (pin `count==0` instead); `UNormTest:155` accepts any
error mentioning "matrix" where the C-5 ID is the contract; 12+ private
fixture-writer copies while `tests/helpers/writeFixtureFile.m` is
montecarlo-only, six without an `fid>0` check; `MCRegressionTest` re-checks
promoted reproducers with a fixed oracle pair rather than the failing oracle;
`SCodegenTest` header says "exactly" while asserting 1e-14.

---

## 4. Documentation findings

### D1 — `adigatorDerivativeConventions.m` contradicts C-1 → issue #118

The authoritative conventions file (CLAUDE.md §3) still carries every §1.3
defect: `:16` the Hessian section declares `f: Rn -> Rm`; `:23`/`:38` both
tables captioned `size(Gradient(f)) = [length(x) length(f)]` — for the
Jacobian that reads **n×m, contradicting C-1's m×n** and the implementation;
`:36` the `dfm/dx1 … dfn/dxn` typo; `:53-58` the inconsistent summary block.
Newer sections (C-6 names, ADR-0020) were appended around the defects. The
same defective tables live as v1.5 comments in `GenJacFile:286-290` /
`GenHesFile:335-343` (§1.3's claim that the file *headers* still carry them is
stale — headers were fixed, body tables were not). §1.5 has no disposition row
for §1.3. Code is right; binding text is wrong.

### D2 — CI_PLAN registry phantoms → issue #119

`URulesBinaryTest` (TS-U-02, `CI_PLAN.md:110`), `UStructuralOpsTest`
(TS-U-03, `:111`; also DESIGN C-2 *Verified by*), `ISecondDerivTest`
(TS-I-04, `:136`; also DESIGN C-1 *Verified by*), and `tests/helpers/fdcheck.m`
(`:207`) are named as existing — none exists, no `(planned)` markers, and the
traceability table credits REQ-C-02/03 and REQ-T-01/REQ-C-04 to them.
`ULintTest`/`SReleaseMatrixTest` exist as `ci_lint.m`/a workflow. TS-S-02/04
describe the `matlabtest` equivalence machinery present-tense with zero repo
artifacts. Several shipped tests have no TS ids (`IRevEmbedTest`,
`IRevGradTest`, `ILoopboundTest`, `INDParamTest`, `IStructInputTest`,
`IAllocationTest`, `UStripDeadOutputIndicesTest`, `UNormTest`,
`SDerivShowcaseTest`).

### D3 — ROADMAP staleness → issue #121

R17's row asserts "rolled scalar-cost gradient/Hessian do **not** codegen"
present-tense, contradicting R20 two rows down (stale since ADR-0019/#89;
wrong R19 cross-ref). R13 "(1)(2) done" overstates — the promised README
examples list doesn't exist. R15 machinery described present-tense with no
artifacts. Backlog §2.3(7) substantially delivered by TS-S-06 but still
listed unpromoted.

### D4 — ANALYSIS staleness → issue #121

§1.3 items lack §1.5 dispositions (see D1); the B20 disposition still refers
to a guide "Limitations" section (post-#113 the note lives in §Debugging; no
Limitations section exists — code side is #116); §2.3(7) and §3.5's "reverse
needs embed-pipeline parity" are un-annotated despite delivery (R20/R16).

### D5 — residual stale ranges the sync PRs missed → issue #121

`docs/README.md:82` "B1–B16", `:83` "R1–R21", `:169` "B1-B16";
`docs/REVIEW_CONTEXT.md:7` "known bugs B1–B14"; `DESIGN.md:173`/`README.md:47`
state the `'l'` deprecation warning in the *present* tense while nothing warns
yet (R24; CI_PLAN wording is correctly *(planned)*).

---

## 5. Open-issues cross-check (as of 2026-07-04)

**Closable:** #101 (every item landed or re-homed; sole residual owned by
#108). **Accurate as-is:** #116, #115, #108 (nit: its body table still says
"#106 in review" — merged). **Need a delivered-state comment** (body
materially understates shipped work): #103 (phase 1 via #111), #84 (phase 1
via #99), #85 (ADR-0020 ratified), #83 (ADR-0021 answers the question), #80
(Gap A, Gap B rolled, CI ERT switch, ADR-0014 amendment all done), #87
(primary ask delivered: ADR-0018 + `SCasadiOracleTest`), #73 (A done, B
substantially done), #64 (approved/spec'd, zero artifacts), #56 (answered by
ADR-0016 measurement; rescope to R18/R19), #38, #11, #6 (early phases/tiers
delivered, checklists never updated). Meta-observation: docs-on-landing now
works well for *docs*, but issue bodies have no equivalent discipline — 10 of
16 open issues understate delivered state.

---

## 6. What's genuinely solid

The slimming/tape stack (`adigatorParseTape`, `adigatorForwardTapeSlice`,
`adigatorFieldSlice`, `adigatorSlimDerivBody/File`,
`adigatorPeepholeUnionCopy`) is the best code in the repo — uniformly
fail-closed with documented bail conditions, consistent error IDs, and a
derivative-leak refuse-loudly net. `adigatorScanEmbedUnsupported`
(mtree-based), `adigatorNormalizeEmbedMode`, `adigatorResolveDerLevels`,
`adigatorSlimEmbeddedDeriv`'s onCleanup discipline, and
`adigatorStripDeadOutputIndices` all check out against their callers and
printers. Test-suite fundamentals are strong: cross-mode exactness asserted
exactly (`AbsTol 0`/`isequaln`) everywhere it's claimed, fixture hygiene
uniformly clean, the ADR-0017 path-hygiene meta-guard is real and
self-compliant, MC determinism/shrink/promote mechanics sound. All 24 ADRs
resolve with correct statuses; §1.5's B1–B22 dispositions verified
reference-perfect down to test-method names; the R26/R27 batch is fully in
sync across docs, tests, ADRs, and code.

## 7. Suggested priority order

1. B23–B26 (#117) — each with its pinning test; B23 together with the
   `IShapeMatrixTest` structure assertions.
2. D1 (#118) — the binding conventions file.
3. D2/T1 (#119) — registry reconciliation; `UStructuralOpsTest` first.
4. M11 (#120) — maintainer decision.
5. #121 in themed batches: `GenFiles4*` emission bugs, test hardening,
   embedding guards, low sweep, doc staleness.
