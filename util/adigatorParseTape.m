function S = adigatorParseTape(body, InNames, allowBlocks)
% adigatorParseTape  Parse a generated forward derivative-file body into a
% statement-struct array with dependency sets - the shared front end of the
% forward-tape slicers (the value-tape slice in adigatorForwardTapeSlice, the
% field-granular slice in adigatorFieldSlice; roadmap R4 / R7b, issue #21).
%
% ------------------------------ Inputs --------------------------------- %
%   body        - string array (or cellstr) of the generated function-body
%                 lines (between the "Start Derivative Computations" marker and
%                 the trailing "function ADiGator_LoadData()" / "end").
%   InNames     - cellstr of the generated function's input names.
%   allowBlocks - optional logical (default false). When true, a rolled
%                 'for...end' block is parsed as ONE atomic statement (.block
%                 == true) rather than rejected - it writes the union of the
%                 bases assigned anywhere inside and reads the externally
%                 defined bases it references, so a backward slice can keep or
%                 drop the whole loop as a unit (roadmap R7b/#44). Top-level
%                 'while'/'if'/'switch' are still rejected; control flow NESTED
%                 inside the for-block is swallowed into the unit. With the
%                 default (false) the strict, fully-unrolled dialect is parsed.
%
% ------------------------------ Output --------------------------------- %
%   S - n-by-1 struct array, one element per statement in original order:
%         .text    - the statement text (trimmed; the 'for' header for a block)
%         .lhs     - assigned base name, optionally one dotted field
%                    ('y', 'y.f', 'cada1f3'); '' for a block
%         .lhsSubs - scatter subscript text ('1:2' from 'v(1:2)=...'), '' for
%                    a plain assignment or a block
%         .rhs     - right-hand-side expression text (without trailing ';');
%                    '' for a block
%         .deps    - cellstr of the base names this statement reads (dotted
%                    field tails stripped; a scatter also reads its own base)
%         .line    - 1-based index of the (first) statement line within `body`
%         .lineEnd - 1-based index of the last line (== .line except for a
%                    block, where it is the matching 'end'), so a slice can
%                    re-emit by dropping .line:.lineEnd
%         .writes  - cellstr of every base this statement assigns ({base} for a
%                    normal statement; the union of inner LHS bases for a block)
%         .block   - logical, true for a rolled 'for...end' unit
%         .active/.kind/.info - left empty for a downstream classify/execute
%                    pass (adigatorGenRevGradFile's execAndClassify)
%
% Rolled control flow ('for'/'while'/'if'/'elseif'/'else'/'switch') in the
% body is rejected with adigator:fwdtape:controlflow UNLESS allowBlocks lets a
% 'for...end' through as a unit. Unparseable statements raise
% adigator:fwdtape:parse.
%
% Copyright GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%            Split out of adigatorForwardTapeSlice so the value-tape and
%            field-granular slicers share one parser (roadmap R7b, issue #21).
%            2026-06  Opt-in rolled-for...end-as-a-unit parsing (#44).
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorForwardTapeSlice, adigatorFieldSlice, adigatorGenRevGradFile

if nargin < 3 || isempty(allowBlocks)
  allowBlocks = false;
end
body = string(body);

% ------------------------- collect statements -------------------------- %
% Each item is a normal statement or (allowBlocks) a rolled for...end unit.
items = collectItems(body, allowBlocks);
n = numel(items);

texts = reshape({items.text},[],1);
S = struct('text',texts,'lhs',[],'lhsSubs',[],'rhs',[],'deps',[],...
  'line',[],'lineEnd',[],'writes',[],'block',[],'active',[],'kind',[],'info',[]);
for k = 1:n
  S(k).line    = items(k).line;
  S(k).lineEnd = items(k).lineEnd;
  S(k).block   = items(k).isBlock;
end

reserved = {'S','Gator1Data','UserFunInputs','InNames','vodLoc','VodName',...
  'OutName','stmts','reserved','FwdGator','fwddata'};

% parse: lhs base name (with optional .f), scatter subscript text, rhs; for a
% block, the union of written bases (its deps are resolved in the pass below).
pendingReads = cell(n,1);
for k = 1:n
  if S(k).block
    [w, r, lv] = analyzeBlock(body(S(k).line:S(k).lineEnd));
    if any(ismember(w,reserved))
      error('adigator:fwdtape:parse',...
        'a name assigned in a rolled loop collides with a generator-internal name');
    end
    S(k).lhs = ''; S(k).lhsSubs = ''; S(k).rhs = '';
    S(k).writes = w;
    pendingReads{k} = setdiff(r,lv); % external-read candidates (loop vars out)
    continue
  end
  % split at the first top-level '=' (the dialect has no '==' and no '='
  % inside subscripts); parse the LHS manually rather than with optional
  % regexp groups, whose tokens MATLAB drops when they do not participate
  ln = S(k).text;
  eq = strfind(ln,'=');
  if isempty(eq) || ln(end) ~= ';'
    error('adigator:fwdtape:parse','cannot parse generated statement: %s',ln);
  end
  lhsfull = strtrim(ln(1:eq(1)-1));
  S(k).rhs = strtrim(ln(eq(1)+1:end-1));
  par = strfind(lhsfull,'(');
  if isempty(par)
    S(k).lhs     = lhsfull;
    S(k).lhsSubs = '';
  elseif lhsfull(end) == ')'
    S(k).lhs     = strtrim(lhsfull(1:par(1)-1));
    S(k).lhsSubs = lhsfull(par(1)+1:end-1);
  else
    error('adigator:fwdtape:parse','cannot parse generated statement: %s',ln);
  end
  if isempty(regexp(S(k).lhs,'^[A-Za-z]\w*(\.\w+)?$','once')) || ...
      isempty(S(k).rhs)
    error('adigator:fwdtape:parse','cannot parse generated statement: %s',ln);
  end
  if ~isempty(regexp(ln,'\<cadaRG','once'))
    error('adigator:fwdtape:parse','reserved name cadaRG* in generated code');
  end
  if any(strcmp(strtok(S(k).lhs,'.'),reserved))
    error('adigator:fwdtape:parse',...
      'variable name ''%s'' collides with a generator-internal name',...
      strtok(S(k).lhs,'.'));
  end
  S(k).writes = {strtok(S(k).lhs,'.')};
end
if any(ismember(InNames,reserved))
  error('adigator:fwdtape:parse',...
    'an input name collides with a generator-internal name');
end

% ----------------------------- dependencies ---------------------------- %
defined = [InNames(:); {'Gator1Data'}];
for k = 1:n
  if S(k).block
    % a block reads every externally defined base it references (including
    % loop-carried bases also initialised outside), and after it those bases
    % it assigns become defined
    S(k).deps = intersect(pendingReads{k},defined);
    defined = union(defined,S(k).writes);
    continue
  end
  % strip dotted tails so field names are not mistaken for variables
  depsrc = regexprep([S(k).rhs,' ',char(S(k).lhsSubs)],'\.\w+','');
  ids = regexp(depsrc,'[A-Za-z]\w*','match');
  S(k).deps = intersect(ids,defined);
  if ~isempty(S(k).lhsSubs)
    S(k).deps = union(S(k).deps,{strtok(S(k).lhs,'.')}); % scatter reads old
  end
  defined = union(defined,{strtok(S(k).lhs,'.')});
end
end

%% --------------------------------------------------------------------- %%
function items = collectItems(body, allowBlocks)
% Walk the body into items: normal one-line statements and (allowBlocks)
% rolled for...end units. Preserves the strict-mode control-flow rejection.
items = struct('isBlock',{},'line',{},'lineEnd',{},'text',{});
N = numel(body);
L = 1;
while L <= N
  ln = strtrim(char(body(L)));
  if isempty(ln) || ln(1) == '%'
    L = L + 1; continue
  end
  if strcmp(ln,'end') || strcmp(ln,'return')
    break % closing of the generated main function
  end
  if ~isempty(regexp(ln,'^(for|while|if|elseif|else|switch)\>','once'))
    if allowBlocks && ~isempty(regexp(ln,'^for\>','once'))
      eL = matchEnd(body,L);
      if isempty(eL)
        error('adigator:fwdtape:controlflow',...
          'unterminated rolled for-loop block starting: %s',ln);
      end
      items(end+1) = struct('isBlock',true,'line',L,'lineEnd',eL,'text',ln); %#ok<AGROW>
      L = eL + 1; continue
    end
    error('adigator:fwdtape:controlflow',...
      ['the generated file contains rolled control flow (''%s''); ',...
      'generate with adigatorOptions(''unroll'',1) or remove loops'],ln);
  end
  items(end+1) = struct('isBlock',false,'line',L,'lineEnd',L,'text',ln); %#ok<AGROW>
  L = L + 1;
end
end

%% --------------------------------------------------------------------- %%
function eL = matchEnd(body, startIdx)
% Index of the 'end' that closes the block opened at startIdx, tracking nested
% openers; [] if unterminated. One keyword per line (the generated dialect).
depth = 1; eL = [];
for e = startIdx+1:numel(body)
  t = strtrim(char(body(e)));
  if ~isempty(regexp(t,'^(for|parfor|while|if|switch)\>','once'))
    depth = depth + 1;
  elseif ~isempty(regexp(t,'^end\>','once'))
    depth = depth - 1;
    if depth == 0
      eL = e; return
    end
  end
end
end

%% --------------------------------------------------------------------- %%
function [writes, reads, loopVars] = analyzeBlock(inner)
% Scan a for...end block (inner includes its header and closing 'end') into the
% bases it assigns (writes), the identifiers it reads (reads), and its loop
% variables (loopVars). Assignment LHS bases are writes; for-headers contribute
% a loop variable and read their bounds; other control-flow lines contribute
% their condition reads; everything is base-name granular (dotted tails out).
% Like the strict parser, this assumes the generated one-statement-per-line,
% semicolon-terminated dialect: an inner line counts as an assignment only when
% it ends in ';' (a continued '...' or non-';' line is read as a bare
% expression, so its LHS would be omitted from writes); .block inherits that
% invariant, on which PR B's closure-over-.writes also relies.
writes = {}; reads = {}; loopVars = {};
for i = 1:numel(inner)
  t = strtrim(char(inner(i)));
  if isempty(t) || t(1) == '%'
    continue
  end
  ft = regexp(t,'^(?:for|parfor)\s+([A-Za-z]\w*)\s*=\s*(.*)$','tokens','once');
  if ~isempty(ft)
    loopVars{end+1} = ft{1};            %#ok<AGROW>
    reads = [reads, idsOf(ft{2})];      %#ok<AGROW>
    continue
  end
  if ~isempty(regexp(t,'^(while|if|elseif|switch|case)\>','once'))
    reads = [reads, idsOf(regexprep(t,'^\w+',''))]; %#ok<AGROW> condition reads
    continue
  end
  if ~isempty(regexp(t,'^(else|otherwise|end|break|continue|return)\>','once'))
    continue
  end
  eqp = strfind(t,'=');
  if ~isempty(eqp) && t(end) == ';'
    lhsfull = strtrim(t(1:eqp(1)-1));
    par = strfind(lhsfull,'(');
    if isempty(par)
      base = strtok(lhsfull,'.'); subs = '';
    else
      base = strtok(strtrim(lhsfull(1:par(1)-1)),'.');
      subs = lhsfull(par(1)+1:end-1);
    end
    writes{end+1} = base;               %#ok<AGROW>
    reads = [reads, idsOf(t(eqp(1)+1:end-1)), idsOf(subs)]; %#ok<AGROW>
  else
    reads = [reads, idsOf(t)];          %#ok<AGROW> bare expr: read all ids
  end
end
writes   = unique(writes);
loopVars = unique(loopVars);
reads    = setdiff(unique(reads),keywordSet());
end

%% --------------------------------------------------------------------- %%
function v = idsOf(s)
% identifier base names in s, with dotted field tails stripped
v = regexp(regexprep(char(s),'\.\w+',''),'[A-Za-z]\w*','match');
end

%% --------------------------------------------------------------------- %%
function kw = keywordSet()
kw = {'for','parfor','while','if','elseif','else','switch','case',...
  'otherwise','end','break','continue','return'};
end
