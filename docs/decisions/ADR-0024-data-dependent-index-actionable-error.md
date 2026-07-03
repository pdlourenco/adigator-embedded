# ADR-0024 — Data-dependent indexing: actionable error, not support (B20)

## Status

Accepted — 2026-07-03 (issues #101/#108, docs/ANALYSIS.md B20). Records a
**limitation policy** (not a contract change): data-dependent indexing stays
unsupported; the fix is the *error quality*. Implementation lands with this ADR
(`lib/cadaUtils/cadaErrorSymbolicIndex.m`; `@cada/subsref.m`, `@cada/subsasgn.m`);
pinned by `tests/integration/ISymbolicIndexTest.m`.

## Context

Indexing a variable by a value computed at runtime — a **data-dependent /
"symbolic" subscript**, e.g. `ref_data(ref_idx,3)` where `ref_idx` depends on
the variable of differentiation or another runtime quantity — cannot be
handled by ADiGator's **static forward AD by source transformation**: the
derivative is a fixed nonzero vector plus a *compile-time* map of where those
nonzeros live (DESIGN §Contracts C-1/C-2). A runtime subscript makes that
sparsity map runtime-dependent, which the model cannot represent.

The tool already **errored** on this (`@cada/subsref.m`, `@cada/subsasgn.m`) —
correct per principle 1 (*a wrong derivative is worse than an error*) — but with
a cryptic message (`Cannot do strictly symbolic referencing/assignment.`) that
gave the user no path forward. There **is** a standard rewrite: replace the
dynamic subscript with a **sum weighted by logical selectors**, so the subscript
becomes a constant and the selection is done by `==`:

```matlab
v = 0;
for k = 1:size(A,1)
    v = v + (idx == k) .* A(k,:);
end
```

## Decision

**Keep the error; make it actionable.** Data-dependent indexing remains
**unsupported** (no attempt to synthesize a runtime-dependent sparsity pattern).
Replace the cryptic message with one — via a single shared helper
`cadaErrorSymbolicIndex` called from both the `subsref` (read) and `subsasgn`
(assign) sites — that (a) names the construct, (b) explains *why* static forward
AD cannot do it, (c) shows the logical-weight-sum rewrite, (d) notes that a
loop-counter index is fixed by a `for` loop (which ADiGator unrolls) rather than
a `while` loop (which it does not), and (e) points to the docs. It carries the
identifier **`adigator:symbolicIndex`** so callers/tests can catch it precisely.

This also subsumes **B19** (docs/ANALYSIS.md §1.3c): a `while`-loop counter used
as a matrix subscript is a symbolic index for exactly this reason (ADiGator does
not unroll `while` loops), so it is the same limitation with the same actionable
error — the `for`-loop pointer (d) is its natural fix.

Document the limitation and the idioms in the user guide (Limitations) and
`docs/ANALYSIS.md` B19/B20.

## Consequences

- **Easier:** a user hitting the limit gets an immediate, self-service fix
  instead of a dead-end error; the shared helper keeps the read/assign messages
  identical and maintainable; the `adigator:symbolicIndex` id makes the case
  catchable (e.g. by the R27 Monte-Carlo fuzzer, which can assert this class
  *errors* rather than miscomputes).
- **Constrained:** the tool still does not differentiate through dynamic
  indexing — by design. The logical-weight rewrite is O(size) in the indexed
  dimension, which is the user's cost to accept.
- **Revisit if:** a future mode genuinely supports runtime-dependent sparsity
  (e.g. gather/scatter with a runtime index vector and a conservative
  sparsity-union) — then the error is replaced by that path for the cases it
  covers. Not on the current roadmap.

## Alternatives considered

- **Silently pick a branch / a fixed index.** Rejected outright — it would emit
  a plausible-but-wrong derivative, the worst outcome (principle 1).
- **Auto-rewrite the dynamic index into the logical-weight sum** inside the
  tool. Rejected for now: it changes the user's computation (an O(n) loop with
  different numerics/cost) silently, and correctly bounding the index range to
  synthesize the loop is itself the hard part; making the user do the rewrite
  keeps the semantics explicit and under their control. Could be revisited as an
  opt-in transform.
- **Leave the cryptic message.** Rejected — it satisfies principle 1 but wastes
  the user's time; the fix here is purely error *quality*, cheap and high-value.
