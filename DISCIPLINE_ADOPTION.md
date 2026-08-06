# Discipline adoption record

This file records this repository's adoption of the disciplined agentic coding
practices from the [disciplined-project-seed](https://github.com/pdlourenco/disciplined-project-seed).
It exists so that "has this been considered?" is answerable from the repo rather
than by re-running an investigation. Its absence is why the seed's 0.4.0 and
0.4.1 releases went untriaged here for a month ([#242](https://github.com/pdlourenco/adigator-embedded/issues/242)).

**A dropped row with a reason is this file working.** Most of what follows is a
transcription of decisions already taken and reasoned about in
[`docs/analyses/SEED_ADOPTION_ANALYSIS.md`](docs/analyses/SEED_ADOPTION_ANALYSIS.md)
§3; the point of moving them here is that an analysis is an immutable snapshot
and this is a living record.

## Provenance

- **Seed:** <https://github.com/pdlourenco/disciplined-project-seed>
- **Adopted at:** v0.4.1 (`49860ad`) — previously assessed at the 2026-07-06 state
- **Adoption date:** 2026-07-06 (initial), 2026-08-04 (first flow-down triage)
- **Profile:** fork + catch-up sync — this repo is a fork of upstream ADiGator
  with its own established doc set, so the seed is a source of conventions
  rather than a scaffold. Several artifacts below were converged on
  independently *before* the seed was read, and at least one travelled the
  other way.

## Per-artifact adoption table

| Seed artifact | Status | Notes |
|---|---|---|
| `docs/SPEC.md` | adapted | folded into `DESIGN.md` §Contracts (C-1..C-5) — one implementation, so a separate contract doc would duplicate rather than separate |
| `docs/DESIGN.md` | adopted | carries both rationale and the binding contracts |
| `docs/ROADMAP.md` | adopted | |
| `docs/CONTRIBUTING.md` | adopted | |
| `docs/REVIEW_CONTEXT.md` | adopted, extended | §"Evidence discipline" is a downstream invention with no seed counterpart — see the backport log |
| `docs/LABELS.md` + `.github/labels.yml` | dropped | ~210 lines + a reconciliation workflow to prevent label drift across many contributors; this repo applies labels by hand (`SEED_ADOPTION_ANALYSIS` §3.3) |
| `.github/branch-protection.yml` + apply script | dropped | three drift-detection mechanisms, a scheduled workflow and a PAT secret for a problem a solo fork does not have (§3.3) |
| `docs/plans/` | dropped | `ROADMAP.md` carries phasing; four documents where two suffice, below the multi-phase-in-flight threshold (§3.3) |
| `docs/decisions/` | adopted | ADR-0001..0038 |
| `docs/analyses/` | adopted | dated snapshots **plus** one canonical register (`ANALYSIS.md`, the `Bnn` bug catalogue) — the seed's rule-3 exception, marked as such |
| `CLAUDE.md` | adopted | |
| CI workflow (`.github/workflows/ci.yml`) | adapted | the seed's markdown/YAML-lint baseline knows nothing about MATLAB; `CI_PLAN.md` is the project-specific design (§3.3) |
| `STRUCTURE.md` | dropped | inherited upstream layout, stable; a paragraph in `DESIGN.md` covers it (§3.3) |
| `RISKS.md` | dropped | the material risk — silently-wrong generated derivatives — is in `ANALYSIS.md` and *pinned by tests* in `CI_PLAN.md`, a stronger control than a prose register (§3.3) |
| `audit-placeholders.py` + placeholder convention | dropped | real documents were written directly rather than filling a template tree, so there are no placeholders to police (§3.3) |
| Agent PR lifecycle / two-session workflow (ADR-0009) | adopted | `CLAUDE.md` §5 + `CONTRIBUTING.md` §"Two-session authoring / review workflow" |
| release-as-code (ADR-0015) | converged independently | landed here as ADR-0031 before the seed's version was read |
| State-based docs rule | adopted | `REVIEW_CONTEXT.md` principle 8 |
| Known-bug lifecycle, two mechanisms (ADR-0012) | adopted | `KnownIssue` / `assumeFail` + the `Bnn` register |
| Traceability matrix (REQ × TS ids) | converged independently | `CI_PLAN.md`; predates the seed's version |
| `docs/analyses/README.md` — the four rules | adopted 2026-08-04 | codifies existing practice; the `ANALYSIS.md` register exception is called out |
| `CONTRIBUTING.md` §"Reviewing an open PR" (ADR-0008) | adapted 2026-08-04 | output channel defaults to a single PR comment, not inline comments — matches what this repo actually does |
| Deferral-sweep step | adopted 2026-08-04 | attached to ROADMAP-row closure rather than a phase ritual (this repo has no phase-completion ceremony) |
| Drift-hardening doctrine (ADR-0011) | adapted 2026-08-04 | the three-line doctrine only; the full contract-gate catalogue is more than this repo needs |
| PR-template randomized-campaign row (ADR-0014 floor) | adopted 2026-08-04 | the campaign already existed and is correctly non-gating; what was missing was the floor |
| `DISCIPLINE_ADOPTION.md` (this file) | adopted 2026-08-04 | |

## Sync log (append-only)

| Date | Seed ref range | Taken | Skipped (reason) |
|---|---|---|---|
| 2026-07-06 | initial assessment (pre-0.4.0) | the §3.1/§3.2 slice — see the table above and `SEED_ADOPTION_ANALYSIS.md` | the §3.3 drops, each with a recorded reason |
| 2026-08-04 | v0.4.0 (2026-07-21) .. v0.4.1 (`49860ad`, 2026-07-22) | all six untriaged items: analyses README, reviewer-invocation convention, deferral sweep, drift doctrine, campaign-row floor, this file ([#242](https://github.com/pdlourenco/adigator-embedded/issues/242)) | nothing skipped — every 0.4.x item was either already present, already deliberately dropped, or taken |

## Backport log

Conventions this project invented, or convention failures it documented,
proposed upstream to the seed.

| Date | What | Upstream issue / PR |
|---|---|---|
| 2026-08-04 | `REVIEW_CONTEXT.md` §"Evidence discipline — fact, or artifact of the measurement?" — six tells that a measurement is an artifact rather than a result, written as generic body + `### Instances (this project)` so lifting it upstream is a deletion rather than a rewrite. No seed counterpart exists. ([#238](https://github.com/pdlourenco/adigator-embedded/pull/238), [#241](https://github.com/pdlourenco/adigator-embedded/issues/241)) | not yet proposed |
| 2026-08-04 | Red flag: *a guard whose failure direction is documented but not asserted* — same shape as the seed's generic red-flag categories, instantiated here by the #200 embed-mode guard. ([#241](https://github.com/pdlourenco/adigator-embedded/issues/241) Gap C) | not yet proposed |

**On why these are worth proposing.** Both came out of *agent-to-agent* review,
where reviewer and author share reasoning habits and therefore share blind
spots — several instances behind them are reviewer-side, and one inference was
repeated by the reviewer *as* review. A shared-blind-spot failure survives
review by construction, which makes this class arguably more valuable at the
seed's scale than at this repo's.
