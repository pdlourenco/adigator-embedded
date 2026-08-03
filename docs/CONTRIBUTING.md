# Contributing to ADiGator-embedded

ADiGator-embedded is a small, largely agent-developed fork of the ADiGator
source-transformation AD tool. The thing that matters is that the **generated
derivative is correct**; these conventions exist to defend that cheaply. CI
strategy, requirements, and test traceability are owned by
[`CI_PLAN.md`](CI_PLAN.md) — this document covers the contributor mechanics
around it.

## Pre-push self-review

Before **every** `git push` on a PR branch, launch a reviewer subagent on the
local diff, seeded with [`REVIEW_CONTEXT.md`](REVIEW_CONTEXT.md) (principles +
red flags) alongside [`DESIGN.md`](DESIGN.md) and [`ANALYSIS.md`](analyses/ANALYSIS.md),
and act on what it flags before pushing. This catches the "I'd have caught that
if I'd thought harder" class of bug before it burns a (MATLAB-licensed) CI
round-trip or reviewer attention.

Ask the reviewer to check the diff for: (1) the principles in
`REVIEW_CONTEXT.md` cited by number; (2) contract drift vs. `DESIGN.md`
§Contracts; (3) the dimension-branch / path-leak / `Data*`-down-cast red flags;
(4) a bug fix landing without flipping or adding its pinning test; (5) scope
drift from the PR's stated purpose; (6) a decision that deserves an ADR.

**Exceptions** — one-line typo fixes, formatting-only changes, pure reverts.
The ceremony costs more than the signal. Note the outcome in the PR description:
`pre-push review: no findings` or `pre-push review flagged X, fixed in <sha>`.

## Local development & pre-push CI

The code requires real MATLAB (R2022a+, [ADR-0003](decisions/ADR-0003-r2022a-minimum-release.md)).
The license-free way to get the CI verdict before pushing is to run the suites
in a MATLAB session. Three entry points:

- `tests/ci_prepush.m` — the **fast pre-push gate** (lint + unit + integration),
  what the hook runs. CI additionally runs the coverage ratchet (`ci_coverage`);
  that stays **CI-only** so the hook stays fast — run `ci_coverage` manually for
  coverage-sensitive changes.
- `tests/ci_local.m` — the **full local gate** (adds the Coder-gated system
  suite).
- `tests/ci_ert.m` — the **embeddability attestation**. Runs *only*
  `SCodegenTest`, `SCodegenShowcaseTest`, `SRolledErtCodegenTest` and
  `SStackScalingTest`, printing a per-class verdict, because hosted CI can
  establish none of them (`CI_PLAN.md` §3.2, quoted below). It distinguishes the
  two things that both surface as *Filtered* — "this machine has no Embedded
  Coder" (**nothing** established) from "a documented `KnownIssue` pin fired as
  designed" (established, one recorded gap) — so a release can record the claim
  rather than assert it. Paste its output into the PR or release checklist.
  **It is not the whole codegen set**: `SLoopboundPaddingTest` and
  `MCSmokeTest/codegenEquivalenceIsClean` also filter silently on hosted CI and
  are established by your `ci_local` run, not this one — see "Confirm the
  codegen classes actually ran" below, which lists all six.

> **CI cannot verify codegen — your local run is the only gate for it.**
> On GitHub-hosted runners MATLAB Coder and Embedded Coder **install but are not
> licensed**, so *every* test that compiles (`SCodegenTest` including the ERT
> builds, `SCodegenShowcaseTest`, `SLoopboundPaddingTest`, the Monte-Carlo
> codegen-equivalence oracle) is silently *Filtered by assumption* — **inside a
> green job**. See [`CI_PLAN.md`](CI_PLAN.md) §3.2 "CI cannot verify codegen" for
> the measured evidence.
>
> So if your change touches the **generators**, the **embed pipeline**, the
> **shared codegen configuration**, or anything whose output is compiled: run the
> Coder-gated tests **locally** on a machine with licensed Coder + Embedded Coder
> and a configured C compiler (`mex -setup`; footprint/stack additionally need a
> standalone `gcc`/`size` toolchain), and **record what you ran and its result in
> the PR description**. A green `Extended` run is not evidence for those cells;
> treat "Filtered" in the job log as "not tested".

