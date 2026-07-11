function info = adigatorSlimEmbeddedDeriv(genfile, UserFunInputs)
% adigatorSlimEmbeddedDeriv  Slim one generated derivative (R7b/R7c driver,
% issue #21): determine which output-struct fields the wrapper reads, field-
% slice the _ADiGator* derivative file to those (R7b), collapse no-op union
% copies in the surviving body (R7c), cross-check, and commit the rewritten
% file (so the now-unreferenced Gator*Data index tables drop in the subsequent
% prune). Conservative: on ANY uncertainty OR error the original file is left
% in place and generation continues unchanged - slimming must never break
% generation.
%
% ------------------------------ Inputs --------------------------------- %
%   genfile       - one element of the GenFiles struct array from
%                   adigatorGenJacFile/adigatorGenHesFile: fields .main (the
%                   wrapper file), .m (the _ADiGator* derivative file), .mat
%                   (the static-data file, still unpruned at this stage), .name
%                   (wrapper function), .dername (derivative function), .path.
%   UserFunInputs - the cell of inputs to the user function (for staging the
%                   numeric round-trip cross-check).
%
% ------------------------------ Output --------------------------------- %
%   info - struct: .sliced (logical: the field-slice applied), .dropped
%          (statements removed by the slice), .collapsed (union-copy pairs
%          collapsed by the peephole), .checked (whether the numeric round-trip
%          ran), .reason (why nothing was rewritten).
%
% Safety. The field-slice carries its own eval-free dependency-closure gate
% (the primary, always-on numeric-equivalence guarantee, ADR-0006); the union-
% copy peephole is provably equivalent-or-stricter by construction (it throws
% rather than mis-computes on a shape the pattern never produces, see
% adigatorPeepholeUnionCopy) - that is its standing guarantee. On top of both, a
% best-effort generation-time numeric round-trip cross-check here evaluates the
% still-classic-style wrapper (this runs BEFORE the embed patching) on staged
% inputs over the COMBINED rewrite and compares; it can only REJECT on a
% definite mismatch or be SKIPPED when it cannot run, never accept a wrong one.
% The round-trip is side-effect-free on genfile.m (it restores the original
% after its temporary eval), and the whole body is wrapped so any unexpected
% error restores the original file - the single authoritative write of the
% rewritten file is the one writelines below, reached only when accepted.
%
% Copyright Pedro Lourenço and GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%            R7b interprocedural slice driver, R7c union-copy peephole (#21).
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorWrapperDemand, adigatorSlimDerivBody, adigatorPeepholeUnionCopy, adigatorGenDerFile_embedded

info = struct('sliced',false,'dropped',0,'collapsed',0,'checked',false,'reason','');

try
  wrapperLines = readlines(genfile.main);
  origLines    = readlines(genfile.m);
catch
  info.reason = 'cannot read generated files'; return
end

try
  % which output-struct fields does the wrapper actually read?
  [resvar, fields] = adigatorWrapperDemand(wrapperLines, genfile.dername);
  if isempty(resvar)
    info.reason = 'wrapper demand unresolved'; return
  end

  % R7b: field-slice the derivative file to those fields (closure-gated).
  % adigatorSlimDerivFile is interprocedural (issue #44 / ADR-0009): it slices
  % across subfunction calls and delegates to the intra-function
  % adigatorSlimDerivBody for a single-derivative-function file.
  [slicedLines, sinfo] = adigatorSlimDerivFile(origLines, fields);
  working = origLines;
  if sinfo.sliced
    working = slicedLines;
  end

  % R7c (issue #21): collapse no-op union copies in the (possibly sliced) body,
  % resolving the Gator*Data index tables from the still-unpruned .mat. Provably
  % equivalent-or-stricter, so - like the slice's closure gate - it is the
  % standing guarantee when the best-effort round-trip below is skipped.
  pinfo = struct('changed',false,'count',0);
  gatorData = loadGatorData(genfile);
  if ~isempty(gatorData)
    [peepLines, pinfo] = adigatorPeepholeUnionCopy(working, gatorData);
    if pinfo.changed
      working = peepLines;
    end
  end

  if ~sinfo.sliced && ~pinfo.changed
    info.reason = sinfo.reason; return % nothing to rewrite -> leave original
  end

  % best-effort numeric round-trip cross-check over the COMBINED rewrite
  % (ADR-0006). It leaves genfile.m holding the ORIGINAL on return, so on a
  % mismatch there is nothing to undo.
  [ran, equal] = roundtripCheck(genfile, UserFunInputs, origLines, working);
  if ran && ~equal
    info.reason = 'numeric round-trip mismatch'; return
  end

  % accept (covers ran==false: the closure gate and the peephole's provable
  % equivalence are the standing guarantees). The only authoritative write.
  writelines(working, genfile.m);
  info.sliced    = sinfo.sliced;
  info.dropped   = sinfo.dropped;
  info.collapsed = pinfo.count;
  info.checked   = ran;
catch err
  % never break generation: restore the original and continue unchanged
  ensureOriginal(genfile, origLines);
  info = struct('sliced',false,'dropped',0,'collapsed',0,'checked',false, ...
    'reason',['left unchanged after error: ',err.message]);
end
end

%% --------------------------------------------------------------------- %%
function gd = loadGatorData(genfile)
% Load the per-function constant tables (Gator*Data, with the Index* arrays the
% peephole resolves) for the main derivative function from the still-unpruned
% .mat. Returns [] on any problem so the peephole is simply skipped. The data
% layout (struct.<func>.Gator<D>Data.Index<N>) matches prune_adigator_mat.
gd = [];
try
  s = load(genfile.mat);
  if isfield(s, genfile.dername) && isstruct(s.(genfile.dername))
    gd = s.(genfile.dername);
  end
catch
  % any load/field problem -> gd stays [] and the peephole is skipped
end
end

%% --------------------------------------------------------------------- %%
function [ran, equal] = roundtripCheck(genfile, UserFunInputs, origLines, newLines)
% Evaluate the wrapper (still classic-style at this pipeline stage) on staged
% inputs before and after the slimmed derivative file, and compare. Restores
% genfile.m to the original on every exit (normal or error) via onCleanup, so
% this check never leaves a side effect on disk.
ran = false; equal = false;

staged = stageInputs(UserFunInputs);
if isempty(staged)
  return % cannot construct staged inputs -> rely on the closure gate
end

savedPath = path;
addpath(genfile.path);
% `cleaner` must stay a named variable so its destructor (restoreEnv) fires
% when this function exits - including on error. (Modern checkcode recognises
% the onCleanup pattern and does not flag the assignment as unused.)
cleaner = onCleanup(@() restoreEnv(savedPath, genfile, origLines));

nout = abs(nargout(genfile.name));
if nout < 1
  return
end

% original derivative file (on disk now)
refresh(genfile);
try
  out0 = cell(1,nout);
  [out0{:}] = feval(genfile.name, staged{:});
catch
  return % the wrapper does not evaluate in this environment -> skip the check
end

% slimmed derivative file (restored to original by the onCleanup above)
writelines(newLines, genfile.m);
refresh(genfile);
try
  out1 = cell(1,nout);
  [out1{:}] = feval(genfile.name, staged{:});
catch
  ran = true; equal = false; return % slice broke evaluation -> reject
end

ran   = true;
equal = outputsEqual(out0, out1);
end

%% --------------------------------------------------------------------- %%
function staged = stageInputs(UserFunInputs)
% Replace each adigatorInput with a positive random array of its size; pass
% fixed numeric inputs through. Positive values (0.1 + rand) avoid log/sqrt-
% domain errors that would otherwise make the original eval throw and silently
% skip the check. Returns {} (skip the check) for vectorized (Inf) sizes or
% non-numeric (struct/cell) inputs, which this cross-check does not stage - the
% closure gate still guarantees correctness in those cases.
staged = {};
out = UserFunInputs;
for i = 1:numel(out)
  ui = out{i};
  if isa(ui,'adigatorInput')
    sz = ui.func.size;
    if numel(sz) ~= 2 || any(~isfinite(sz)) || any(sz < 1)
      return
    end
    out{i} = 0.1 + rand(sz);
  elseif ~isnumeric(ui)
    return
  end
end
staged = out;
end

%% --------------------------------------------------------------------- %%
function tf = outputsEqual(a, b)
% Outputs should be bit-identical (the slice drops dead statements only, never
% changing the arithmetic of a kept one), so compare exactly (sparse->full).
tf = numel(a) == numel(b);
for i = 1:numel(a)
  if ~tf
    return
  end
  x = a{i}; y = b{i};
  if issparse(x); x = full(x); end
  if issparse(y); y = full(y); end
  tf = isequaln(x, y);
end
end

%% --------------------------------------------------------------------- %%
function refresh(genfile)
% Force MATLAB to reload the (rewritten) derivative function and its data.
clear(genfile.dername);
clear('global',['ADiGator_',genfile.dername]);
rehash;
end

%% --------------------------------------------------------------------- %%
function restoreEnv(savedPath, genfile, origLines)
% Restore the derivative file (the round-trip may have written the slimmed
% candidate to evaluate it), then the path and the cached global. The global
% name matches GlobalVarName in lib/adigatorFunctionInitialize.m
% ('ADiGator_' + the derivative-file name).
try
  writelines(origLines, genfile.m);
catch
  % a failed restore here means a disk-level problem; nothing more to do
end
path(savedPath);
clear('global',['ADiGator_',genfile.dername]);
end

%% --------------------------------------------------------------------- %%
function ensureOriginal(genfile, origLines)
% Best-effort restore of the original derivative file after an unexpected
% error, so a failed slim never leaves a mutated artifact behind.
try
  writelines(origLines, genfile.m);
catch
  % a failed restore here means a disk-level problem; nothing more to do
end
end
