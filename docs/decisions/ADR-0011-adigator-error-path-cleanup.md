# ADR-0011 — `adigator.m` releases transformation state on every exit

## Status

Accepted — 2026-06-22. Issue [#38](https://github.com/pdlourenco/adigator-embedded/issues/38)
(roadmap R9 Phase B.3). Fixes bug **B16** (`docs/ANALYSIS.md` §1.3b);
pins `docs/CI_PLAN.md` REQ-T-07 / REQ-C-09 (the B13 family).

## Context

`adigator()` acquires three pieces of session state during a transformation:
the four transformation-state globals (`ADIGATOR ADIGATORFORDATA ADIGATORDATA
ADIGATORVARIABLESTORAGE`), a temp dir that it creates and **adds to the MATLAB
path**, and the file handles it opens (`Dfid` for the generated file, `Tfid`
per intermediate file). Originally all three were released only on the
**success path** (a trailing `clear global …`, `rmpath`/`rmdir`,
`fclose('all')`). The single `try/catch` guarded only the initial user-function
eval and rethrew **without** releasing anything.

So any error in the ~600-line transformation body left stray `ADIGATOR*`
globals, the temp dir still on the path, and (past the point `Dfid` opens) an
open file handle — exactly the REQ-T-07 hygiene contract ("raise clean errors,
restore the MATLAB path, close all file handles, leave no stray globals"). The
issue-#38 Monte-Carlo `oracleHygiene` prototype caught it on its first run: a
malformed fixture left a non-empty `who('global')` delta. This is a genuine
robustness bug for any caller that runs `adigator` in a loop or a test suite
(one failure poisons every later transformation), which is why it is fixed in
core rather than worked around in the harness.

The forces: cleanup must run on **every** exit (the success tail is not enough);
it must not clear the runtime data global `ADiGator_<name>` (the generated file
loads it on first call); and it should not close file handles the *caller* had
open before invoking `adigator` (embedding contexts).

## Decision

Release the three kinds of state **two ways**, on every exit (normal or error):

**Globals — cleared from a non-declaring helper subfunction.** The four
transformation globals are cleared by `adigatorClearTransformGlobals()` — a
subfunction that does **not** declare them `global` and just runs
`clear global ADIGATOR …` — called once on the normal path (the last body
statement) and once in a `catch` that wraps the body and rethrows. The decisive
constraint, found empirically (and confirmed in-situ against the real
`adigatorGenJacFile` flow): a literal `clear global` issued from `adigator`'s
**own** frame — which *declares* these globals via the `global` statement at the
top — is unreliable on the **success** path; it **re-registers** the named
globals empty instead of removing them, leaving a stray (empty) `ADIGATOR` in
`who('global')`. (The error path's identical in-frame clear happened to release
cleanly, so the leak was success-path-only and stayed invisible until a
*positive*-path `who('global')` check existed — `UCoreErrorHygieneTest`, the
test that caught it.) Clearing from a helper frame that never declares these
globals releases them on **both** paths. The resource cleanup below must
likewise hold no `global` declaration — an `onCleanup` callback that re-declares
a still-live global re-registers it empty.

As **defense-in-depth**, the runtime-data global `ADiGator_<name>` is
eval-declared in its own subfunction (`adigatorLoadRuntimeData`), never in
`adigator`'s frame: that keeps `adigator`'s frame free of an eval-declared
global (one known way to provoke the re-registration footgun). The move-out is
*necessary hygiene but not sufficient* — empirically the in-frame clear still
leaked on success after it, which is why the non-declaring-helper clear is the
load-bearing fix.

```matlab
adigatorEntryFids = adigatorOpenFids();   % handles open at entry (openedFiles / fopen('all'))
try
  …                                         % file-keeping, transformation
  adigatorLoadRuntimeData(FILENAME, MATPATH);  % eval-global in a SUBFUNCTION frame, not here
  …                                         % output assignment
catch adigatorErr
  adigatorClearTransformGlobals();          % clears from a non-declaring frame
  rethrow(adigatorErr)
end
adigatorClearTransformGlobals();

function adigatorClearTransformGlobals()
clear global ADIGATOR ADIGATORFORDATA ADIGATORDATA ADIGATORVARIABLESTORAGE
end
```

**Temp dir + file handles — released by a by-value `onCleanup`.** Registered
once `filekeeping` has created the temp dir, capturing the temp dir and the
entry-time `fopen('all')` snapshot **by value** (no `global` declaration, so it
cannot resurrect the cleared globals):

```matlab
adigatorResourceCleanup = onCleanup(@() adigatorReleaseResources(adigatorTempDir, adigatorEntryFids));
```

`adigatorReleaseResources(tempdir, entryFids)` closes every handle adigator
opened during the call — the user source files (`FunctionInfo(*).File.fid`), the
per-function temp files (`Tfid`/`TempFID`) and the generated file (`Dfid`) —
computed as `setdiff(fopen('all'), entryFids)`, the **delta** against the entry
snapshot, then drops the temp dir from the path (`rmpath`, with the
`MATLAB:rmpath:DirNotFound` warning suppressed) and deletes it. The runtime data
global `ADiGator_<name>` is **never** cleared — the generated file needs it.

The delta approach makes the handle close *complete*: adigator opens read
handles in several places (`adigator.m` source-file `fopen(...,'r')`,
`lib/adigatorFunctionInitialize.m`'s `TempFID`) that the original code closed
only via the blanket `fclose('all')`; closing the snapshot delta covers all of
them without enumerating each site, while leaving a caller's own open files
(those already open at entry) untouched.

The old success-path release was removed, so release happens exactly once. The
three helpers (`adigatorClearTransformGlobals`, `adigatorLoadRuntimeData`,
`adigatorReleaseResources`) are top-level **subfunctions**, not nested functions:
each has its own non-static workspace, so `adigatorClearTransformGlobals` clears
from a frame that never declared the globals, `adigatorLoadRuntimeData` can
`eval`-declare the runtime global without touching `adigator`'s frame, and
`adigatorReleaseResources` takes its state by value. Pinned by
**`UCoreErrorHygieneTest`** (gated `tests/unit`: success *and* error path) and, in
the extended suite, the `mcGenNegative` / `oracleHygiene` pair (error path) plus
`MCSmokeTest.successLeavesNoOpenHandles`.

## Consequences

- **Easier:** `adigator` is now safe to call in a loop / test campaign — a
  failed transformation cannot poison later ones. REQ-T-07 is pinned, and the
  B13 family is no longer "unpinned" in `CI_PLAN.md`.
- **Constrained:** the global clear must be issued from a frame that does **not**
  declare these globals (the `adigatorClearTransformGlobals` helper); a future
  edit that inlines `clear global …` back into `adigator`'s own (declaring) frame
  will reintroduce the success-path leak. The body must still stay inside the
  `try` so both exits route through the helper. The snapshot-delta close assumes
  every handle open at exit that was *not* open at entry belongs to adigator (a
  handle the user function opens *during* the initial eval is in the delta and
  gets closed — acceptable, and stricter only than a caller-held handle).
- **Behavioural note:** the resource cleanup runs as the function unwinds, i.e.
  *after* the output arguments are assigned. Handle-closing is now scoped to the
  handles adigator opened during the call rather than the old blanket
  `fclose('all')`, so a caller's pre-existing open files survive a transformation
  (a small,
  deliberate behaviour change).
- **Revisit if:** a future need arises to keep one of adigator's own handles
  open past return, in which case exclude it from the delta explicitly.

## Alternatives considered

- **`onCleanup` does everything, including `clear global`.** The first cut: a
  single `onCleanup(@adigatorCleanupState)` whose callback re-declared the four
  globals (to read state parked on `ADIGATOR.CLEANUP`) and then `clear global`'d
  them. Rejected after it **failed on R2023a**: a callback that *re-declares* a
  global still live in `adigator`'s frame and then clears it re-registers it
  empty, so `who('global')` kept `{'ADIGATOR'}` after every call. The handle/path
  release — which needs no `global` — belongs in the `onCleanup`; the global
  clear does not.
- **In-frame `clear global` in `adigator`'s own frame (with the `eval`-load moved
  out).** The second cut (commit `590bfe4`): clear literally in `adigator`'s frame
  on both paths, having moved the runtime-global `eval`-load to a subfunction so
  the frame holds no eval-declared global. The error path released cleanly, but
  the **success path still leaked** `{'ADIGATOR'}` empirically — `adigator`'s
  frame *declares* the four globals (the top `global` statement), and a literal
  `clear global` from within that declaring frame re-registers them empty on the
  success path regardless of the `eval` move. Rejected: an in-situ probe against
  the real `adigatorGenJacFile` flow showed the in-frame clear leaks
  (`leaked_inframe = {'ADIGATOR'}`) while the non-declaring-helper clear releases
  (`leaked_after_helper = {}`). The move-out is kept as defense-in-depth but is
  not the fix.
- **`onCleanup` with a nested cleanup function.** The most direct way to see the
  live `adigatorTempDir`. Rejected: a function that *hosts* a nested function gets
  a static workspace, and the cleanup is registered before the transformation
  runs — a by-value subfunction gives the same result without coupling cleanup to
  `adigator`'s workspace, and is portable. (Historically this was also forced by
  the `eval`-created `ADiGator_<name>` global living in `adigator`'s frame; that
  `eval` now lives in `adigatorLoadRuntimeData`, so the constraint it imposed has
  moved there, but the subfunction-not-nested choice stands on its own.)
- **A single shared release subfunction called from both the success tail and
  the `catch` (no `onCleanup`).** Viable, but the `onCleanup` is the idiomatic
  way to guarantee the temp dir / handles are released even on an exit path a
  future edit forgets to route through the tail; the `catch` is needed anyway
  only to route the global clear through the helper on the error path, so the
  split keeps each mechanism doing what it is good at.
- **`fclose('all')` in the cleanup** (matching the old success path). Rejected:
  it also closes file handles the caller had open before calling `adigator`.
- **Tracking each adigator-owned fid in its own `CLEANUP` slot** (`DFID`/`TFID`,
  …). Rejected: adigator opens handles at several sites across two files
  (`adigator.m` source reads, `adigatorFunctionInitialize.m`'s `TempFID`), so a
  per-slot scheme is easy to leave incomplete — an unregistered `fopen` silently
  leaks. The entry snapshot + `setdiff` close is complete by construction and
  needs no per-site bookkeeping, at the cost of one `fopen('all')` call at entry.
- **Fix only the globals (not the path / handles).** Rejected: REQ-T-07 names
  all three; a leaked path entry and open handle are equally part of the
  hygiene contract the fuzzer checks.
