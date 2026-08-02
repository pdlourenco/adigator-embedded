# ADR-0037 — The inherited `adigatorGenFiles4*` family is deprecated: shipped for upstream continuity, not maintained

## Status

Accepted — 2026-08-01. **Supersedes [ADR-0026](ADR-0026-inherited-solver-wrappers-not-at-parity.md)**,
which flagged this family as *not-at-parity* with explicitly "no behaviour
change". The family and the flag both stay; what changes is the **promise**.
Tracked by [#156](https://github.com/pdlourenco/adigator-embedded/issues/156).

## Context

The five `adigatorGenFiles4{Fminunc,Fsolve,Fmincon,Ipopt,gpops2}` wrappers come
from upstream ADiGator (Weinstein/Rao, GPL-3.0). They emit **host-only**
derivative files through the classic runtime-`load`/global mechanism and do not
support `EMBED_MODE`, code generation, `PATH`, the CSC output form, or reverse
mode. ADR-0026 catalogued that gap and chose to keep them with a header banner
plus a user-guide note, on the grounds that removal would break drop-in
compatibility for users migrating from stock ADiGator.

That decision holds up. What has changed is that the fork now has an **explicit
embeddability bar for what it ships**, and this family sits outside it.

Two things forced the question:

1. **The example corpus is being held to "the input function must ERT-codegen."**
   That bar came out of [#217](https://github.com/pdlourenco/adigator-embedded/issues/217)'s
   aftermath: a derivative that fails to code-generate is only evidence about the
   *tool* if the user function code-generates in the first place — a precondition
   that was nowhere written down, and whose absence produced a wrongly-filed
   issue (#223, retracted). Auditing every shipped example against it forces a
   verdict on the four `examples/optimization/{fmincon,fminunc,fsolve,ipopt}Ex/`
   directories, which exist only to demonstrate this family.
2. **"Not at parity" does not tell a user what they need to know.** It describes
   a present-tense gap. It does not say whether the gap will ever close, or
   whether the feature will still be there next release. A user choosing between
   `adigatorGenFiles4Fmincon` and rolling their own on
   `adigatorGenJacFile`/`adigatorGenHesFile` cannot make that call from ADR-0026.

The fork is named `adigator-embedded`. A host-only family that no one maintains
is not part of that product, and saying so plainly is more useful to a user than
carrying it in a state that looks supported.

## Decision

**The `adigatorGenFiles4*` family is deprecated.** It is shipped for
**continuity with the upstream repository**, is **not maintained**, and its
**functionality may be reduced or removed in a future release**.

Concretely:

- **Wording escalates** on the five `util/adigatorGenFiles4*.m` banners and in
  the user guide: from *"not at parity"* (a present-tense gap) to *"deprecated —
  retained for upstream continuity, unmaintained, may lose functionality"*.
- **The four `*Ex` examples are tagged deprecated** and carry the same statement,
  pointing at the core generators for anyone writing new code.
- **They are exempt from the shipped-example embeddability bar.** An example that
  exists to demonstrate a deprecated host-only family is not expected to
  ERT-codegen, and its failing to do so is not a defect. This exemption is the
  operative half of the decision: without it, the audit has no principled way to
  close those four rows.
- **No new work is undertaken on the family** — not parity, not the deferred
  option-hygiene gap (#156), not test depth. Incidental churn from repo-wide
  sweeps is tolerated, not sought.
- **They keep working today.** Deprecation is a statement about the future and
  about maintenance, not a behaviour change in this release.

## Consequences

- **A user can now make an informed choice.** "Deprecated, unmaintained, may
  disappear" is actionable in a way "not at parity" is not: write new code
  against the core generators, and treat existing `Files4*` code as carrying
  migration risk.
- **Removal is on the table without re-litigating the deprecation.** ADR-0026's
  revisit condition — the fork formally renouncing upstream drop-in
  compatibility — is dropped; this ADR is the notice. That is the substantive
  difference from ADR-0026, whose bar was never going to be cleared explicitly,
  leaving the family in indefinite limbo.

  A removal PR still records its **own** mechanics, because this ADR did not
  weigh them: hard delete versus an erroring stub that names the replacement,
  whether the four `*Ex` directories go with it, how guide §5/§12 are
  restructured, and the fate of `tests/integration/IGenFiles4Test.m`. And it is
  still surfaced under `CLAUDE.md` §4 like any other removal of shipped
  entry points. Deprecating a family is not the same decision as removing it,
  and this ADR only makes the first.
- **The example audit can close.** Four of the corpus's non-embeddable rows are
  resolved by scope rather than by fixes that would never be made.
- **The rot risk is unchanged and now openly accepted.** They still ride along in
  lint and sweeps; ADR-0026 already priced this in.
- **CHANGELOG carries it**, because a deprecation is a user-visible policy change
  even when no code changes.
- **Upstream compatibility degrades over time by design.** Code migrating from
  stock ADiGator keeps working now and has no guarantee later. That is the
  trade being made deliberately, where ADR-0026 declined to make it.

**Revisit when:** a concrete user need for *embeddable* solver-integration
wrappers appears. The answer then is to build them on the core generators — as
ADR-0026 already said — not to revive this family. Or when the maintenance cost
of carrying them exceeds the continuity benefit, at which point removal proceeds
under this ADR.

## Alternatives considered

- **Keep ADR-0026's "flagged, not-at-parity" wording.** Cheapest, and the flag
  already exists. Rejected: it leaves the family in a state that reads as
  supported, and its revisit condition (the fork formally renouncing upstream
  drop-in compatibility) is a bar nobody would ever explicitly clear — so the
  ambiguity would persist indefinitely. It also gives the example audit no
  principled way to close the four `*Ex` rows.
- **Remove the family now.** Ends the rot outright and is where this is
  ultimately heading. Rejected as premature: removal cascades across the guide
  (§5 and the §12 walkthroughs), `adigatorOptions.m`'s docstring,
  `docs/DESIGN.md`, `tests/integration/IGenFiles4Test.m` and the four example
  directories — and it converts a soft migration into a hard break with no
  notice period. Deprecation is that notice. (ADR-0026's version of this list
  named `util/Contents.m`, which does not exist — the repo's `Contents.m` is at
  the root and carries no `Files4*` entry.)
- **Bring them to embedded parity.** Rejected for the reasons in ADR-0026,
  unchanged: a large investment in a family the maintainer does not want, and
  the right shape would be a rebuild on the core generators rather than a
  retrofit.
- **Deprecate the wrappers but keep the examples untagged.** Rejected: the
  examples are the most likely first contact a user has with the family, so an
  untagged example is exactly where the wrong impression forms. It would also
  leave the four audit rows unresolved, which is half the reason this decision
  is being made now.
