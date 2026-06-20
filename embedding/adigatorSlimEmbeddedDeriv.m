function info = adigatorSlimEmbeddedDeriv(genfile, UserFunInputs)
% adigatorSlimEmbeddedDeriv  Slim one generated derivative (R7b driver, issue
% #21): determine which output-struct fields the wrapper reads, field-slice
% the _ADiGator* derivative file to those, cross-check, and commit the slimmed
% file (so the now-unreferenced Gator*Data index tables drop in the subsequent
% prune). Conservative: on ANY uncertainty OR error the original file is left
% in place and generation continues unsliced - slimming must never break
% generation.
%
% ------------------------------ Inputs --------------------------------- %
%   genfile       - one element of the GenFiles struct array from
%                   adigatorGenJacFile/adigatorGenHesFile: fields .main (the
%                   wrapper file), .m (the _ADiGator* derivative file), .name
%                   (wrapper function), .dername (derivative function), .path.
%   UserFunInputs - the cell of inputs to the user function (for staging the
%                   numeric round-trip cross-check).
%
% ------------------------------ Output --------------------------------- %
%   info - struct: .sliced (logical), .dropped (statements removed), .checked
%          (whether the numeric round-trip ran), .reason (why not sliced).
%
% Safety. Two independent guards, both bail-to-original on failure: the
% eval-free dependency-closure gate inside adigatorSlimDerivBody (the primary,
% always-on numeric-equivalence guarantee, ADR-0006), and a best-effort
% generation-time numeric round-trip cross-check here (it evaluates the still-
% classic-style wrapper - this runs BEFORE the embed patching - on staged
% inputs and compares; it can only REJECT a slim on a definite mismatch or be
% SKIPPED when it cannot run, never accept a wrong one). The round-trip is
% side-effect-free on genfile.m (it restores the original after its temporary
% eval), and the whole body is wrapped so any unexpected error restores the
% original file - the single authoritative write of the slimmed file is the
% one writelines below, reached only when the slim is accepted.
%
% Copyright GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%            R7b interprocedural slice driver (issue #21).
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorWrapperDemand, adigatorSlimDerivBody, adigatorGenDerFile_embedded

info = struct('sliced',false,'dropped',0,'checked',false,'reason','');

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

  % field-slice the derivative file to those fields (closure-gated internally)
  [newLines, sinfo] = adigatorSlimDerivBody(origLines, fields);
  if ~sinfo.sliced
    info.reason = sinfo.reason; return
  end

  % best-effort numeric round-trip cross-check (ADR-0006). It leaves genfile.m
  % holding the ORIGINAL on return, so on a mismatch there is nothing to undo.
  [ran, equal] = roundtripCheck(genfile, UserFunInputs, origLines, newLines);
  if ran && ~equal
    info.reason = 'numeric round-trip mismatch'; return
  end

  % accept the slice (covers ran==false: the closure gate is the standing
  % guarantee). This is the only authoritative write of the slimmed file.
  writelines(newLines, genfile.m);
  info.sliced  = true;
  info.dropped = sinfo.dropped;
  info.checked = ran;
catch err
  % never break generation: restore the original and continue unsliced
  ensureOriginal(genfile, origLines);
  info = struct('sliced',false,'dropped',0,'checked',false, ...
    'reason',['left unsliced after error: ',err.message]);
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
cleaner = onCleanup(@() restoreEnv(savedPath, genfile, origLines)); %#ok<NASGU>

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
