# ADR-0015 — `@cada` benign reads declare the transformation globals only on the paths that use them

## Status

Accepted — 2026-06-25. Implements R11 / issue #54 (the `@cada` follow-up to the
B16 transformation-state hygiene of [ADR-0011](ADR-0011-adigator-error-path-cleanup.md)).
No change to `docs/DESIGN.md` §Contracts or `adigatorDerivativeConventions.m`.

## Context

Every `@cada` overload opens with `global ADIGATOR` (and several with
`ADIGATORFORDATA`/`ADIGATORDATA`). In MATLAB a `global X` declaration **creates
an empty `X` if it does not already exist**. So after a transformation finishes
and `adigator` has cleared the four transformation-state globals (B16,
ADR-0011), *any* code that touches a returned `cada` object re-creates an empty
`ADIGATOR` in the workspace.

This is benign for correctness — the empty name carries no state and the next
transform repopulates it — but it means "a successful transform leaves **no**
transformation global in `who('global')`" is not achievable while a caller reads
the returned object. The trigger is concrete: `adigatorGenJacFile` reads
`adiout.func.size` / `adiout.deriv.nzlocs(:,2)` / `x.deriv.vodname` off the
returned objects, and each access runs `@cada/subsref` → `global ADIGATOR`.

#51 settled the interim B16 invariant as **"no *populated* transformation global
survives"** (assert empty-or-absent) precisely because this empty re-registration
was unavoidable then. The strict-absent form was deferred to this ADR.

## Decision

Declare the transformation globals **only on the code paths that use them**, in
the handful of `@cada` methods a *caller* invokes on a returned object — the
benign read paths — so those paths return before any `global` declaration:

- **`subsref`** — a leading `'.'` subscript is always a benign property read
  (`.id`/`.func`/`.deriv`); it returns a plain value, so the whole chain
  (`.func.size`, `.deriv.nzlocs(:,2)`, …) is served by the builtin before
  `global ADIGATOR`. The overloaded `()` reference path (user-code indexing
  *during* a transformation) still declares the global and is unchanged.
- **`size` / `length`** — a fast path guarded by `isempty(who('global','ADIGATOR'))`
  (which does **not** create the global) returns the plain size/length of the
  stored `func.size` shape when no transformation is in progress.
- **`isempty`** — the `global` declaration moves inside the
  `adigatortempfunc`-caller branch that uses it; the external `y = false` branch
  no longer declares it.
- **`numel`** already routed external calls to `y = 1` before any `global`; left
  as is.

The other ~45 `@cada` files that declare `global ADIGATOR` are arithmetic /
structural overloads invoked **only during a transformation** (when `ADIGATOR`
is already populated), so they never re-register and are intentionally left
untouched — the scope is the caller-facing read methods, not the whole layer.

`who('global','ADIGATOR')` is chosen over a `dbstack` caller-name heuristic (the
existing `numel`/`size` workspace check) because it is true in *every*
transformation context — direct or nested through another `@cada` method —
whereas a "called from `adigatortempfunc`" test would misclassify a `size`/
`length` reached via an intermediate method and take the benign branch *during*
a transformation, which would be wrong.

## Consequences

- A successful transform now leaves **no** transformation global; the #51 B16
  hygiene asserts tighten from empty-or-absent to strict-absent
  (`UCoreErrorHygieneTest`, `MCSmokeTest/successLeavesNoOpenHandles`).
- The benign fast paths are behaviour-identical to the existing branches for the
  reads they serve; verified by the full unit + integration + Monte-Carlo
  suites passing unchanged (no derivative-shape change — `subsref`/`size`/
  `length` are exercised constantly during generation).
- The `who('global',…)` guard adds one cheap lookup per external `size`/`length`
  on the no-transformation path; the transformation path is unchanged.
- **Revisit** if: a future `@cada` read method is added that a caller invokes on
  a returned object (it must follow the same declare-on-use pattern); or if the
  `func.size` storage shape ever becomes >2-D (the `size`/`length` benign value
  computation assumes the 2-D fold).

## Alternatives considered

- **Keep the #51 interim invariant ("no *populated* global").** Rejected as the
  end state: it permanently tolerates a stray empty name in `who('global')`,
  weakening the hygiene guarantee and leaving `MCSmokeTest` unable to assert
  strict cleanliness. Acceptable only as the interim it was.
- **`dbstack` caller-name gating** (extend the existing `numel`/`size`
  `adigatortempfunc` heuristic to `length`/`isempty`). Rejected: it is fragile
  (depends on the generated temp-function name) and, worse, *unsound* for
  methods reachable through an intermediate `@cada` method during a
  transformation — the immediate caller would not be the tempfunc, so it would
  wrongly take the benign branch and corrupt the tape. The existence check is
  sound in all contexts.
- **Clear the stray empty `ADIGATOR` again at the end of every wrapper
  generator.** Rejected: it chases the symptom (re-clearing after each benign
  read) instead of the cause, is easy to forget at a new call site, and does
  nothing for a caller outside the generators that reads a returned object.
- **Touch all 54 files that declare `global ADIGATOR`.** Rejected as
  unnecessary: only the caller-facing read methods can re-register post-
  transformation; the arithmetic/structural overloads run solely while
  `ADIGATOR` is populated. Restructuring them would be churn with no hygiene
  benefit and non-zero risk to the hot transformation path.
