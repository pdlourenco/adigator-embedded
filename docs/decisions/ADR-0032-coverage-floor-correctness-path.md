# ADR-0032 — V&V coverage floor on the derivative-correctness path

## Status

Accepted — 2026-07-27. First deliverable of the V&V-for-release gate (the
maintainer's standard that the V&V issues #38 / #103 / #64 close before the v2.0
tag, because ADiGator-embedded is being taken over as a *critical* embedded-code
generator). Complements the fast PR-gate ratchet in
[ADR — CI plan](../CI_PLAN.md) (`ci_coverage.m`); this ADR adds the *release*
floor.

## Context

The repo already had a coverage ratchet, but it measured the wrong thing for a
critical-software standard:

- **Scope too narrow.** `ci_coverage.m` runs only the PR-gate suites
  (unit + integration) and reports a *single aggregate* line rate over
  `lib/ + util/ + embedding/`. The honest full-suite number
  (unit + integration + system + montecarlo) is **47.6%**, versus the
  PR-gate-only **19.4%** baseline — the aggregate hid where coverage actually
  is.
- **Aggregate hides the correctness path.** Broken out per folder, the tree
  splits sharply:

  | folder | line coverage | what it is |
  | --- | --- | --- |
  | `embedding/` | ~92% | embed-mode emitter (serialises a derivative object) |
  | `util/` | ~75% | host-side generators & helpers (CSC, loopbound, showcase) |
  | `lib/cadaUtils` | ~87% | shared derivative utilities |
  | `lib/` (top-level) | ~59% | source-transformation orchestration |
  | `lib/@cada` | ~40% | **per-operation forward/reverse derivative rules** |
  | `lib/@cadastruct` | ~17% | **struct / remap / union layer** |

  A single aggregate floor would let a real regression in `@cada` (where a wrong
  derivative *originates*) be masked by an unrelated rise in `embedding` (which
  only *emits* an already-computed derivative). Under Principle 1 — a wrong
  derivative is worse than an error — the correctness-critical buckets are
  exactly `@cada` / `@cadastruct` / orchestration, and they are the *least*
  covered. A blunt aggregate makes that invisible.

An earlier framing tiered the floor by **authorship** (fork-authored
`embedding`/`util` = critical, inherited `@cada` = "tolerable upstream tail").
That is backwards: a perfectly-embedded *wrong* derivative is worthless, and the
derivative is computed in `@cada`/`@cadastruct`. The floor must follow the
**derivative-correctness path**, not who wrote the file.

## Decision

Add a **per-folder, full-suite coverage floor** as the V&V release gate, kept
separate from the untouched PR-gate ratchet.

- **`tests/ci_coverage_folders.m`** — runs the full deterministic suite
  (unit + integration + system + montecarlo) under coverage of
  `lib/ + util/ + embedding/`, buckets each file into the six folders above, and
  enforces a **per-folder no-regression ratchet**: each folder must hold its
  baselined rate within a tolerance. A drop in one folder can never be offset by
  a rise in another. `ci_coverage_folders('write')` regenerates the baseline.
- **`tests/coverage_baseline_folders.txt`** — the per-folder floor, one row per
  folder, generated from a real run (self-consistent with the script).
- **Enforced in `extended.yml`**, not the PR gate. The full suite needs
  `Optimization_Toolbox` + `MATLAB_Coder` (already installed in that job's
  `full-products` install) and system/montecarlo runtime the fast PR gate
  deliberately omits. The PR gate's `ci_coverage.m` is left unchanged, so PRs
  stay fast; the release floor runs post-merge where the real numbers live.
- **Ratchet now, raise later.** The correctness-path buckets are baselined at
  their *current* (low) levels — the ratchet only forbids backsliding. Their
  real targets are **raised as #38 (FD value oracle) and #103 (option×operation
  oracle matrix) land tests**, driven by the shipped-surface overload inventory
  (`docs/vv/cada-surface-inventory.md`), which classifies every `@cada` /
  `@cadastruct` overload as supported / guarded-unsupported / dead so the floor's
  denominator is the *shipped* surface, not raw lines.

## Consequences

- The floor is highest exactly where a wrong derivative can originate, and a
  regression there breaks CI on its own — it cannot hide behind the emitter.
- **Coverage is necessary, not sufficient.** A covered line in `@cada/prod.m`
  can still return a wrong Jacobian. The floor has teeth only paired with the
  #38 / #103 value oracles; this ADR sets the ratchet, those issues supply
  correctness. The inventory is the shared worklist.
- The gate runs post-merge (Extended), so a coverage regression is caught after
  merge, not on the PR. That is the accepted trade for keeping the PR gate fast
  and for measuring the *real* (full-suite, licensed-product) numbers; the
  maintainer chose this enforcement point explicitly.
- **Baseline is a conservative floor, not a measured peak.** Even on one
  machine with fixed montecarlo seeds, the correctness-path buckets show
  ~0.3–0.6 pp run-to-run jitter: the set of `@cada`/`@cadastruct` files a run
  *instruments* shifts with which overloads that run happens to touch (the
  stable emitter buckets `embedding`/`util`/`cadaUtils` do not move). So
  `'write'` records each rate **rounded down to 2 decimals**, placing the floor
  at/below the observed minimum, and `TOL = 0.01` adds a further point — ordinary
  jitter never trips the ratchet; only a real backslide does. Cross-release RNG
  and line-count shifts are the same phenomenon at larger amplitude: the baseline
  is authoritative for the release the Extended `full-products` job runs
  (`latest`); regenerate (`'write'`) when the pinned release moves. Any mismatch
  fails **loud** (a `regression`/`missingBucket` error), never a silent green.
- Two coverage scripts now coexist (`ci_coverage.m` aggregate PR-gate,
  `ci_coverage_folders.m` per-folder release floor). They have different scopes
  and different jobs; the small duplication is deliberate to keep each simple.
