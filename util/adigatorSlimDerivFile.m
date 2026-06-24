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
% A rolled 'for...end' in a multi-subfunction file is sliced as a unit, not
% bailed on (R10(a), issue #44 item 1): the call-site and result-field scans are
% block-aware (they read the loop body), so a subfunction call or a callee-
% result-field read nested in a kept loop is seen and its demand propagated.
% Because demand is a may-analysis, scanning the loop body can only over-demand
% (keep more), never under-demand. The loop's value chain is kept/dropped whole
% by the field-slice's atomic-block handling, under the same closure gate.
%
% SAFETY. Conservative throughout: on ANY uncertainty - an unparseable split, a
% call site whose result/arguments cannot be read (including a call nested in a
% loop that does not assign a plain whole result struct), an unknown callee, a
% call graph cycle, a per-function slice error (line continuations, top-level
% while/if/switch), or a failed closure check in ANY block - it returns mLines
% UNCHANGED with .sliced = false. It never emits a partial,
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
% Attach each rolled 'for...end' block's full body text to its statement so the
% interprocedural call-site and result-field scans (callSites/fieldsRead) can
% read INSIDE the loop (issue #44 item 1, R10(a)): a subfunction call or a
% callee-result-field read nested in a kept loop would otherwise be invisible to
% the top-level-only scans and under-demand a callee. Demand is a may-analysis,
% so scanning the loop body (over-approximating to "the loop reads/calls this")
% is sound - it can only keep more, never drop a needed producer. A call inside
% a loop whose result is not a plain whole-struct assignment still bails
% conservatively in callSites, as at top level.
[Sall.blocktext] = deal(strings(0,1));
for q = 1:numel(Sall)
  if Sall(q).block
    Sall(q).blocktext = body(Sall(q).line:Sall(q).lineEnd);
  end
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
% Block-aware (R10(a)): a kept rolled 'for...end' is scanned line by line so a
% call nested in the loop is found too; demand is a may-analysis, so an
% over-counted call only over-demands its callee, never under-demands one.
calls = struct('result',{},'callee',{});
ok = true;
for k = find(keep(:)).'
  for ln = scanLines(Sall(k))
    [res, callee, isCall, lineOk] = parseCallLine(char(ln), derivNames);
    if ~lineOk
      ok = false; return   % a call to a derivative function not assigning a
                           % plain whole result struct: bail (as at top level)
    end
    if isCall
      calls(end+1) = struct('result',res,'callee',callee); %#ok<AGROW>
    end
  end
end
end

%% --------------------------------------------------------------------- %%
function lines = scanLines(S)
% The statement text lines to scan interprocedurally: a normal statement is its
% single line; a rolled 'for...end' block is every line of its body (so calls /
% result-field reads nested in the loop are seen). Row string for for-iteration.
if S.block && ~isempty(S.blocktext)
  lines = reshape(string(S.blocktext),1,[]);
else
  lines = string(S.text);
end
end

%% --------------------------------------------------------------------- %%
function [res, callee, isCall, lineOk] = parseCallLine(ln, derivNames)
% Parse one statement line. If its RHS is a bare call 'callee(args)' to a name in
% derivNames, return isCall=true with res (the assigned result var) and callee;
% lineOk=false iff it IS such a call but the result is not a plain whole-struct
% assignment (dotted/subscripted LHS). Non-call lines: isCall=false, lineOk=true.
%
% The '^callee(args)$' anchor (and the single-'=' split) rely on the generator
% emitting each subfunction call as its own statement on its own line, with the
% '% Call to function' note on the NEXT line (lib/adigatorFunctionInitialize.m).
% That invariant is what makes "RHS does not end in ')' => not a call" safe: a
% future emitter change that appended an inline comment or fused a call with a
% result-read on one line would slip past this and under-demand the callee, so
% it must be caught in review, not here.
res = ''; callee = ''; isCall = false; lineOk = true;
t = strtrim(ln);
if isempty(t) || t(1) == '%'
  return
end
eq = strfind(t,'=');
if isempty(eq)
  return   % no assignment (for/end/bare expr): cannot be a call statement
end
lhsfull = strtrim(t(1:eq(1)-1));
rhs = strtrim(t(eq(1)+1:end));
if ~isempty(rhs) && rhs(end) == ';'
  rhs = strtrim(rhs(1:end-1));
end
tok = regexp(rhs,'^([A-Za-z]\w*)\s*\((.*)\)$','tokens','once');
if isempty(tok)
  return   % RHS is not a bare single call
end
cal = string(tok{1});
if ~any(cal == derivNames)
  return   % a call to a non-derivative function (library/builtin): not ours
end
% it is a call to one of our subfunctions - the result must be a whole struct
if isempty(lhsfull) || contains(lhsfull,'.') || contains(lhsfull,'(')
  lineOk = false; return
end
res = lhsfull; callee = char(cal); isCall = true;
end

%% --------------------------------------------------------------------- %%
function fr = fieldsRead(Sall, keep, resultVar)
% Which fields of <resultVar> the kept statements read: a cellstr of field
% names, or the string 'WHOLE' if the result struct is read whole anywhere (a
% bare <resultVar> token not followed by '.'). Mirrors adigatorWrapperDemand's
% extraction, over the kept derivative-block statements rather than a wrapper.
% Block-aware (R10(a)): a kept rolled loop is scanned line by line, so a
% '<resultVar>.field' read nested in the loop is counted; the call line that
% assigns <resultVar> is skipped wherever it appears (top level or in a loop).
rv     = regexptranslate('escape',resultVar);
barepat = ['\<',rv,'\>(?!\.)'];
fldpat  = ['\<',rv,'\.([A-Za-z]\w*)'];
found = {};
for k = find(keep(:)).'
  for ln = scanLines(Sall(k))
    txt = char(ln);
    if isAssignmentOf(txt, resultVar)
      continue   % the 'resultVar = ...' assignment itself, not a use
    end
    if ~isempty(regexp(txt,barepat,'once'))
      fr = 'WHOLE'; return
    end
    toks = regexp(txt,fldpat,'tokens');
    for t = 1:numel(toks)
      found{end+1,1} = toks{t}{1}; %#ok<AGROW>
    end
  end
end
fr = unique(found(:)).';
if isempty(fr)
  fr = 'WHOLE';   % kept but no field read found -> demand all, conservatively
end
end

%% --------------------------------------------------------------------- %%
function tf = isAssignmentOf(ln, base)
% true iff line ln is a plain whole assignment 'base = ...' (no dotted field, no
% subscript on the LHS) - the call's own result assignment, which must not be
% mistaken for a bare whole-struct READ of base.
tf = false;
t = strtrim(ln);
eq = strfind(t,'=');
if isempty(eq)
  return
end
lhs = strtrim(t(1:eq(1)-1));
tf = strcmp(lhs, base);
end

%% --------------------------------------------------------------------- %%
function [ok, why] = closureOk(Sall, keep, demanded, innames)
% Per-function eval-free closure gate (identical reasoning to
% adigatorSlimDerivBody/closureOk; block-aware via Sall.writes, so a base
% assigned inside a rolled loop counts as produced/written): every base read by
% a kept statement is an input / Gator1Data or has ALL its writers kept, and
% every demanded output
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
