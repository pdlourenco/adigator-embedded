# ADR-0026 — Inherited solver-integration wrappers are kept but flagged, not brought to parity

## Status

Accepted — 2026-07-08

## Context

The five `adigatorGenFiles4{Fminunc,Fsolve,Fmincon,Ipopt,gpops2}` commands are
convenience wrappers carried over from upstream ADiGator (Weinstein/Rao,
GPL-3.0). They generate solver-ready derivative files (objective gradient,
constraint Jacobian, Lagrangian Hessian) for MATLAB's optimization toolbox,
IPOPT, and GPOPS II.

They predate the v1.5 embedded fork and were never brought forward to its
capabilities. Relative to the core generators (`adigator`,
`adigatorGenJacFile`, `adigatorGenHesFile`, `adigatorGenDerFile_embedded`) they
emit **host-only** files (the classic runtime-`load`/global mechanism) and do
not support `EMBED_MODE`, code generation (MATLAB / Embedded Coder), the `PATH`
option, the `nonzeros` output form, or reverse mode. They also build a partial
`opts` (only `.overwrite`) rather than starting from `adigatorOptions()`, and
carry less test depth. The maintainer is not interested in this family and does
not intend to invest in it; the concern is that it silently rots — it rode along
unnoticed through the M6 hygiene sweep (#121, PR #155), for instance.

## Decision

**Keep the wrappers but flag them as not-at-parity**, rather than remove them or
invest to bring them up to the embedded pipeline. Concretely:

- A header banner on each of the five generators
  (`util/adigatorGenFiles4*.m`) stating: inherited-upstream, host-only, does not
  support the embedded features, not maintained/tested to the core generators'
  depth, prefer the core generators for embeddable derivatives, retained for
  upstream compatibility, and pointing to this ADR and issue #156.
- A note in the user guide: a grouped "Solver-Integration Wrappers (Inherited
  from Upstream)" subsection ahead of their §5 documentation, and a one-line
  flag at the GPOPS II section.
- Issue #156 tracks the family and the parity gap.

No behaviour change: the wrappers still work exactly as before.

## Consequences

- Users are told plainly, in the code and the guide, that these are host-only
  and outside the fork's embedded feature set — no surprise when they fail to
  code-generate.
- Upstream drop-in compatibility is preserved: code written against stock
  ADiGator that calls these wrappers keeps working.
- The rot risk is documented rather than eliminated: they still ride along in
  lint/test/sweeps, so future refactors (like M6) still touch them. Accepted as
  the price of keeping them.
- **Revisit when:** (a) the fork formally drops the goal of upstream drop-in
  compatibility — then removal (this ADR's rejected alternative) becomes the
  cleaner choice; or (b) a user need arises for embeddable solver wrappers —
  then they would be rebuilt on the core generators, not patched. Any
  bring-to-parity or removal work is deferred until after the roadmap's
  code-quality/test/optimization/documentation phases (maintainer direction,
  2026-07-08); see the related deferred hygiene note in #156.

## Alternatives considered

- **Remove them from the repo.** Ends the rot and the ongoing maintenance
  burden outright. Rejected for now: removal cascades across the guide (§5 +
  §12), `util/Contents.m`, the `adigatorOptions` docs, `docs/README.md`, and the
  four `examples/optimization/{fminunc,fsolve,ipopt,fmincon}Ex/` directories,
  and it breaks drop-in compatibility for users migrating from stock ADiGator.
  Kept on the table as the revisit path if upstream compatibility is dropped.
- **Bring them to embedded parity.** Add `EMBED_MODE`/codegen/`PATH`/`nonzeros`
  support and full option handling. Rejected: large investment in a family the
  maintainer does not want, and the right shape would be to regenerate them on
  the core embedded generators rather than retrofit the inherited code.
- **Do nothing (leave them undocumented).** Rejected: the whole problem is that
  their host-only, not-at-parity status is invisible, so they rot and mislead;
  a flag is the minimum that addresses that.
