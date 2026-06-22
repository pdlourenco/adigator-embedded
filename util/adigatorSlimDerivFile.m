function [newLines, info] = adigatorSlimDerivFile(mLines, fieldNames)
% adigatorSlimDerivFile  Interprocedural field-slice of a generated _ADiGator*
% derivative file (issue #44 item 1; ADR-0009). The interprocedural layer over
% adigatorFieldSlice: it lets the R7b slice cross subfunction-call boundaries.
%
% A generated derivative whose user function calls subfunctions (e.g.
% gapfun -> conefun -> setfun) is emitted as ONE file with several
% 'function ... = ADiGator_<sub>(...)' blocks that the main derivative function
% calls. The intra-function slicer (adigatorSlimDerivBody) grabs a single body
% span (Start marker -> first 'function ADiGator_LoadData()'), which swallows
% those subfunction 'function'/'end' lines and makes the tape parser bail, so
% the whole file is left unsliced. This driver instead:
%
%   1. splits the file into its per-function blocks (main derivative function,
%      each ADiGator_* subfunction, the ADiGator_LoadData trailer);
%   2. runs a FORWARD worklist fixpoint over (function, demanded-output-field-
%      set): the main function is seeded with the wrapper-demanded fields, and a
%      callee's demand is the union, over the kept call sites, of the result-
%      struct fields the caller actually reads there. (No backward edge is
%      needed: keeping a call statement keeps its argument at base granularity,
%      which keeps the argument-struct assembly, so the producers are pulled in
%      by the ordinary intra-function slice.)
%   3. field-slices each block with adigatorFieldSlice under the SAME eval-free
%      per-function dependency-closure gate as adigatorSlimDerivBody (ADR-0006),
%      and reassembles, dropping only dead body lines.
%
% For a single-derivative-function file (no ADiGator_* subfunctions) it
% delegates to adigatorSlimDerivBody, so the proven intra-function path is
% byte-for-byte unchanged.
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
% SAFETY. Conservative throughout: on ANY uncertainty - an unparseable split, a
% call site whose result/arguments cannot be read, an unknown callee, a call
% graph cycle, a per-function slice error (line continuations, top-level
% while/if/switch), ANY rolled 'for...end' in a multi-subfunction file (whose
% interior the top-level call/field scans do not see - see sliceOneBlock), or a
% failed closure check in ANY block - it returns mLines UNCHANGED with
% .sliced = false. It never emits a partial,
% possibly-inconsistent rewrite. The closure gate is the same eval-free
% numeric-equivalence guarantee adigatorSlimDerivBody documents, applied per
% function; the driver's whole-file numeric round-trip is the combined
% cross-check (ADR-0006/0009).
%
% Copyright GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%            R7b interprocedural field-slice (issue #44 item 1, ADR-0009).
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorSlimDerivBody, adigatorFieldSlice, adigatorWrapperDemand,
%          adigatorParseTape, adigatorSlimEmbeddedDeriv

mL = string(mLines);
mL = mL(:);
newLines = mL;
info = struct('sliced',false,'dropped',0,'reason','');

fieldNames = cellstr(string(fieldNames));
fieldNames = fieldNames(:).';
if isempty(fieldNames)
  info.reason = 'no demanded fields'; return
end

% --------------------------- split into blocks ------------------------- %
[blocks, ok, why] = splitBlocks(mL);
if ~ok
  info.reason = why; return
end
isDeriv  = [blocks.isDeriv];
derivIdx = find(isDeriv);
if isempty(derivIdx)
  info.reason = 'no derivative function body found'; return
end
mainIdx = derivIdx(1);

% single derivative function -> proven intra-function path, unchanged
if isscalar(derivIdx)
  [newLines, info] = adigatorSlimDerivBody(mL, fieldNames);
  return
end

derivNames = string({blocks(derivIdx).name});

% ------------------- forward worklist demand fixpoint ------------------ %
% demand{i} (over derivIdx) is a cellstr of demanded outputs for that block,
% each 'outvar.field' (or a bare 'outvar' for a whole-struct read). Seed main.
demand = repmat({{}}, 1, numel(derivIdx));
mainPos = find(derivIdx == mainIdx,1);
demand{mainPos} = strcat(blocks(mainIdx).outvar,'.',fieldNames);

inWork = false(1, numel(derivIdx));
queue  = mainPos;
inWork(mainPos) = true;
guard  = 0;
% Demand sets only grow (union) over the finite (outvar x field) universe, so
% the fixpoint always terminates; this generous bound (assuming the small
% per-struct field counts of generated derivatives) is a belt-and-suspenders
% guard that, if ever hit, only bails the whole file unsliced - never wrong.
maxIter = 100 * numel(derivIdx) + 100;
while ~isempty(queue)
  guard = guard + 1;
  if guard > maxIter
    info.reason = 'demand fixpoint did not converge'; return
  end
  pos = queue(1); queue(1) = [];
  inWork(pos) = false;
  bi = derivIdx(pos);

  [keep, Sall, sok, swhy] = sliceOneBlock(blocks(bi), demand{pos});
  if ~sok
    info.reason = swhy; return
  end

  % forward edge: every kept call site pushes its read result-fields as demand
  [calls, cok] = callSites(Sall, keep, derivNames);
  if ~cok
    info.reason = 'unparseable subfunction call site'; return
  end
  for c = 1:numel(calls)
    cpos = find(strcmp(calls(c).callee, derivNames), 1);
    if isempty(cpos)
      info.reason = ['call to unknown function ',char(calls(c).callee)]; return
    end
    fr = fieldsRead(Sall, keep, calls(c).result);
    cb = derivIdx(cpos);
    if isequal(fr,'WHOLE')
      newd = {blocks(cb).outvar};
    else
      newd = strcat(blocks(cb).outvar,'.',fr);
    end
    merged = union(demand{cpos}, newd);
    if numel(merged) > numel(demand{cpos})
      demand{cpos} = merged;
      if ~inWork(cpos)
        queue(end+1) = cpos; inWork(cpos) = true; %#ok<AGROW>
      end
    end
  end
end

% --------------- final per-block slice with settled demand ------------- %
% drop dead body lines per block (global line = block.bodyStart-1 + local idx)
dropMask = false(numel(mL),1);
anyDrop  = false;
for pos = 1:numel(derivIdx)
  bi = derivIdx(pos);
  if isempty(demand{pos})
    continue   % a never-demanded (dead) subfunction: leave whole, conservatively
  end
  [keep, Sall, sok, swhy] = sliceOneBlock(blocks(bi), demand{pos});
  if ~sok
    info.reason = swhy; return
  end
  if all(keep)
    continue
  end
  for k = find(~keep(:)).'
    span = Sall(k).line:Sall(k).lineEnd;            % local to the block body
    dropMask(blocks(bi).bodyStart - 1 + span) = true;
    anyDrop = true;
  end
end

if ~anyDrop
  info.reason = 'no dead statements'; return
end

newLines = mL(~dropMask);
info.sliced  = true;
info.dropped = nnz(dropMask);
end

%% --------------------------------------------------------------------- %%
function [keep, Sall, ok, why] = sliceOneBlock(blk, demanded)
% Field-slice one derivative block's body to its demanded outputs and run the
% per-function closure gate. ok=false (with why) on a slice error or a closure
% failure, so the caller bails the whole file.
keep = []; Sall = []; ok = false; why = '';
body = blk.body;
if any(endsWith(strtrim(body),'...'))
  why = ['line continuation in ',blk.name,' body']; return
end
try
  [~, keep, Sall] = adigatorFieldSlice(body, blk.innames, demanded);
catch ME
  if startsWith(ME.identifier,'adigator:fwdtape')
    why = ['cannot slice ',blk.name,': ',ME.message]; return
  end
  rethrow(ME)
end
% Conservative scope (ADR-0009): the interprocedural forward-demand and call-
% site scans read only top-level statement text, so a subfunction call OR a
% result-field read hidden INSIDE a rolled 'for...end' would be missed and
% under-demand a callee - a wrong derivative. So bail the WHOLE file unsliced if
% any rolled loop appears in a multi-subfunction file. (A single-subfunction
% rolled-loop file never reaches here: it goes through adigatorSlimDerivBody,
% which handles the loop-as-a-unit with no cross-call demand to get wrong.)
if any([Sall.block])
  why = ['rolled loop in interprocedural file (',blk.name, ...
    '); conservative bail']; return
end
[cok, cwhy] = closureOk(Sall, keep, demanded, blk.innames);
if ~cok
  why = ['closure check failed in ',blk.name,': ',cwhy]; return
end
ok = true;
end

%% --------------------------------------------------------------------- %%
function [blocks, ok, why] = splitBlocks(mL)
% Split a generated file into top-level function blocks. Each block:
%   .name .outvar .innames .headerLine .endLine .bodyStart .bodyEnd .body
%   .isDeriv (true iff it carries a 'Start Derivative Computations' marker and
%            a parseable single-output header).
%
% Functions are delimited by their '^function' headers; a function spans from
% its header to the line before the next header (or EOF). Its closing 'end' is
% the LAST whole-line 'end' in that span - which comes after every inner rolled
% 'for...end' (whose 'end's are earlier) and after the trailing statements.
% Keying on a whole trimmed line == 'end' deliberately ignores both the
% generated one-line guard 'if isempty(GLOBAL); ADiGator_LoadData(); end' and
% any 'end' that appears inside a subscript - neither is a block close.
blocks = struct('name',{},'outvar',{},'innames',{},'headerLine',{}, ...
  'endLine',{},'bodyStart',{},'bodyEnd',{},'body',{},'isDeriv',{});
ok = false; why = '';
n = numel(mL);
isHeader = false(n,1);
for i = 1:n
  if ~isempty(regexp(strtrim(char(mL(i))),'^function\>','once'))
    isHeader(i) = true;
  end
end
H = find(isHeader);
if isempty(H)
  why = 'no function blocks found'; return
end
for hi = 1:numel(H)
  startL = H(hi);
  if hi < numel(H)
    spanEnd = H(hi+1) - 1;
  else
    spanEnd = n;
  end
  endL = [];
  for e = spanEnd:-1:startL+1
    if strcmp(strtrim(char(mL(e))),'end')
      endL = e; break
    end
  end
  if isempty(endL)
    why = 'function block without a closing end'; return
  end
  [outvar, innames, fname, hok] = parseHeader(strtrim(char(mL(startL))));
  if ~hok
    why = 'cannot parse a function header'; return
  end
  rel = find(contains(mL(startL+1:endL-1), ...
    'ADiGator Start Derivative Computations'),1);
  if ~isempty(rel) && ~isempty(outvar)
    mk = startL + rel;           % (startL+1) + rel - 1
    isDeriv   = true;
    bodyStart = mk + 1;
    bodyEnd   = endL - 1;
    body      = mL(bodyStart:bodyEnd);
  else
    isDeriv = false; bodyStart = NaN; bodyEnd = NaN; body = strings(0,1);
  end
  blocks(end+1) = struct('name',fname,'outvar',outvar,'innames',{innames}, ...
    'headerLine',startL,'endLine',endL,'bodyStart',bodyStart,'bodyEnd',bodyEnd, ...
    'body',body,'isDeriv',isDeriv); %#ok<AGROW>
end
ok = true;
end

%% --------------------------------------------------------------------- %%
function [outvar, innames, fname, ok] = parseHeader(hdr)
% Parse 'function OUTVAR = NAME(in1,...)' -> outvar/innames/fname, or a
% no-output header 'function NAME(...)' (e.g. ADiGator_LoadData) -> outvar=''.
% ok=false only when the line is not a recognisable function header at all.
outvar = ''; innames = {}; fname = ''; ok = false;
tok = regexp(hdr, ...
  '^\s*function\s+([A-Za-z]\w*)\s*=\s*([A-Za-z]\w*)\s*\(([^)]*)\)', ...
  'tokens','once');
if ~isempty(tok)
  outvar  = tok{1};
  fname   = tok{2};
  ins     = strtrim(strsplit(tok{3},','));
  innames = ins(~cellfun(@isempty,ins));
  ok = true; return
end
tok = regexp(hdr,'^\s*function\s+([A-Za-z]\w*)\s*\(([^)]*)\)','tokens','once');
if ~isempty(tok)
  fname   = tok{1};
  ins     = strtrim(strsplit(tok{2},','));
  innames = ins(~cellfun(@isempty,ins));
  ok = true; return
end
end

%% --------------------------------------------------------------------- %%
function [calls, ok] = callSites(Sall, keep, derivNames)
% The kept call statements 'X = ADiGator_<sub>(arg1,...)'. Each entry has
% .result (X) and .callee (the subfunction name). ok=false if a statement whose
% RHS is a bare call to one of derivNames cannot be parsed into result+callee.
calls = struct('result',{},'callee',{});
ok = true;
for k = find(keep(:)).'
  rhs = strtrim(char(Sall(k).rhs));
  tok = regexp(rhs,'^([A-Za-z]\w*)\s*\((.*)\)$','tokens','once');
  if isempty(tok)
    continue
  end
  callee = string(tok{1});
  if ~any(callee == derivNames)
    continue   % a call to a non-derivative function (library/builtin): not ours
  end
  lhs = char(Sall(k).lhs);
  if isempty(lhs) || contains(lhs,'.') || ~isempty(Sall(k).lhsSubs)
    ok = false; return   % a call must assign a whole result struct
  end
  calls(end+1) = struct('result',lhs,'callee',callee); %#ok<AGROW>
end
end

%% --------------------------------------------------------------------- %%
function fr = fieldsRead(Sall, keep, resultVar)
% Which fields of <resultVar> the kept statements read: a cellstr of field
% names, or the string 'WHOLE' if the result struct is read whole anywhere (a
% bare <resultVar> token not followed by '.'). Mirrors adigatorWrapperDemand's
% extraction, over the kept derivative-block statements rather than a wrapper.
rv     = regexptranslate('escape',resultVar);
barepat = ['\<',rv,'\>(?!\.)'];
fldpat  = ['\<',rv,'\.([A-Za-z]\w*)'];
found = {};
for k = find(keep(:)).'
  % skip the call's own LHS assignment: 'resultVar = callee(...)'
  if strcmp(strtok(char(Sall(k).lhs),'.'),resultVar) && isempty(Sall(k).lhsSubs)
    continue
  end
  txt = char(Sall(k).text);
  if ~isempty(regexp(txt,barepat,'once'))
    fr = 'WHOLE'; return
  end
  toks = regexp(txt,fldpat,'tokens');
  for t = 1:numel(toks)
    found{end+1,1} = toks{t}{1}; %#ok<AGROW>
  end
end
fr = unique(found(:)).';
if isempty(fr)
  fr = 'WHOLE';   % kept but no field read found -> demand all, conservatively
end
end

%% --------------------------------------------------------------------- %%
function [ok, why] = closureOk(Sall, keep, demanded, innames)
% Per-function eval-free closure gate (identical reasoning to
% adigatorSlimDerivBody/closureOk): every base read by a kept statement is an
% input / Gator1Data or has ALL its writers kept, and every demanded output
% field is still produced.
ok = false; why = '';
external = [innames(:); {'Gator1Data'}];
keep  = logical(keep(:));
writers = {Sall.writes};

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
  isW = cellfun(@(w) any(strcmp(b,w)),writers);
  if ~any(isW)
    why = ['undefined base ',b]; return
  end
  if sum(isW & keep(:).') ~= sum(isW)
    why = ['a writer of ',b,' was dropped']; return
  end
end

demanded = cellstr(string(demanded));
for j = 1:numel(demanded)
  d = demanded{j};
  base = strtok(d,'.');
  produced = false;
  for k = find(keep).'
    if strcmp(Sall(k).lhs,d) || any(strcmp(base,Sall(k).writes))
      produced = true; break
    end
  end
  if ~produced
    why = ['demanded output ',d,' is not produced']; return
  end
end
ok = true;
end
