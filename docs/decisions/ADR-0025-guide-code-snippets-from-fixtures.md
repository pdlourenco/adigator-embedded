# ADR-0025 — User-guide code samples load from golden fixtures via marked `listings` ranges

## Status

Accepted — 2026-07-07. **Extended 2026-07-07** (see
[Extension](#extension--2026-07-07-bench-measured-tables-via-producer-emitted-input)):
adds a second mechanism for *measured/computed* bench comparison content — the
bench producer emits a committed, ready-to-`\input` `.tex` fragment — keyed by
artifact class alongside the original `\lstinputlisting`-on-source-fixture path.

## Context

Issue [#139](https://github.com/pdlourenco/adigator-embedded/issues/139) asks the
user guide to show *generated* derivative code — a reverse-mode `_RGrd`/`_JtV`
sample, a classic-vs-inline embedded contrast — not just hand-written user code.
Two forces pull against each other:

- A whole generated file (an `_ADiGator*` derivative file, an inline data
  companion) is far too long to sit in a guide; the reader needs a **short,
  representative slice**.
- Copy-pasting that slice into `ADiGatorUserGuide.tex` makes the guide a second,
  hand-maintained source of truth for generator output. It **rots silently**:
  the pasted code drifts from what the tool actually emits, and nothing catches
  the divergence. This repo already keeps committed generated code as **golden
  fixtures** (`tests/fixtures/…`, e.g. `cf_Jac.m` / `cf_ADiGatorJac.m`) precisely
  so a single source of truth is version-controlled and testable.

So the guide should *load* an excerpt from a golden fixture rather than embed a
copy — but "load a sub-range of a file" in LaTeX has to survive the one thing
golden fixtures do routinely: **regeneration**. A snippet keyed to line numbers
silently grabs the wrong region the first time the fixture shifts by a line.

The guide's current LaTeX toolchain (`docs/userguide/ADiGatorUserGuide.tex`,
built by `makepdf.sh` with plain `pdflatex` — **no `-shell-escape`**) shows all
code today as hand-pasted `\begin{verbatim}` blocks, and loads `verbatim` +
`fancyvrb` but not `listings` or `minted`.

## Decision

Guide code samples that reproduce **generated** output load an excerpt from the
committed golden fixture, using the `listings` package's `\lstinputlisting` with
a **named text-marker range** (the "B1" option from the #139 discussion):

```latex
% preamble
\usepackage{listings}
% at the sample
\lstinputlisting[language=Matlab,includerangemarker=false,
                 linerange={BEGIN-rgrd-core}-{END-rgrd-core}]
                {../../tests/fixtures/<...>/<fn>_RGrd.m}
```

- **Markers are emitted by the fixture producer**, not hand-added. The MATLAB
  routine that (re)generates the golden fixture writes a paired
  `% BEGIN-<tag>` … `% END-<tag>` comment around each region the guide excerpts.
  They are plain MATLAB line comments — inert to MATLAB, `adigator`, and MATLAB
  Coder — and are kept out of the printed listing by the **`includerangemarker=false`**
  option (its `listings` default is `true`, which *prints* the marker lines, so
  the option is required, not implicit). Because `listings` matches the
  **markers, not line numbers**, the excerpt survives regeneration as long as the
  producer keeps re-emitting the markers.
- `<tag>` names are lowercase-kebab, scoped to the fixture and unique within it;
  the producer owns the tag set. A tag referenced by the guide but absent from
  the fixture is a build error (the excerpt is empty / `listings` errors), which
  is the intended tripwire. The `{BEGIN-<tag>}-{END-<tag>}` brace grouping is what
  separates the two markers from the range `-`; the implementation PR should
  confirm brace-grouped markers containing `-` parse cleanly against a real build
  and, if not, drop the internal hyphen (`BEGINrgrdcore`).
- `listings` needs **no `-shell-escape`**, so `makepdf.sh` stays a plain
  `pdflatex` build. Hand-written *user* code in the guide keeps using
  `verbatim`; only loaded-from-generator samples use `\lstinputlisting`. The two
  styles coexist deliberately — illustrative input vs. real emitted output are
  different things.

This is a docs-tooling and on-disk-convention decision; it does **not** touch a
derivative Contract (C-1..C-6) or `adigatorDerivativeConventions.m`.

## Consequences

- **New build dependency:** the guide preamble gains `\usepackage{listings}`
  (TeX Live `texlive-latex-recommended`, already in the guide-build install).
  No shell-escape, no Python/pygments, no change to `makepdf.sh`'s command
  sequence.
- **New cross-artifact convention:** golden-fixture *producers* (the MATLAB
  generators / bench harness that write the committed fixtures) must emit and
  maintain the `% BEGIN-<tag>`/`% END-<tag>` marker pairs the guide references.
  This is a small standing obligation on the code side, owned by the MATLAB
  session; the guide side (this docs session) owns the `\lstinputlisting` wiring
  and the tag references. Drift shows up as a build error, not a silent stale
  paste.
- **Build-time coupling:** the guide PDF build now reads files under
  `tests/fixtures/…`. Those are committed golden fixtures, so they are present at
  build time; a moved/renamed fixture breaks the guide build (caught in CI /
  local rebuild), which is preferable to a silently stale sample.
- **Single source of truth restored:** the sample in the PDF is a slice of the
  same bytes the tests assert on. A generator change that alters emitted code
  either updates the fixture (and the sample follows) or fails its fixture test.
- **Revisit when:** (a) marker maintenance proves burdensome or a needed snippet
  has no fixture to key off — fall back to the documented **B2** alternative (a
  committed curated excerpt file that the guide loads whole, pinned by a test
  asserting it is a substring of the real fixture); (b) syntax-highlighting needs
  outgrow `listings` — reconsider `minted`, accepting the `-shell-escape` build
  change it forces.

## Alternatives considered

- **Copy-paste the snippet into the `.tex` (status quo for all code today).**
  Allows arbitrary slicing with zero tooling, but makes the guide a second,
  hand-maintained copy of generator output that drifts silently — the exact rot
  golden fixtures exist to prevent. Rejected for *generated* samples (kept for
  hand-written user code, which has no fixture and no drift risk).
- **`\VerbatimInput[firstline=..,lastline=..]` (`fancyvrb`, already loaded — zero
  new packages).** Loads a line range with no new dependency, but keys the
  excerpt to **line numbers**: the first regeneration that shifts the fixture
  makes the guide quietly show the wrong lines. Rejected as brittle for the one
  file class that is regenerated by design. (`listings`' own `firstline`/
  `lastline` was rejected for the same reason.)
- **B2 — committed curated excerpt file + substring test.** Keep a small
  hand-picked slice as its own file that the guide loads whole, with a test
  asserting it is a literal substring of the real fixture. Needs no generator
  change, but is still a hand-maintained copy (the test bounds the drift instead
  of eliminating it, and the curation is manual). Kept as the **documented
  fallback** for cases with no suitable fixture or marker, not the primary path.
- **`minted`.** Best syntax highlighting, but requires `-shell-escape` plus a
  Python/pygments toolchain — a build-system change to `makepdf.sh` and the CI
  image — for a highlighting nicety. Rejected as disproportionate; `listings`
  covers the need within the existing plain-`pdflatex` build.

## Extension — 2026-07-07: bench measured tables via producer-emitted `\input`

The original decision covers loading *generated source code* into the guide.
Issue #139 item 2 (the embedded classic-vs-inline contrast) also needs the
**measured/computed** comparison — code-line counts, ROM/`.mat` bytes, generated-C
size, runtime — which `listings`-on-a-source-fixture cannot produce (those are
numbers the bench harness computes, not text in a file). Copy-transcribing them
into the guide is the same rot this ADR exists to avoid: the tables in
`bench/SHOWCASE.md` are already produced by `bench/derivShowcase*.m`, and a
hand-typed copy in the guide would silently fall out of step with the next run.

**Extended decision.** For measured/computed bench comparison content, the bench
producer (MATLAB session) emits a **committed, ready-to-`\input` `.tex`
fragment**, and the guide includes it with `\input{…}` — no extraction, no
`listings`, no markers. The two mechanisms partition by **artifact class**:

- *Generated source code* → marked golden fixture + `\lstinputlisting`
  (the original decision above).
- *Measured/computed tables* → bench-producer-emitted `\input` fragment
  (this extension).

Code excerpts stay on the `\lstinputlisting` path; the bench fragment carries
**tables only** — one mechanism per concern, no overlap.

**Constraints on the emitter** (both owned by the MATLAB-session bench code):

1. **Deterministic committed artifact.** The guide build runs plain `pdflatex`
   and cannot invoke MATLAB, so the fragment is regenerated by the bench harness
   and **checked in** (like the golden fixtures and the PDF). The emitter must be
   deterministic — stable row order, LaTeX-escaped identifiers (underscores),
   **no timestamps** — so re-running it produces a byte-identical fragment when
   the measured structure is unchanged (avoids the #115 `SOURCE_DATE_EPOCH`
   churn class).
2. **No machine-dependent numbers in the committed fragment.** The
   MATLAB-generator metrics (code-lines, ROM/`.mat` bytes) are deterministic and
   emitted exact. The Coder- and host-sensitive figures — generated-C size
   (MATLAB Coder / toolchain-version dependent, and a poor ROM proxy per
   `bench/SHOWCASE.md`) and wall-clock `timeit` runtime — would rewrite the
   committed table on regeneration from a different image. Emit those as
   **relative ratios** (e.g. MEX-vs-interpreted runtime) or omit them from the
   committed fragment, pointing to `bench/SHOWCASE.md` for the absolute
   host-specific figures.

**Ownership / location.** The emitter is MATLAB-session bench code; the guide
`\input` wiring is this (docs) session's. Recommended: the committed fragment
lives under the guide (e.g. `docs/userguide/generated/bench_compare.tex`) with a
`% GENERATED — do not hand-edit` header, so the guide is self-contained and the
generated status is unmistakable; the exact path is an implementation detail for
the wiring PR.

**Revisit when:** the same B2-style pressure the original decision names — if a
needed table has no bench producer, a curated committed fragment (with a test
asserting it against the real bench output) is the fallback.

