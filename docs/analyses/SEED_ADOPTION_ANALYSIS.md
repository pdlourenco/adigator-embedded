# Should adigator-embedded adopt the `disciplined-project-seed`?

An assessment of the [`disciplined-project-seed`](https://github.com/pdlourenco/disciplined-project-seed)
against this repository, deciding — per concept — what is worth adopting and
what is overhead given what adigator-embedded actually is.

**Bottom line.** Adopt a *small* slice. The seed's high-value, low-ceremony
pieces (a `CLAUDE.md`, a reviewer-context document, a lightweight ADR habit,
and the verification-vs-validation framing) fit this project well and address
real gaps. Most of the seed's *machinery* — label-sync, branch-protection-as-
code with drift detection, the DESIGN/SPEC split, STRUCTURE/RISKS/plans as
separate documents, the `meta/` history, the template-placeholder tooling — is
built for a problem this repository does not have, and adopting it would add
maintenance surface without buying anything. Notably, the single most valuable
idea in the seed — the V-model left-leg/right-leg discipline — **has already
been adopted independently** in [`CI_PLAN.md`](../CI_PLAN.md); that convergence is
the strongest evidence for which parts carry their weight.

---

## 1. What the seed is built for vs. what this repo is

The seed states its own sweet spot plainly in its README:

> *"The discipline pays off most when contributors — human and agent — edit
> independent modules in parallel and the cost of an unnoticed contract break
> is higher than the cost of writing things down. If that doesn't sound like
> your project, adopt selectively; `CLAUDE.md`, `REVIEW_CONTEXT.md`, and the
> ADR set are the pieces that carry weight even at single-contributor scale."*

That framing maps almost one-to-one onto the keep/drop decision below. The
seed's central assumption is **multiple parallel contributors editing
independent modules against cross-language / cross-process / cross-module
contracts**. adigator-embedded is close to the opposite on every axis:

| Axis | Seed assumes | adigator-embedded is |
|------|--------------|----------------------|
| Languages | Polyglot; contracts cross language boundaries | Single language (MATLAB), one small Fortran reference file |
| Module boundaries | Many independent modules developed in parallel | One coherent transformation engine (`lib/@cada`, `util/`, `embedding/`) |
| Contributors | Multiple humans + agents in parallel | Small; largely agentic against a maintained upstream fork |
| Process boundaries | RPC / on-disk / cross-process contracts | None — in-process MATLAB calls; the only "wire format" is generated `.m`/`.mat` files |
| Licence | MIT | **GPLv3** (inherited from upstream Weinstein/Rao) |
| Maturity | Greenfield scaffold | Mature 1.5 codebase + an active embedded fork |

The consequence: every seed concept whose value comes from *coordinating
parallel edits to a shared contract* is low-value here, and every concept whose
value comes from *capturing intent and catching regressions* is high-value here
regardless of scale.

## 2. Convergent evolution: the seed's best idea is already in the repo

Before forking the seed at all, note that [`CI_PLAN.md`](../CI_PLAN.md) was written
as a *"simplified V-model: requirements stated first (left leg), each
requirement assigned tests that verify or validate it (right leg)"*, with stable
`REQ-T`/`REQ-C`/`TS-U`/`TS-I`/`TS-S` IDs and an explicit traceability matrix
(§2.4). That is precisely the discipline the seed introduces in its
`ADR-0007 — v-cycle-additions` and `REVIEW_CONTEXT.md §"Verification vs
validation"`.

This is the clearest signal in the whole analysis: the project independently
arrived at the seed's load-bearing idea *because the idea earns its keep here*
(correctness of generated derivative code is the thing that matters, and pinning
each requirement to a test is how you defend it). The "deferred-with-conditions"
pattern the seed pushes is likewise already in use — `CI_PLAN.md §3.5 "Out of
scope"` and `ANALYSIS.md §3.3` (the staged reverse-mode plan, each stage with a
trigger) are exactly that shape.

So adoption is not "import a foreign discipline"; it's "harmonise vocabulary
with a discipline the repo already practises, and fill the few gaps."

## 3. Component-by-component verdict

Legend: **Adopt** (high value, low overhead) · **Adapt** (valuable but must be
slimmed/retargeted) · **Drop** (overhead for this project).

### 3.1 Adopt

| Seed artifact | Verdict | Why it fits here |
|---------------|---------|------------------|
| **`CLAUDE.md`** (agent operating rules) | **Adopt, slimmed** | This repo is developed largely by agents and has *no* root operating-rules file today. A short index pointing agents at `CI_PLAN.md`, `ANALYSIS.md`, the derivative conventions, and the pre-push review habit is pure upside. Drop §3's cross-boundary-contract language; collapse it to "implementations must match `adigatorDerivativeConventions.m` and the generated-file/Gator-data layout documented in `ANALYSIS.md`." |
| **`REVIEW_CONTEXT.md`** (reviewer-agent seed) | **Adopt** | High value at any scale, and this project has unusually crisp, citable principles to fill it with: *no runtime `load`/`global` in `l`/`i` modes; codegen compatibility; cross-mode numeric identity; derivative correctness vs FD; matrix-induced norms must error rather than mis-differentiate; GPLv3 dependency hygiene.* These are real, repeatedly-relevant invariants — exactly what the section is for. |
| **Lightweight ADR habit** (`docs/decisions/`) | **Adopt, minimal** | The repo is *already making* ADR-worthy decisions and burying them in commit messages: "down-cast only `Index*`, leave `Data*` double" (B1), "matrix-induced norm raises an error instead of an SVD" (#28), "minimum release R2022a", "single-install PR pipeline". A handful of short ADRs would stop these rationales from being re-derived. Skip the two-lifecycle (ADR-first / issue-first) ceremony and the `meta/` split — just a numbered file per sticky decision. |
| **V-model / verification-vs-validation framing** | **Adopt (formalise)** | Already in `CI_PLAN.md`. Worth lifting the *vocabulary* (left leg = what, right leg = built-right; `Verified by:` annotations) into the conventions so reviews can name which leg a finding is on. Zero new machinery. |
| **Deferred-with-conditions pattern** | **Adopt (already in use)** | Make it explicit as a convention; it's already practised in `ANALYSIS.md`/`CI_PLAN.md`. |

### 3.2 Adapt

| Seed artifact | Verdict | What to change |
|---------------|---------|----------------|
| **`CONTRIBUTING.md`** | **Adapt, heavily slimmed** | Keep: the **pre-push self-review** convention (genuinely useful for agentic work — catch issues before burning MATLAB-licensed CI minutes), commit/branch conventions, and a MATLAB-specific "local development" section. **Drop the four-tier CI section** — it duplicates `CI_PLAN.md`, which is more specific and correct for this repo; link to it instead. Tier 1 (cross-component contract enforcement) and Tier 2 (cross-platform matrix) don't apply: there are no cross-component contracts, and `CI_PLAN.md §3.5` already (correctly) rules out an OS matrix. |
| **`DESIGN.md`** | **Adapt — real gap, single file** | There is a genuine architecture-documentation hole: the only architectural narrative today lives in PDFs (`ADiGatorUserGuide`, the dissertation, the TOMS papers). A concise `DESIGN.md` explaining the overloading/source-transformation model, the `@cada`/`@cadastruct` classes, the "static tape" insight (`ANALYSIS.md §3.2`), and the embedded pipeline would help every future contributor. Keep it as *one* file. |
| **`SPEC.md`** (separate contract doc) | **Adapt — fold in, don't split** | The seed's value proposition for a *separate* SPEC is parallel modules agreeing on a wire format. Here the only "contract" is the derivative output convention + the `y.dX` / `Gator*Data` layout — and that is already partly specified in `adigatorDerivativeConventions.m` and the `ANALYSIS.md` preamble. Recommendation: a short **"Contracts" section inside `DESIGN.md`** (or a thin `SPEC.md` if preferred) that consolidates those, rather than maintaining the full DESIGN/SPEC pair as two competing homes. The strict split is overhead below the multi-implementation threshold. |
| **`ROADMAP.md`** | **Adapt — inline, no `plans/`** | A single roadmap consolidating the bug-fix sequence (B1–B14), the CI phased rollout (`CI_PLAN.md §3.4`), and the reverse-mode stages (`ANALYSIS.md §3.3`) is useful. **Skip the `plans/` subdirectory** — at this size, per-phase plan files are more structure than content. Keep phases inline. |
| **PR / issue templates** | **Adapt, optional** | A slim `pull_request_template.md` with a "pre-push review: …" line reinforces the one convention worth reinforcing. The `decision-proposal.yml` issue template only pays off if the ADR habit takes hold. Low cost, low-to-moderate value. |
| **Cheap doc-lint CI jobs** | **Adapt, optional** | The seed's tier-3 `markdown-lint` / internal `link-check` jobs are cheap and licence-free (no MATLAB), so they *could* sit alongside the MATLAB CI from `CI_PLAN.md`. Minor value; adopt only if doc rot becomes real. |

### 3.3 Drop (overhead for this project)

| Seed artifact | Why it's overhead here |
|---------------|------------------------|
| **Label-sync machinery** (`docs/LABELS.md` + `.github/labels.yml` + `sync-labels.yml` + `ADR-0001`/`ADR-0003`) | A version-controlled label catalogue with a reconciliation workflow is for teams where label drift across many contributors is a real cost. This repo can apply a handful of labels by hand. ~210 lines of machinery + a workflow to maintain, for negligible benefit at this scale. |
| **Branch-protection-as-code** (`branch-protection.yml`, `setup-branch-protection.sh`, `normalize-branch-protection.jq`, `check-bp-contexts.py`, `check-branch-protection.yml`, `ADR-0005`) | Three drift-detection mechanisms across two timing modes is serious infrastructure justified by "protection silently removed across a big team." A solo/small fork sets branch protection once in the GitHub UI. ~450 lines + a weekly scheduled workflow + a PAT secret, for a problem this repo doesn't have. |
| **`STRUCTURE.md`** (separate layout doc) | adigator's layout (`lib/@cada`, `util/`, `embedding/`, `examples/`) is inherited and stable; it isn't churning. A short "layout" paragraph in `DESIGN.md` covers it. A standalone aspirational-layout file would mostly describe what already exists. |
| **`RISKS.md`** | The seed itself says skip unless under regulated/safety obligations. The relevant risk here — *silently-wrong generated derivatives* (e.g. B7 Hessian row index, B9 layout inconsistency) — is already captured in `ANALYSIS.md` and *pinned by tests* in `CI_PLAN.md`, which is a stronger control than a prose register. Fold any residual into `ANALYSIS.md` rather than open a new document. |
| **`meta/` (seed's own history) + `ADR-0001..0008`, `meta/CHANGELOG`** | These document *the seed's* evolution, not adigator's. Useful only as reference while deciding (as done here); nothing to copy into the repo. The seed's `README` explicitly offers `rm -rf meta/`. |
| **`audit-placeholders.py` + the template-placeholder convention** | These exist to police `[PROJECT]` / `<!-- FILL IN -->` markers in an unfilled template. If we write real documents directly (recommended) rather than carrying the template tree, there are no placeholders to audit. |
| **Seed's `ci.yml` as the CI baseline** | It is markdown/YAML-lint centric and knows nothing about MATLAB. `CI_PLAN.md` is the correct, project-specific CI design (MATLAB setup, licence handling, `KnownIssue` tagging, single-install pipeline). Don't let the seed's `ci.yml` displace it; at most borrow the two cheap doc-lint jobs (§3.2). |
| **DESIGN/SPEC strict separation, ROADMAP/`plans` separation** | The *discipline* (rationale vs contract; portfolio vs execution) is sound, but maintaining four documents where two would do is overhead below the multi-implementation, multi-phase-in-flight threshold this repo sits under. Collapse as noted in §3.2. |

## 4. Licensing note

The seed ships under **MIT**; this repository is **GPLv3** (Weinstein/Rao
upstream, with the GMV embedded additions). MIT text and scaffolding can be
incorporated into a GPLv3 project without conflict (MIT is GPL-compatible), but:

- Any seed file copied in should have its MIT copyright/attribution line either
  preserved or rewritten to point at this project, per the seed README step 6.
- Don't copy the seed's `LICENSE` — this repo keeps `docs/COPYING.txt` (GPLv3).

This is a minor mechanical point, not a blocker.

## 5. Recommended minimal adoption

If the project adopts anything, this is the proportionate set — roughly a day of
work, no new infrastructure to maintain:

1. **`CLAUDE.md`** at the repo root — short, pointing at `CI_PLAN.md`,
   `ANALYSIS.md`, `adigatorDerivativeConventions.m`, and the pre-push review
   habit; §3 retargeted to the derivative-conventions contract.
2. **`docs/REVIEW_CONTEXT.md`** — filled with the real principles listed in
   §3.1 (embeddability, codegen compat, cross-mode identity, FD-correctness,
   norm/SVD policy, GPL hygiene).
3. **`docs/DESIGN.md`** — one file: architecture narrative + a "Contracts"
   subsection consolidating the derivative-output convention and `y.dX`/
   `Gator*Data` layout.
4. **`docs/decisions/`** — start an ADR log; back-fill 3–4 decisions already
   made (B1 down-cast policy, norm-error policy, R2022a floor, single-install
   pipeline).
5. **A slim `CONTRIBUTING.md`** — pre-push review + commit conventions + MATLAB
   local-dev commands; link to `CI_PLAN.md` for CI rather than restating it.
6. Optionally a **`pull_request_template.md`** with the pre-push-review line.

Everything in §3.3 stays out unless and until the project grows the problem it
solves (more parallel contributors, a second language/implementation, a
genuine team-scale label/branch-protection coordination cost).

## 6. What *not* to do

- **Don't `Use this template` / import the whole tree.** It would create
  duplicate homes for content that already lives well in `ANALYSIS.md` and
  `CI_PLAN.md`, and drag in label/branch-protection/`meta` machinery the repo
  won't maintain.
- **Don't restructure `CI_PLAN.md` into the seed's `CONTRIBUTING.md §CI
  strategy` four-tier mold.** The current document is *more* correct for this
  repo (it knows about MATLAB licensing, `KnownIssue` tagging, and why an OS
  matrix is unnecessary). Adopt the vocabulary, not the reshaping.
- **Don't split existing consolidated analysis into DESIGN+SPEC+RISKS+ROADMAP
  for symmetry's sake.** Symmetry with the seed is not a goal; reducing the
  number of places a future contributor must look is.
