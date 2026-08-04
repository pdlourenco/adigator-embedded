# ADR-0038 — Generated files carry a wall clock: REQ-T-06 means byte-reproducible *modulo timestamp lines*

## Status

Accepted — 2026-08-04. **Narrows the reproducibility promise** made in
[#21](https://github.com/pdlourenco/adigator-embedded/issues/21) for generated
wrapper and derivative files; the embedded **data functions** keep the stricter
promise unchanged. Arises from
[#200](https://github.com/pdlourenco/adigator-embedded/issues/200).

## Context

#21 removed the wall-clock line from the header written by
`structure_to_embed_mfile`, so that regenerating a data function twice from
identical inputs produced byte-identical output. The comment recording that is
still in the file. Byte-reproducibility is worth having: it makes regeneration
a no-op in a diff, so a reviewer can tell "this was regenerated" from "this
changed".

#200 then required every generated file to answer *what produced this, and is
it still current* — the questions a derivative found in a firmware repository
cannot otherwise answer. Two of the three parts of that answer are static: the
tool version and a generation id over the options and the source closure. The
third, **when**, is not.

These pull in opposite directions, and the conflict was initially resolved by
accident rather than decision: #200 simply reintroduced a timestamp, leaving
the #21 comment in the tree silently contradicted and `docs/CI_PLAN.md`
REQ-T-06 claiming a property the generator no longer had. That is the part
worth an ADR — not the timestamp itself, but the fact that a stated
verification promise moved.

## Decision

**Generated wrapper and derivative files carry an ISO 8601 UTC timestamp.**
REQ-T-06 is restated as *byte-reproducible modulo timestamp lines*, verified by
TS-I-03 (`IReproTest`), which strips date-bearing lines and compares the rest.

**Embedded data functions keep the #21 property unchanged** — no timestamp,
byte-identical on regeneration.

Rejected alternatives:

- **Drop the timestamp, keep only the id.** Fully restores #21 and keeps
  byte-comparison tests simple. Rejected because it answers "when" with "read
  the file's mtime", which is exactly the information lost when a generated
  file is copied into a firmware tree, committed, or shipped — the situation
  the header exists for. The id tells you *whether* an artifact is stale; only
  the timestamp tells you *how old* the generation is when you are triaging one.
- **Timestamp in classic mode only.** Keeps the embedded path — where
  reproducible builds matter most — byte-reproducible. Rejected because the
  header would then mean different things in different modes, which every
  future reader has to learn, and it splits the fixture story in two for a
  property TS-I-03 already handles.

## Consequences

- Any test comparing generated files byte-for-byte must strip timestamp lines.
  Two already do (`IReproTest`, `IEmbedSlimTest`). **Strip only the timestamp**
  — an earlier attempt discarded the whole header and thereby stopped
  comparing the generation id, which hid a real defect (two runs emitting
  identical code under different ids) until the narrower comparison was
  restored.
- Regenerating the committed `tests/fixtures/gen_dialect` captures always
  produces a diff, even when the generated code is identical. This is the
  `docs/` PDF-churn pattern and is tolerable here only because that recapture
  is a deliberate, occasional act rather than something CI does on every push.
  If it ever becomes automatic, revisit this ADR.
- A generation id must never be computed over a file that carries a timestamp,
  or the id inherits the non-determinism. This is not hypothetical: the
  Hessian path differentiates twice and feeds its own generated output back in,
  which made second-order ids change on every run until one stamp per run was
  threaded through (`opts.inherited_stamp`).

## Verified by

- TS-I-03 (`IReproTest`) — regeneration is byte-identical modulo timestamp lines.
- TS-U-21 (`UGenerationStampTest`) — the stamp itself is deterministic, and
  independent of path, closure order, line endings and flag spelling.
