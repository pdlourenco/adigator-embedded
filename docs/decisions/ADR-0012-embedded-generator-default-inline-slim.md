# ADR-0012 — `adigatorGenDerFile_embedded` defaults to inline + slim

## Status

Accepted — 2026-06-24. Implements a maintainer request from the development session:
calling the embedded derivative generator should, by default, produce the
embeddable, optimized form (inline data, slimmed code) rather than inheriting
the global classic default.

## Context

`adigatorOptions()` historically defaulted `embed_mode = 'c'` (classic) and
`slim_embed = 0` (off). The embedded entry point
`adigatorGenDerFile_embedded` inherited those defaults, so a user who called it
without spelling out options got classic, non-slimmed output — the *opposite*
of what that entry point exists for. The maintainer's intent: invoking the
embedded generator *is* the signal that the user wants embeddable, optimized
code, so it should default to inline (`'i'`) **and** slim.

The obstacle is that `adigatorOptions()` always *populates* `embed_mode` and
`slim_embed`, so a caller passing a full options struct
(`opts = adigatorOptions(); opts.embed_mode = 'i'`) carries `slim_embed = 0`
explicitly — the generator cannot distinguish "left at the default" from
"deliberately off." A per-entry-point default that only applied to bare calls
would therefore *not* take effect for the common full-struct call pattern (the
one the shipped examples use).

## Decision

Introduce an **unset sentinel**. `adigatorOptions()` now defaults
`embed_mode = []` and `slim_embed = []` (meaning "not chosen"); each entry
point resolves `[]` to its own default:

- **`adigatorGenDerFile_embedded`** resolves unset `embed_mode → 'i'` and unset
  `slim_embed → true`, then forwards the fully-resolved options to the inner
  `adigatorGenJacFile`/`adigatorGenHesFile` so the wrapper and the
  post-processing agree on the mode.
- **The classic generators** (`adigatorGenJacFile`, `adigatorGenHesFile`, core
  `adigator`) resolve unset `embed_mode → 'c'` via
  `adigatorNormalizeEmbedMode([]) → 'c'`; they never read `slim_embed`.

An explicitly-set value always wins, so `'c'`/`'l'`/`'i'` and `slim_embed = 0`
stay fully selectable everywhere (including via a full `adigatorOptions`
struct). An empty *char* `''` remains a malformed value and still errors — only
the numeric-empty `[]` sentinel resolves.

## Consequences

- Bare, partial, and full-struct calls to the embedded generator all get
  inline + slim unless the option is set explicitly — the intent holds for
  every call pattern.
- Tests/examples that pass an explicit `embed_mode` are unaffected. Tests that
  called the embedded generator **without** `slim_embed` now exercise the slim
  pass by default; where a test needs the *unslimmed* baseline it now sets
  `slim_embed = 0` explicitly (`IEmbedSlimTest` baselines, `SCodegenTest`'s
  unshrunk point). The slim pass is numerically safe (closure-gate +
  round-trip, conservative bail), so cross-mode numeric-equality tests
  (`IEmbedModesTest`, `IStructInputTest`, `oracleCrossMode`) stay green while
  now covering the default path.
- `UOptionsTest` pins the new behavior: unset defaults are empty, and
  `adigatorNormalizeEmbedMode([]) → 'c'` (while `''` still errors).
- Docs updated to match (REQ per CLAUDE.md §3): `adigatorOptions` help, the
  generator help, `docs/README.md`, and the user guide.
- No derivative-shape contract changes (DESIGN §Contracts C-1..C-5 hold); the
  modes themselves are unchanged, only which one is the default.

## Alternatives considered

- **Contained (bare/partial only)** — seed the embedded defaults but let any
  full struct win. Lowest risk, but slim would *not* apply to the dominant
  full-struct pattern, missing the intent. Rejected.
- **Flip the global `adigatorOptions` default to `'i'`/on** — would change the
  classic standalone generators too (out of scope, surprising for classic
  users). Rejected.
- **Treat the value `'c'`/`0` as "unset"** — would make explicit classic /
  no-slim unreachable via a full struct and break the `'c'`-mode and
  unslimmed-baseline tests. Rejected.
