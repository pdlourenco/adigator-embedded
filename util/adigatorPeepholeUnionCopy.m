function [newLines, info] = adigatorPeepholeUnionCopy(mLines, gatorData)
% adigatorPeepholeUnionCopy  Collapse no-op "union copy" pairs in a generated
% _ADiGator* derivative file (roadmap R7c, issue #21; ANALYSIS.md 2.3 item 6):
%
%     v = zeros(K,1);        % K an integer literal
%     v(idx)     = src;      %  idx the ordered identity 1:K (so v == src)
%
% becomes a single
%
%     v = reshape(src,K,1);
%
% which is EITHER exactly equivalent (when idx == (1:K).' and numel(src)==K,
% the case this pattern always produces - the scatter fills every row of the
% freshly-zeroed column in order) OR fails loudly: reshape requires
% numel(src)==K, so a non-K-element src - including a scalar src that the
% original 'v(1:K)=scalar' would have broadcast - throws rather than silently
% mis-computing. The rewrite is thus equivalent-or-stricter, never silently
% wrong; the round-trip cross-check in the slim_embed driver is the secondary
% guard.
%
% ------------------------------ Inputs --------------------------------- %
%   mLines    - string array (or cellstr) of the full _ADiGator* file.
%   gatorData - the struct holding the file's constant tables (the per-
%               function value of the saved .mat, e.g. tmp.(dername)), so a
%               'Gator<D>Data.Index<N>' scatter subscript can be resolved to
%               its numeric value to test the identity condition.
%
% ------------------------------ Outputs -------------------------------- %
%   newLines - string column of the (possibly) rewritten file.
%   info     - struct: .changed (logical), .count (pairs collapsed), .reason.
%
% Conservative: bails (returns mLines unchanged) on missing body markers, line
% continuations, or rolled control flow, and skips any pair it cannot prove is
% an ordered-identity full overwrite (vectorized 'zeros(size(..),m)' forms, a
% non-resolvable / non-identity index, a self-referential RHS, a non-
% consecutive scatter).
%
% Copyright Pedro Lourenço and GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%            R7c union-copy peephole (issue #21).
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorParseTape, adigatorSlimDerivBody, adigatorGenDerFile_embedded

mL = string(mLines);
mL = mL(:);
newLines = mL;
info = struct('changed',false,'count',0,'reason','');

if nargin < 2 || ~isstruct(gatorData)
  info.reason = 'no gator data'; return
end

% --------------------------- locate the body --------------------------- %
bs = find(contains(mL,'ADiGator Start Derivative Computations'),1);
be = find(strtrim(mL) == "function ADiGator_LoadData()",1);
if isempty(bs) || isempty(be) || be <= bs+1
  info.reason = 'body markers not found'; return
end
body = mL(bs+1:be-1);
if any(endsWith(strtrim(body),'...'))
  info.reason = 'line continuation in body'; return
end

% header inputs (for the parser); bail on a bracketed/odd header
hi = find(startsWith(strtrim(mL),'function'),1);
tok = regexp(char(mL(hi)), ...
  '^\s*function\s+[A-Za-z]\w*\s*=\s*[A-Za-z]\w*\s*\(([^)]*)\)','tokens','once');
if isempty(tok)
  info.reason = 'cannot parse header'; return
end
ins = strtrim(strsplit(tok{1},','));
innames = ins(~cellfun(@isempty,ins));

% ------------------------------- parse --------------------------------- %
try
  S = adigatorParseTape(body, innames);
catch ME
  if startsWith(ME.identifier,'adigator:fwdtape')
    info.reason = ['cannot parse: ',ME.message]; return
  end
  rethrow(ME)
end

% --------------- find ordered-identity zeros->scatter pairs ------------ %
dropLine    = [];                 % body lines to remove (the zeros statement)
rewriteLine = zeros(0,1);         % body lines to replace ...
rewriteText = strings(0,1);       % ... with this text
n = numel(S);
k = 1;
while k < n
  [isZeros, K, v] = matchZerosK1(S(k));
  if ~isZeros
    k = k + 1; continue
  end
  Snext = S(k+1);
  % the very next statement must be a scatter (has lhsSubs) into the SAME
  % base v (v is a plain, dot-free zeros lhs, so lhs==v is the full test)
  if isempty(Snext.lhsSubs) || ~strcmp(Snext.lhs,v)
    k = k + 1; continue
  end
  if ~isIdentityScatter(Snext.lhsSubs, K, gatorData)
    k = k + 1; continue
  end
  % the RHS must not reference v (otherwise dropping the zeros changes it)
  if ~isempty(regexp(Snext.rhs,['\<',regexptranslate('escape',v),'\>'],'once'))
    k = k + 1; continue
  end
  % collapse: drop the zeros line, rewrite the scatter to a reshape
  dropLine(end+1,1)    = S(k).line;     %#ok<AGROW>
  rewriteLine(end+1,1) = Snext.line;    %#ok<AGROW>
  rewriteText(end+1,1) = sprintf('%s = reshape(%s,%d,1);', v, Snext.rhs, K); %#ok<AGROW>
  k = k + 2;                            % consume both statements
end

if isempty(dropLine)
  info.reason = 'no identity union copies'; return
end

% ------------------------------ re-emit -------------------------------- %
% preserve leading whitespace of the rewritten line
for r = 1:numel(rewriteLine)
  ln = char(body(rewriteLine(r)));
  indent = ln(1:find(~isspace(ln),1)-1);
  body(rewriteLine(r)) = string([indent, char(rewriteText(r))]);
end
bmask = true(numel(body),1);
bmask(dropLine) = false;

newLines = [mL(1:bs); body(bmask); mL(be:end)];
info.changed = true;
info.count   = numel(dropLine);
end

%% --------------------------------------------------------------------- %%
function [tf, K, v] = matchZerosK1(s)
% match 'v = zeros(K,1);' with K an integer literal and a plain (non-scatter,
% non-field) lhs.
tf = false; K = 0; v = '';
if ~isempty(s.lhsSubs) || ~strcmp(s.lhs,strtok(s.lhs,'.'))
  return
end
t = regexp(s.rhs,'^zeros\((\d+),1\)$','tokens','once');
if isempty(t)
  return
end
tf = true; K = str2double(t{1}); v = s.lhs;
end

%% --------------------------------------------------------------------- %%
function tf = isIdentityScatter(lhsSubs, K, gatorData)
% true iff the scatter subscript resolves to the ordered identity (1:K).',
% indexing all K rows of the K-by-1 target (a trailing ',1' / ',:' col index
% is allowed).
tf = false;
parts = strtrim(strsplit(lhsSubs,','));
if numel(parts) == 2 && ~any(strcmp(parts{2},{'1',':'}))
  return % an unexpected column subscript -> not a full K-by-1 fill
end
rowsub = parts{1};
idx = resolveIndex(rowsub, gatorData);
if isempty(idx)
  return
end
tf = isequal(idx(:), (1:K).');
end

%% --------------------------------------------------------------------- %%
function idx = resolveIndex(expr, gatorData)
% resolve a scatter row-subscript to a numeric vector, or [] if it cannot be
% resolved to a constant. Handles the two forms the printer actually emits for
% these union copies - a bare range 'a:b' (optionally transposed) and a
% 'Gator<D>Data.IndexN' table reference. Anything else (a parenthesised range,
% an arithmetic expression, sub2ind, ...) returns [] and the pair is skipped
% (a missed optimisation, never a wrong rewrite).
idx = [];
expr = strtrim(expr);
expr = regexprep(expr,'\.''$','');           % strip a trailing transpose
expr = strtrim(expr);
r = regexp(expr,'^(\d+):(\d+)$','tokens','once');
if ~isempty(r)
  idx = str2double(r{1}):str2double(r{2}); return
end
g = regexp(expr,'^(Gator\d+Data)\.(Index\d+)$','tokens','once');
if ~isempty(g)
  dn = g{1}; ix = g{2};
  if isfield(gatorData,dn) && isfield(gatorData.(dn),ix)
    val = gatorData.(dn).(ix);
    if isnumeric(val)
      idx = double(val);
    end
  end
end
end