**Run them on a clean path** — in a fresh `matlab -batch`, not against a dirty
interactive session and never via `addpath(genpath(...))`. CI uses a clean path
(`matlab-actions/run-command` + `tests/ci_gate.m`, no `genpath`), so a dirty-path run can pass locally
while CI goes red on a test class missing its `PathFixture` (this is real —
[ADR-0017](decisions/ADR-0017-prepush-clean-path-testing.md), the PR #81 lesson):

```
matlab -batch "addpath('tests'); ci_prepush"
```

Wire it as a **pre-push hook** (recommended, [ADR-0017](decisions/ADR-0017-prepush-clean-path-testing.md)) so it runs automatically:

```
git config core.hooksPath .githooks
```

The hook skips cleanly where MATLAB is absent and is bypassable only via the
explicit `git push --no-verify`. It complements — does not replace — the §2
pre-push reviewer subagent.

**Writing tests:** subclass **`AdigatorTestCase`** (`tests/AdigatorTestCase.m`)
instead of `matlab.unittest.TestCase` — it puts the repo source folders on the
path for you, so a class can't silently rely on a dirty path. A class needing
extra paths adds its own `TestClassSetup` on top. `UTestPathHygieneTest`
enforces that every `tests/{unit,integration}` class does one or the other. The
suite lives under `tests/{unit,integration,system}`;
`tests/legacy/test_unarymath_rules.m` remains the legacy finite-difference rule
harness it was built from.

Note: the MATLAB suite **cannot** run in a Claude-Code-on-the-web container
(MATLAB is licensed and not provisioned there) — it runs in GitHub Actions
(`CI_PLAN.md` §3.1) and in local MATLAB sessions. Web sessions can still author,
review diffs, and edit docs.

The codegen system tests (`SCodegenTest`, TS-S-02) additionally need a MATLAB
Coder license and a configured C compiler (`mex -setup`); they self-skip via
assumption otherwise (so a "skipped/incomplete" result there is expected without
Coder, not a failure — but per the note above, *expected* is not *verified*: on
hosted CI they always skip, so only your local run establishes them). On R2024a with MinGW + ninja, codegen also needs `.` (the
current directory) on the **system** PATH so `cmd.exe` finds the generated
`.bat` build script, plus `MW_MINGW64_LOC` and `MinGW\bin` on the persistent
PATH — an R2024a environment quirk, not a toolbox bug.

**Confirm the codegen classes actually ran — per class, not by a total.** Since
your local run is the only gate for them, "it passed" is worth checking. Do *not*
use an aggregate incomplete count for this: optional dependencies (`SCasadiOracleTest`
without CasADi) and the `KnownIssue`/`assumeFail` convention for documented-unfixed
bugs (`CI_PLAN.md` §3.3) both produce *Filtered* results in a perfectly healthy
run. What matters is that the codegen classes specifically are not among them —
`SCodegenTest`, `SRolledErtCodegenTest`, `SCodegenShowcaseTest`,
`SLoopboundPaddingTest`, and `MCSmokeTest/codegenEquivalenceIsClean` (the
Monte-Carlo codegen-equivalence oracle, which is a method rather than a class of
its own). Read the run log for `Filtered by assumption` against those names — the
same check `CI_PLAN.md` §3.2 prescribes for a hosted job, applied to your own.
Say in the PR which of them ran, not just how many tests passed.

**The full gate can hang rather than fail.** On Windows/MinGW a `gcc` invocation
inside a MEX build can stall mid-build having consumed **zero CPU**, blocking
MATLAB indefinitely — nothing times out, so the run simply never ends. Two
consequences worth planning for:

- **Launch it so you can watch it.** Redirect to a log file and read it as it
  grows; a run piped through something that buffers until exit is
  indistinguishable from a hung one.
- **Tell hung from slow by CPU *time*, not wall-clock.** Sample the MATLAB
  process's accumulated CPU seconds twice, ~20 s apart — unchanged means stalled,
  not working. The MEX `buildLog.log` (under the temp
  `codegen/mex/<fn>/build/win64/`) names the step it stopped on. Kill the
  compiler process, its shell and MATLAB, then re-run: this is a toolchain
  stall, not a repository defect, and re-running has cleared it (#214).

## Design decisions (ADRs)

Non-obvious tactical choices live in [`decisions/`](decisions/) — see
[`decisions/README.md`](decisions/README.md) for when to write one and the
numbering convention (including the parallel-track rebase rule). Link the ADR
from the PR description; reference it inline beside the value it explains.
Contracts and architecture themselves belong in `DESIGN.md`, not an ADR.

## Documentation: state-based and release-relative

Two audiences, two conventions (ADR-0029, REVIEW_CONTEXT principle 8):

- **User-facing docs** — the user guide, `README`, `bench/SHOWCASE.md`, and the
  ADR-0025 emitted fragments — describe **current behavior**. Reference a
  behavior change **release-relative** ("new in v2.0", "deprecated in v2.0"),
  never with in-fork dev tracking (`ADR-xxxx` / `PR #x` / `#issue` / roadmap
  `Rnn` / rev-date / `Bnn`, or an inline dev-doc `§` citation like `ANALYSIS §` /
  `DESIGN §Contracts` — not a navigation link). The release-to-release change history lives in the
  user-facing `CHANGELOG.md`; point there instead of inlining change notes. A
  *new* doc has nothing to track — write it clean. Linking to a dev doc as
  navigation ("development plan: see ROADMAP") is fine.
- **Dev docs and code comments** keep the full audit trail. ADRs, `ANALYSIS.md`,
  `ROADMAP.md`, `CI_PLAN.md`, and `DESIGN.md` rationale track as they do. **Code
  comments keep everything** — the diff-annotations justifying why upstream code
  was touched, and the `Bxx` / `Rnn` / `#issue` / `ADR-` / `ANALYSIS` refs — and
  you keep writing them. The only rule: a change's **version tag names the
  release it ships in** (current unreleased work → `v2.0`; later work → its own
  release).

## Commit & branch conventions

- Feature branches: `claude/<topic>-<short-hash>` for agent work,
  `<user>/<topic>` for humans.
- Commits: imperative subject line, ≤70 chars; follow the existing `git log`
  style. One topic per commit where practical — it keeps CI failures
  diagnosable.

## PR lifecycle

Per [`../CLAUDE.md`](../CLAUDE.md) §5:

- **Opening a PR is free for already-planned work** — implementing an
  already-approved item does not need separate approval; the pre-push
  self-review (and local CI, once it lands) run first. Unplanned work follows
  `CLAUDE.md` §4 (surface it, wait for go-ahead) before the PR opens.
- **Merging always requires explicit maintainer approval** — never on an
  agent's own initiative, not even a green PR.

## Cutting a release

Releases are **tag-gated** ([ADR-0031](decisions/ADR-0031-release-as-code.md)):
pushing a `vX.Y` tag is the human release decision, and
[`.github/workflows/release.yml`](../.github/workflows/release.yml) does the
ceremony and validates it against the CHANGELOG. To cut a release from an
up-to-date `master`:

1. **Cut the CHANGELOG section.** Rename `## [Unreleased]` to
   `## [X.Y] — YYYY-MM-DD` (today's date), leaving a fresh empty `[Unreleased]`
   above it. **The renamed section is published verbatim as the GitHub release
   body** — `extract` strips only link definitions, not blockquotes, prose or
   HTML comments — so before renaming:
   - move the `<!-- Add user-facing changes here … -->` maintainer comment up
     into the new empty `[Unreleased]`, where it belongs (a plain rename carries
     it *into* the release notes, as the first thing a reader sees);
   - delete any `[Unreleased]` framing blockquote;
   - put forward-looking prose ("this will be…") into the past tense.

   Confirm the version matches the `version` constant in
   [`adigator.m`](../adigator.m). Optionally dry-run the gate:

   ```bash
   python3 .github/scripts/release_changelog.py validate --changelog CHANGELOG.md --version X.Y
   ```

2. **Commit** the CHANGELOG on a PR, review, and merge to `master` as usual.
3. **Tag a green `master`.** Tag the merge commit whose CI has passed (the
   workflow does *not* check CI status — tagging a red or arbitrary commit still
   publishes, so this is your responsibility), then push the tag:

   ```bash
   git tag vX.Y && git push origin vX.Y
   ```

The workflow then re-validates the tag against the CHANGELOG **and** against
`adigator.m`'s `version = '…'` constant (fails loud, no release, if the `[X.Y]`
section is missing/undated, `[Unreleased]` is non-empty, or the source version
disagrees), extracts the `[X.Y]` section as the release body, and publishes the
GitHub release with a curated runtime-distribution archive
(`*-dist.zip`/`.tar.gz`) attached. If a run half-completes (release created,
asset upload failed), delete the partial release and re-push the tag before
re-running.

## Two-session authoring / review workflow

For parallel agentic development the default topology is **two sessions per
track**: one authors, one reviews. They never share the three verbs below. See
[ADR-0009 in the seed](https://github.com/pdlourenco/disciplined-project-seed/blob/main/meta/decisions/ADR-0009-agent-pr-lifecycle-and-two-session-workflow.md)
for the rationale; the open/merge authorization this assumes is set in
[`../CLAUDE.md`](../CLAUDE.md) §5.

### Roles

- **Authoring session** — implements a planned item, opens the PR, pushes
  fixes, and **merges on the maintainer's *"merge and proceed."*** Owns the
  code. Its only review duty is the **pre-push self-review of its own diff**
  (above) — *not* the same verb as reviewing a PR.
- **Reviewing session** — **only reviews** (on *"review PR X"*) and follows
  through. It never edits or pushes code, and **never merges** — not even a
  clean, approved PR.

At a glance:

| Session | Authors / edits | Reviews open PRs | Merges |
|---|---|---|---|
| **Authoring** | yes | no — only the pre-push self-review of its *own* diff | yes, on `merge and proceed` |
| **Reviewing** | no | yes | no |

### The loop

1. **Authoring** implements and **opens the PR** — no separate approval for
   in-plan work; the pre-push self-review runs first.
2. **Reviewing** reviews on *"review PR X"*. Never touches code.
3. Maintainer tells authoring *"reviews posted"*; it analyses the comments and
   pushes any fixes.
4. Repeat 2–3 until the review is clean.
5. Maintainer tells authoring *"merge and proceed"*; it merges (squash / rebase
   for linear history) and starts the next item.

### Command vocabulary

| Phrase | Session | Means |
|---|---|---|
| `review PR X` | reviewing | review PR X against `REVIEW_CONTEXT.md` |
| `reviews posted` | authoring | analyse the posted review, push fixes |
| `merge and proceed` | authoring | merge the open PR, then start the next item |

When two authoring sessions run in parallel and share a contract surface, prefer
**one shared reviewer** over one-per-author — cross-track contract drift is
exactly what a single reviewer holding both contexts catches and two siloed
reviewers each miss.

The kickoff collapses to one line: *"you are the authoring / reviewing session
for <work item>, per `CONTRIBUTING.md` §Two-session authoring / review
workflow."* Only role + work-item are seeded per session.

## Warnings are actionable

CI warnings, deprecation notices, and MATLAB `checkcode` warnings should be
addressed, not tolerated — ignored only when triggered on purpose, with a
narrow suppression plus a one-line comment saying why. `CI_PLAN.md` treats the
`checkcode` warning count as a ratchet (REQ-C-10); don't grow it.
