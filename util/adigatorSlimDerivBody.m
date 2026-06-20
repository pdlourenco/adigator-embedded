function [newLines, info] = adigatorSlimDerivBody(mLines, fieldNames)
% adigatorSlimDerivBody  Slim a generated _ADiGator* derivative file by
% removing the statements that feed only output-struct fields the wrapper
% never reads (e.g. the '..._location'/'..._size' metadata in embed modes),
% so the now-unreferenced Gator*Data index tables drop in the subsequent
% prune. This is the R7b slice engine (issue #21); the embedded driver
% supplies fieldNames from adigatorWrapperDemand and wires this in before
% prune_adigator_mat, behind the opt-in slim_embed option.
%
% ------------------------------ Inputs --------------------------------- %
%   mLines     - string array (or cellstr) of the full _ADiGator* file.
%   fieldNames - cellstr of the output-struct field names the wrapper reads
%                (from adigatorWrapperDemand), e.g. {'f','dx'}.
%
% ------------------------------ Outputs -------------------------------- %
%   newLines - string column of the (possibly) slimmed file.
%   info     - struct: .sliced (logical), .dropped (lines removed), .reason
%              (why no slice happened, when .sliced is false).
%
% SAFETY. The function is conservative: on ANY condition it is not sure about
% - missing body markers, line continuations, an unparseable header, rolled
% control flow, no demanded fields, or a failed dependency-closure check - it
% returns mLines UNCHANGED with .sliced = false. The closure check is an
% eval-free numeric-equivalence guarantee for this side-effect-free
% straight-line dialect: if every base read by a kept statement is an input /
% Gator1Data or has ALL its writers kept, and every demanded output field is
% still produced, the slimmed file computes the demanded outputs identically
% (a dropped statement only ever removed a value nothing kept reads).
%
% Copyright GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%            R7b slice engine (issue #21).
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorFieldSlice, adigatorWrapperDemand, adigatorParseTape

mL = string(mLines);
mL = mL(:);
newLines = mL;
info = struct('sliced',false,'dropped',0,'reason','');

fieldNames = cellstr(string(fieldNames));
if isempty(fieldNames)
  info.reason = 'no demanded fields'; return
end

% --------------------------- locate the body --------------------------- %
bs = find(contains(mL,'ADiGator Start Derivative Computations'),1);
be = find(strtrim(mL) == "function ADiGator_LoadData()",1);
if isempty(bs) || isempty(be) || be <= bs+1
  info.reason = 'body markers not found'; return
end
body = mL(bs+1:be-1);
if any(endsWith(strtrim(body),'...'))
  info.reason = 'line continuation in body'; return % cannot line-slice safely
end

% ------------------------ header: outvar + inputs ---------------------- %
hi = find(startsWith(strtrim(mL),'function'),1);
[outvar, innames] = parseHeader(char(mL(hi)));
if isempty(outvar)
  info.reason = 'cannot parse derivative-function header'; return
end
demanded = strcat(outvar,'.',fieldNames(:).');

% ------------------------------- slice --------------------------------- %
try
  [~, keep, Sall] = adigatorFieldSlice(body, innames, demanded);
catch ME
  if startsWith(ME.identifier,'adigator:fwdtape')
    info.reason = ['cannot slice: ',ME.message]; return % e.g. rolled loops
  end
  rethrow(ME)
end
if all(keep)
  info.reason = 'no dead statements'; return
end

% ----------------- eval-free dependency-closure gate ------------------- %
[ok, why] = closureOk(Sall, keep, demanded, innames);
if ~ok
  info.reason = ['closure check failed: ',why]; return
end

% --------------------------- re-emit the file -------------------------- %
dropLines = [Sall(~keep).line];           % body-line indices to remove
bmask = true(numel(body),1);
bmask(dropLines) = false;
newLines = [mL(1:bs); body(bmask); mL(be:end)];
info.sliced  = true;
info.dropped = numel(dropLines);
end

%% --------------------------------------------------------------------- %%
function [outvar, innames] = parseHeader(hdr)
% parse 'function OUTVAR = NAME(in1,in2,...)'; OUTVAR='' for a bracketed
% (multi-output) header, which this slicer does not handle.
outvar = ''; innames = {};
tok = regexp(hdr,...
  '^\s*function\s+([A-Za-z]\w*)\s*=\s*[A-Za-z]\w*\s*\(([^)]*)\)',...
  'tokens','once');
if isempty(tok)
  return
end
outvar = tok{1};
ins = strtrim(strsplit(tok{2},','));
innames = ins(~cellfun(@isempty,ins));
end

%% --------------------------------------------------------------------- %%
function [ok, why] = closureOk(Sall, keep, demanded, innames)
% Verify the kept set is closed: every base read by a kept statement is an
% input / Gator1Data or has ALL of its writers kept (so partial-write/scatter
% values are intact), and every demanded output field is still produced.
ok = false; why = '';
external = [innames(:); {'Gator1Data'}];
keep  = logical(keep(:));
bases = cell(numel(Sall),1);                % base name written by each statement
for i = 1:numel(Sall)
  bases{i} = strtok(Sall(i).lhs,'.');
end

readBases = {};
for k = find(keep).'
  if ~isempty(Sall(k).deps)
    readBases = union(readBases,Sall(k).deps);
  end
end
for j = 1:numel(readBases)
  b = readBases{j};
  if any(strcmp(b,external))
    continue
  end
  isW = strcmp(bases,b);
  if ~any(isW)
    why = ['undefined base ',b]; return
  end
  if sum(isW & keep) ~= sum(isW)
    why = ['a writer of ',b,' was dropped']; return % would corrupt its value
  end
end

for j = 1:numel(demanded)
  d = demanded{j};
  base = strtok(d,'.');
  produced = false;
  for k = find(keep).'
    if strcmp(Sall(k).lhs,d) || strcmp(Sall(k).lhs,base)
      produced = true; break
    end
  end
  if ~produced
    why = ['demanded output ',d,' is not produced']; return
  end
end
ok = true;
end
