function adigatorCheckTripCountRediff(UserFunName,UserFunInputs)
% ADIGATORCHECKTRIPCOUNTREDIFF  Fail actionably when re-differentiating a
% specialized file at a different trip count (B36, issue #210).
%
%   adigatorCheckTripCountRediff(UserFunName,UserFunInputs)
%
% A file this tool generated for a loop bound that NAMES a function input is
% specialized to exactly one trip count: its loop headers are literals and its
% index tables are sized for that value. It states so with
% `assert(<name> == <value>);` (util/adigatorLoopboundGuard). Differentiating
% such a file again with a different value for that input cannot produce a
% valid result - the new pass would build a body serving the old count while
% stamping the new one onto the guard.
%
% That case is already LOUD without this check: the source guard executes during
% adigator's initial test evaluation and throws. But it throws a bare
% `MATLAB:assertion:failed` / "Assertion failed", which tells the user nothing
% about what they did. This turns it into a diagnosis, matching the actionable
% re-differentiation error established for the loopbound guard (#173 PR A).
%
% Silent no-op unless the file exists, is readable, carries a guard, and the
% guard's name resolves to a positional input whose value differs: every step is
% best-effort, because this runs BEFORE adigator's own parsing and must never be
% the thing that breaks an otherwise-valid call.
%
% See also adigator adigatorLoopboundGuard
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public
% License v3.0.
% Changelog:
%   2026-07    Created (B36, issue #210).

fname = which(UserFunName);
if isempty(fname) || exist(fname,'file') ~= 2
  return   % adigator's own checks report a missing file better than we can
end
try
  lines = strtrim(string(splitlines(string(fileread(fname)))));
catch
  return
end

g = adigatorLoopboundGuard();
guards = lines(~cellfun(@isempty, regexp(cellstr(lines), g.eqMatch, 'once')));
if isempty(guards); return; end

argNames = signatureInputs(lines);
if isempty(argNames); return; end

for k = 1:numel(guards)
  tok = regexp(char(guards(k)), g.eqMatch, 'once', 'tokens');
  if isempty(tok); continue; end
  gname = tok{1};
  gval  = str2double(tok{2});
  loc   = find(strcmp(argNames,gname),1);
  if isempty(loc) || loc > numel(UserFunInputs); continue; end
  passed = UserFunInputs{loc};
  if ~isnumeric(passed) || ~isscalar(passed) || ~isreal(passed); continue; end
  if passed ~= gval
    error('adigator:tripcount:mismatch','%s',...
      ['Cannot differentiate ''',UserFunName,''': it was generated ',...
       'specialized to ',gname,' = ',num2str(gval),', but this call passes ',...
       gname,' = ',num2str(passed),'. A specialized derivative file''s loop ',...
       'headers and index tables are built for the value it was generated at, ',...
       'so a further derivative of it must use the same one. Re-generate the ',...
       'whole chain at ',gname,' = ',num2str(passed),', or use the ',...
       '''loopbound'' option if one file must serve several trip counts ',...
       '(issue #210).']);
  end
end
end

function names = signatureInputs(lines)
% positional input names from the first `function ... (a,b,c)` declaration
names = {};
loc = find(startsWith(lines,'function '),1);
if isempty(loc); return; end
sig = char(lines(loc));
lp  = strfind(sig,'('); rp = strfind(sig,')');
if isempty(lp) || isempty(rp) || rp(end) <= lp(1); return; end
inner = strtrim(sig(lp(1)+1:rp(end)-1));
if isempty(inner); return; end
names = strtrim(strsplit(inner,','));
end
