# Analysis documents

Dated, immutable analysis snapshots: repo-wide reviews, field reports, audits,
adoption and backport studies.

Analyses fill a gap the rest of the doc set leaves open. They are neither
decisions ([`../decisions/`](../decisions/README.md) records what was chosen and
why) nor living contracts or rationale ([`../DESIGN.md`](../DESIGN.md) §Contracts
is maintained to stay true). An analysis records **what was observed at a point
in time**, and is then left alone.

Adopted from the [disciplined-project-seed](https://github.com/pdlourenco/disciplined-project-seed)
at v0.4.1; see [`DISCIPLINE_ADOPTION.md`](../../DISCIPLINE_ADOPTION.md). The
rules below describe what this folder already did — writing them down is what
stops the next analysis drifting from it, since the `.gitignore` whitelist was
previously the only enforced convention here.

## The four rules

1. **Dated filename.** `YYYY-MM-DD-<slug>.md`, dated by when the analysis was
   performed, not when it merges.
2. **Anchored to a commit.** Each analysis names the commit it examined.
   `file:line` references are relative to that commit and are expected to drift
   afterwards — that is not an error.
3. **Immutable once merged.** Findings are not edited as they get fixed; the
   follow-up issues and PRs are the live tracking surface. Amendments land while
   the analysis's PR is open; after merge, supersede by writing a new dated
   analysis. Each document should say so up front and point at where live status
   is tracked.
4. **Not a contract.** Nothing in an analysis binds implementations. Binding
   text lives in `DESIGN.md` §Contracts and
   `adigatorDerivativeConventions.m`; decisions live in ADRs. An analysis can
   motivate either — the authoritative text then moves there.

**A recorded command is a claim, not a fact.** When an analysis records a shell
command as *working*, test it against a live system at the time it is carried,
not on the strength of the source study. A command can enter the record untested
and then propagate as established fact. This is the same failure as
[`../REVIEW_CONTEXT.md`](../REVIEW_CONTEXT.md) §"Evidence discipline" tell 6,
reached independently upstream; verify executable commands at backport time.

The immutability-plus-pointers rule is what keeps this folder from becoming a
stale-doc graveyard: nothing in it claims to be current, so nothing in it can
rot.

## The one exception: `ANALYSIS.md` is a register, not a snapshot

[`ANALYSIS.md`](ANALYSIS.md) is a **canonical register** — the numbered `Bnn`
bug catalogue and the optimization/reverse-mode analysis, cited by stable IDs
from `CI_PLAN.md`, `ROADMAP.md`, ADRs and commit messages. It is deliberately
**living**, and rule 3 does not apply to it. It is the seed's documented
register exception rather than a violation of rule 3, and it is named here so
nobody "fixes" it into a dated snapshot.

Everything else in this folder is a snapshot.

## Current contents

| Document | Kind |
|---|---|
| [`ANALYSIS.md`](ANALYSIS.md) | **register** (living) — `Bnn` bugs, optimization and reverse-mode analysis |
| [`SEED_ADOPTION_ANALYSIS.md`](SEED_ADOPTION_ANALYSIS.md) | snapshot — seed assessment, 2026-07-06 |
| [`2026-07-04-code-quality-review.md`](2026-07-04-code-quality-review.md) | snapshot |
| [`2026-07-09-objective-reassessment.md`](2026-07-09-objective-reassessment.md) | snapshot — self-declares that it will not be maintained |
| [`2026-08-02-engine-v2-r6-r21-implementation-analysis.md`](2026-08-02-engine-v2-r6-r21-implementation-analysis.md) | snapshot |

`SEED_ADOPTION_ANALYSIS.md` predates rule 1's naming convention. It is not
renamed: rule 3 makes merged analyses immutable, and the live adoption state now
lives in [`DISCIPLINE_ADOPTION.md`](../../DISCIPLINE_ADOPTION.md) anyway.

## See also

- [`../decisions/README.md`](../decisions/README.md) — where a decision an
  analysis motivates gets recorded.
- [`../../DISCIPLINE_ADOPTION.md`](../../DISCIPLINE_ADOPTION.md) — adoption
  state and the seed sync log.
