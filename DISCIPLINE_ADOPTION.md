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
- **Adopted at:** v0.4.1 (`49860ad`) — previously assessed against the seed as
  it stood on **2026-06-17**
- **Adoption date:** 2026-06-18 (initial — `c351732` CLAUDE.md, `2dbdfb3`
  REVIEW_CONTEXT.md), 2026-08-04 (first flow-down triage)
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
| `docs/ROADMAP.md` | adapted | inlined; no separate `plans/` tree (`SEED_ADOPTION_ANALYSIS` §3.2) |
| `docs/CONTRIBUTING.md` | adapted | heavily slimmed — the seed's four-tier CI section dropped in favour of `CI_PLAN.md` (§3.2) |
| `docs/REVIEW_CONTEXT.md` | adopted, extended | §"Evidence discipline" is a downstream invention with no seed counterpart — see the backport log |
| `docs/LABELS.md` + `.github/labels.yml` | dropped | ~210 lines + a reconciliation workflow to prevent label drift across many contributors; this repo applies labels by hand (`SEED_ADOPTION_ANALYSIS` §3.3) |
| `.github/branch-protection.yml` + apply script | dropped | three drift-detection mechanisms, a scheduled workflow and a PAT secret for a problem a solo fork does not have (§3.3) |
| `docs/plans/` | dropped | `ROADMAP.md` carries phasing; four documents where two suffice, below the multi-phase-in-flight threshold (§3.3) |
| `docs/decisions/` | adopted | ADR-0001..0038 |
| `docs/analyses/` | adopted | dated snapshots **plus** one canonical register (`ANALYSIS.md`, the `Bnn` bug catalogue) — the seed's rule-3 exception, marked as such |
| `CLAUDE.md` | adapted | slimmed; §3 retargeted from the seed's cross-boundary-contract language to this repo's derivative contracts (§3.1) |
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
| `.github/pull_request_template.md` + issue templates | adapted | PR template present and project-specific; no issue templates (§3.2 rates both optional) |
| Cheap doc-lint CI jobs | dropped | §3.2 offered them as a borrow; not taken — `ci.yml` is MATLAB-centric and a markdown linter would gate on style this repo does not enforce |
| `scripts/local-ci.sh` | converged independently | `tests/ci_local.m`, in MATLAB rather than shell |
| `.claude/settings.json` + session-start hook | dropped | not adopted; session context comes from `CLAUDE.md`, which every session reads anyway |
| "Expensive required checks" cost patterns (0.4.0) | adapted | the concern is real here (MATLAB-licensed CI) and is already answered by `CI_PLAN.md`'s single-install pipeline (ADR-0004) and the local pre-push gate |
| `DISCIPLINE_ADOPTION.md` (this file) | adopted 2026-08-04 | |

## Sync log (append-only)

| Date | Seed ref range | Taken | Skipped (reason) |
|---|---|---|---|
| 2026-06-18 | initial assessment (pre-0.4.0), seed as of 2026-06-17 | the §3.1/§3.2 slice — see the table above and `SEED_ADOPTION_ANALYSIS.md` | the §3.3 drops, each with a recorded reason |
| 2026-08-04 | v0.4.0 (2026-07-21) .. v0.4.1 (`49860ad`, 2026-07-22) | the six items [#242](https://github.com/pdlourenco/adigator-embedded/issues/242) enumerated — analyses README, reviewer-invocation convention, deferral sweep, drift doctrine, campaign-row floor, this file — **plus** 0.4.1's correction to the in-flight ADR-collision scan (`in:files` is a no-op qualifier), applied to `docs/decisions/README.md` | nothing skipped. The `in:files` fix was initially missed: #242 triaged the seed CHANGELOG's `### Added` entries and not its `### Fixed` ones, so a live broken command in this repo went unnoticed while the caveat written to accompany it (*"a recorded command is a claim, not a fact"*) was adopted. Caught in pre-push review. **When triaging a future release, read every CHANGELOG section, not just `Added`.** |

## Backport log

Conventions this project invented, or convention failures it documented,
proposed upstream to the seed.

| Date | What | Upstream issue / PR |
|---|---|---|
| 2026-08-04 | `REVIEW_CONTEXT.md` §"Evidence discipline — fact, or artifact of the measurement?" — six tells that a measurement is an artifact rather than a result, structured as generic body + `### Instances (this project)`. No seed counterpart exists. ([#238](https://github.com/pdlourenco/adigator-embedded/pull/238), [#241](https://github.com/pdlourenco/adigator-embedded/issues/241)) | [seed #53](https://github.com/pdlourenco/disciplined-project-seed/issues/53) |
| 2026-08-04 | Red flag: *a guard whose failure direction is documented but not asserted* — the same shape as the seed's generic red-flag categories, instantiated here by the #200 embed-mode guard. §Red flags is project-specific throughout in this repo, so the upstream version is a one-sentence generic category with the local evidence dropped. ([#241](https://github.com/pdlourenco/adigator-embedded/issues/241) Gap C) | [seed #53](https://github.com/pdlourenco/disciplined-project-seed/issues/53) |

**Correction, recorded rather than quietly fixed (2026-08-04).** The first row
above originally claimed that lifting the section upstream would be *"a deletion
rather than a rewrite"*. Preparing seed #53 falsified that: **seven**
project-specific references sit inside the supposedly generic numbered body —
a cross-reference to a locally-numbered principle, MATLAB-specific path
vocabulary in tell 3, `(#230, §1.3n)` in tell 4, `(#234, §2.5(c))` plus its
inline statistic in tell 5, `docs/analyses/.gitignore` in tell 6, and
`ANALYSIS.md §2.5` in the closer. Tells 1 and 2 lift verbatim; the rest needed
rewriting. The generic-body/Instances split is still the right structure and
still made the backport cheap — but "a deletion" was a claim about the text
nobody had tested by attempting the deletion. Tell 6, applied to this file.

**On why these are worth proposing.** Both came out of *agent-to-agent* review,
where reviewer and author share reasoning habits and therefore share blind
spots — several instances behind them are reviewer-side, and one inference was
repeated by the reviewer *as* review. A shared-blind-spot failure survives
review by construction, which makes this class arguably more valuable at the
seed's scale than at this repo's.
