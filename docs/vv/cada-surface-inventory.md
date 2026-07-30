# `@cada` / `@cadastruct` shipped-surface overload inventory

**Purpose.** This is the denominator for the V&V coverage floor (ADR-0032) and
the worklist for the value-oracle campaigns (#38 FD-Hessian oracle, #103
option×operation oracle matrix). It classifies **every** overload in the two
derivative-computation classes so the floor targets the *shipped* surface — the
operations a user can actually differentiate through — rather than raw line
counts, and so the oracle work goes where a wrong derivative can originate.

**Why these two classes.** `lib/@cada` holds the per-operation
forward/reverse derivative *rules*; `lib/@cadastruct` holds the struct / remap /
union layer. A wrong derivative originates here, not in the downstream emitter
(`embedding/`, `util/`) — see ADR-0032. Coverage on this path is therefore the
correctness-critical measurement, and it is the *least*-covered part of the tree
(`@cada` ~40%, `@cadastruct` ~17% full-suite line coverage).

**Method.** Coverage percentages are full-suite line coverage
(unit + integration + system + montecarlo) from `ci_coverage_folders.m`.
Classification is evidence-based (each overload's primary path was read):

- **supported-op** — a user-facing operation implementing a real derivative
  rule, reachable by MATLAB class dispatch when user code calls that function.
  Untested coverage here is a **genuine V&V gap**.
- **guarded-unsupported** — the whole-op path errors out for the shipped
  surface; 0% coverage is acceptable, an error-assert test is the most that is
  owed.
- **machinery** — engine plumbing (constructors, printers, analyzers, remap /
  union / overmap helpers, private derivative kernels). Exercised indirectly.
- **dead** — unreachable / vestigial (removal candidate).

**Headline result.** There is **no dead code** and, across `@cada`, **no
whole-op-unsupported code**: every `@cada` math/query overload is a real
supported operation, and every `error(...)` in them is a defensive *sub-case*
guard inside an otherwise-supported op (e.g. `inv` "Can only Invert Square
Matrices", `sub2ind` "only meant to be used on known numeric objects", `repmat`
"purely symbolic dimension"). So the low coverage on this path is almost
entirely **supported-but-untested** — the real V&V hole — not code that is
correctly excluded. Coverage alone is necessary, not sufficient: these ops must
be exercised **against a value oracle**, which is what #38 / #103 supply.

## The V&V gap worklist (supported ops, zero / low coverage)

These are the correctness-path operations with no (or thin) test exercise. They
are the targets whose oracle coverage **raises** the ADR-0032 floor. Two natural
clusters let a few fixtures light up many files at once:

- **Interpolation family** — `@cada/interp1`, `@cada/interp2`, `@cada/ppval`,
  `@cada/adigatorEvalInterp2pp` (interp2 → `adigatorGenInterp2pp` /
  `adigatorEvalInterp2pp`; interp1 → `ppval`). One interp1 + one interp2 fixture
  through the FD oracle covers all four.
- **Matrix-inverse family** — `@cada/inv`, `@cada/mldivide`, `@cada/mrdivide`
  all drive the untested private kernel `@cada/private/cadainversederiv`. One
  matrix-inverse / linear-solve fixture covers the op and the kernel together.

| bucket | zero-coverage supported ops | thin (<25%) supported ops |
|---|---|---|
| `@cada` | cross, repmat, interp1, interp2, ppval, adigatorEvalInterp2pp, prod, inv, nnz, sub2ind, isequalwithequalnans | numel (6.8%), min (10.5%), isempty (17.9%), isequal (22.2%), reshape (22.9%) |
| `@cadastruct` | horzcat, vertcat, repmat, reshape, ppval, size, transpose, ctranspose, length, struct | subsref (20.6%) |
| untested private kernels | `@cada/private/cadainversederiv` (← inv/mldivide/mrdivide), `@cada/private/cadamtimesderivvec` (← vectorized mtimes), `@cada/private/cadaRemoveRowsCols` (← FOR-loop binary-op printing) | — |

`@cadastruct/subsasgn` (29.7%) is also a partial gap. The `@cadastruct`
concat/reshape/transpose ops are reachable when user code manipulates a
struct-valued differentiated variable inside a loop or overmap path; they are
untriggered by the current corpus, not unsupported.

## Guarded / unsupported (0% acceptable)

- **`@cadastruct/isequal`** — header states the logic "has not been coded to
  allow users"; errors for `nargin>2` and tempfunc-internal calls. Not
  user-facing on the shipped surface; owed at most an error-assert test.

(No `@cada` file is whole-op unsupported.)

## Removal candidates (dead)

**None**, at any confidence. Every math/query overload is named after a real
MATLAB function and is auto-dispatched when user code calls it (reachable by
construction). Every private kernel and `cada*` helper has an identified caller
(e.g. `cadainversederiv` ← inv/mldivide/mrdivide; `cadacreatearray` ←
zeros/ones/eye/…; the `@cadastruct` private printers ← subsref/subsasgn). The 0%
figures reflect untriggered test paths, not vestigial code.

## Latent defects found while classifying (now fixed)

Reading the rarely-taken `RUNFLAG==2 && nameloc<=0` derivative-naming branch of
the `@cadastruct` concat/transpose ops surfaced real defects on **fail-loud edge
paths** (they throw on undefined names, they do not silently corrupt a
derivative). The inventory found three; the fix sweep found **two more** by
comparing against the sibling overloads:

- `@cadastruct/vertcat.m`, `ctranspose.m`, and — not caught by the inventory —
  `horzcat.m`: the `nameloc<=0` arm references `NDstr` (never assigned in the
  function) and `yid` (not in scope there).
- `@cadastruct/subsref.m` — the same line in the **main** `subsref` body, the
  most-used overload of the class. Subtler: the file *does* assign `NDstr`, but
  inside the `ForSubsRef` **subfunction**, so a per-file "is it assigned?" check
  misses it. (`subsasgn.m` was checked and is clean.)
- `@cadastruct/repmat.m` — a misspelled empty-eval flag field.

These are exactly the class of defect a coverage hole hides — and the branch is
**user-reachable** (`hlp([s; s]')` throws pre-fix - it is the concat result
that is the unnamed intermediate), so they were fixed, not guarded, using
`DERNUMBER` - the value the deleted `NDstr` stood for - and deliberately *not*
the `NVAROFDIFF` spelling three siblings in the class use (see ANALYSIS §1.3g for
why that distinction is principle-1 relevant, and for the open follow-up to
harmonize those three). Logged in the canonical bug catalog as
**B29–B31, B33–B34** (`docs/analyses/ANALYSIS.md` §1.3g, disposition §1.5) and
pinned by `tests/integration/IStructArrayNamingTest.m`, so the catalog stays the
single source of truth.

## Full classification

### `lib/@cada`

| category | files (coverage%) |
|---|---|
| supported-op — zero | cross (0), repmat (0), interp1 (0), interp2 (0), ppval (0), adigatorEvalInterp2pp (0), prod (0), inv (0), nnz (0), sub2ind (0), isequalwithequalnans (0) |
| supported-op — thin | numel (6.8), min (10.5), isempty (17.9), isequal (22.2), reshape (22.9), sparse (28.3), size (32.4), length (39.0), mrdivide (40.1) |
| supported-op — moderate/good | transpose (47.0), sum (47.6), subsasgn (47.9), mldivide (49.2), diag (51.3), max (51.9), subsref (55.2), mpower (56.8), colon (57.1), nonzeros (62.5), vertcat (66.7), mtimes (71.6), horzcat (86.3) |
| machinery | private/cadamtimesderivvec (0), private/cadainversederiv (0), private/cadaRemoveRowsCols (0), cadacreatearray (27.4), adigatorAnalyzeForData (33.9), cadaPrintReMap (44.2), cada (56.5), cadaUnionVars (58.0), cadabinarylogical (62.4), cadabinaryarraymath (64.7), cadaOverMap (65.1), cadaunarylogical (66.7), cadaEmptyEval (68.2), adigatorStructAnalyzer (72.2), adigatorPrintOutputIndices (82.7), private/cadamtimesderiv (82.7), adigatorVarAnalyzer (83.5), cadaunarymath (91.8), private/cadaRepDers (93.8), private/cadaunion (100), private/cadaCancelDerivs (100), cadaCheckForDerivs (100) |

The four shared kernels `cadabinaryarraymath` / `cadabinarylogical` /
`cadaunarymath` / `cadaunarylogical` carry the actual `+ - .* ./ sin cos exp …`
derivative rules; they are classified machinery (not user-facing files) but are
well covered (62–92%), so not a gap either way.

### `lib/@cadastruct`

| category | files (coverage%) |
|---|---|
| supported-op — zero | horzcat (0), vertcat (0), repmat (0), reshape (0), ppval (0), size (0), transpose (0), ctranspose (0), length (0), struct (0) |
| supported-op — partial | subsref (20.6), subsasgn (29.7) |
| guarded-unsupported | isequal (0) |
| machinery | cadaPrintReMap (0), cadaUnionVars (0), private/adigatorPrintStructAsgn (0), private/cadaloopstructderivref (0), private/cadaloopstructfuncref (0), cadaCheckForDerivs (0), cadaOverMap (4.6), adigatorVarAnalyzer (43.8), adigatorPrintOutputIndices (59.1), adigatorStructAnalyzer (80.0), cadastruct (94.4) |
