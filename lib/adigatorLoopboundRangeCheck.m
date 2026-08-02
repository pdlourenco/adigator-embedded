function adigatorLoopboundRangeCheck(ForCount,LBname)
% adigatorLoopboundRangeCheck(ForCount,LBname)
%
% Route 4(a) of the B36 residuals (issue #213): refuse to specialize a loop
% whose RANGE names a declared `loopbound` parameter but whose analyzed TRIP
% COUNT does not match that bound's declared maximum.
%
% ------------------------ Input Information ---------------------------- %
% ForCount: index of the loop being initialized (keys ADIGATORFORDATA and the
%           mention recorded by adigatorPrintTempFiles, which records only for
%           the MAIN function - ForCount restarts per function)
% LBname:   result of adigatorLoopboundMatch for this loop - '' when the trip
%           count matched no declared bound
%
% ----------------------------------------------------------------------- %
% The defect.
%
% `loopbound` matches loops BY TRIP-COUNT VALUE (adigatorLoopboundMatch), so in
%
%     adigatorOptions(...,'loopbound','N')      % declared maximum Nmax
%     for a = 1:N        % trip count Nmax  -> runtime header + assert(N<=Nmax)
%     for b = 1:N-1      % trip count Nmax-1 -> NO match -> LITERAL header
%
% the second loop is silently specialized to a literal. It is excluded from
% B36's `==` specialization guard on purpose - the name is a declared
% `loopbound`, and the two guards are opposites, so a name must never carry
% both - which leaves it covered only by `assert(N <= Nmax)`. That assert is
% satisfied by exactly the calls that make the second loop wrong: run at
% n < Nmax and the file happily executes `b = 1:Nmax-1` regardless, in the B36
% shape (`REVIEW_CONTEXT` principle 1 - a wrong derivative, not an error).
%
% Why REFUSE rather than emit a bound-derived header.
%
% Not because the shape is unpaddable. For `for b = 1:N-1` analyzed at Nmax the
% padded-program argument does hold: the analyzed iteration set 1..Nmax-1
% contains the runtime set 1..n-1 (the file's own assert gives n <= Nmax), the
% loop-variable VALUES are 1,2,... independent of N, so iteration j does the
% same work at every admissible n, and the skipped tail stays structurally zero
% exactly as it does for the matching loop. A header of `for c = 1:N-1` under
% the existing assert would be correct.
%
% The obstruction is expressive, not semantic: matching is by value and
% adigatorForInitialize can only emit `for c = 1:<name>`, so there is no way to
% state an AFFINE-in-bound header today. That is Tier 2 of issue #6, not this
% fix. Until it exists, refusing is the honest outcome - it converts a silent
% wrong derivative into a loud, actionable failure, which principle 1 ranks
% strictly better. (A shape whose loop-variable VALUES depend on the bound, say
% `for b = Nmax-N+1:Nmax`, genuinely cannot be padded - but that is a different
% case and is not what this check is about.)
%
% Scope, and what it does not catch.
%
% The predicate is syntactic on the range text, so it fires only where a
% declared bound is NAMED. A deliberate fixed loop (`for k = 1:3`) never
% mentions a bound and is untouched, which is what keeps the refusal from
% making the option unusable. A field reference (`1:p.N`) is excluded by the
% leading-dot rule in the recorder - that is route 2 of the residuals and keeps
% its current behaviour. And one level of indirection defeats it entirely:
%
%     M = N-1;  for b = 1:M      % names no declared bound -> NOT refused
%
% is still silently specialized. That residual is recorded in ANALYSIS §1.3m;
% closing it needs the bound's value to be traced through assignments, which is
% a different analysis from reading the range text.
%
% Copyright Pedro Lourenço and GMV.  2026-08  (#213 route 4a)
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorLoopboundMatch, adigatorForInitialize, adigatorOptions

global ADIGATOR ADIGATORFORDATA %#ok<GVMIS> - the transformation globals

if ~isempty(LBname)
  return                       % the loop matched a declared bound: nothing to do
end
if isempty(ADIGATOR.OPTIONS.LOOPBOUND) || ~isfield(ADIGATOR,'LOOPBOUNDINRANGE')
  return
end
if numel(ADIGATOR.LOOPBOUNDINRANGE) < ForCount
  return
end
Mentioned = ADIGATOR.LOOPBOUNDINRANGE{ForCount};
if isempty(Mentioned)
  return                       % this loop's range names no declared bound
end

% Report the bound the range actually mentioned, not simply the first declared
% one: with several bounds in play, naming the wrong parameter would send the
% user to delete the one that was fine.
BadName = Mentioned{1};
names   = {ADIGATOR.OPTIONS.LOOPBOUND.name};
values  = [ADIGATOR.OPTIONS.LOOPBOUND.value];
BadMax  = values(strcmp(names,BadName));
triplen = ADIGATORFORDATA(ForCount).MAXLENGTH;

error('adigator:loopbound:rangemismatch','%s', ...
  sprintf(['A loop range names the declared ''loopbound'' parameter ''%s'' but ', ...
   'its trip count (%g) does not match that bound''s declared maximum (%g).\n\n', ...
   'Loops are matched to a runtime bound BY TRIP-COUNT VALUE, so this loop ', ...
   'would be given a fixed literal header inside a file whose bound is ', ...
   'runtime - and would then compute the wrong answer, silently, for every ', ...
   'call below the maximum. The file''s own assert(%s <= %g) is satisfied by ', ...
   'exactly those calls, so it does not cover this.\n\n', ...
   'A bound-derived header (for c = 1:%s-1) would be correct, but cannot be ', ...
   'expressed today: matching is by trip-count value and only ''1:<name>'' ', ...
   'headers are emitted. Affine bounds are issue #6 Tier 2.\n\n', ...
   'Fix by one of:\n', ...
   '  - make the loop''s trip count equal %g (loop to %s and skip the last ', ...
   'iteration inside the body); or\n', ...
   '  - declare the second count as its own loopbound parameter - note ', ...
   'matching is by VALUE, so the caller must keep the two consistent at ', ...
   'every call; or\n', ...
   '  - remove ''%s'' from the loopbound option and let the file specialize ', ...
   'to one size, which B36''s assert(%s == n) then states.'], ...
   BadName, triplen, BadMax, BadName, BadMax, BadName, BadMax, BadName, ...
   BadName, BadName));
end
