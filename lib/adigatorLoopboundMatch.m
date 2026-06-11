function name = adigatorLoopboundMatch(loopbound,triplen)
% name = adigatorLoopboundMatch(loopbound,triplen)
%
% Runtime loop-bound matching (roadmap R3; issue #6 Tier 1). Given the
% resolved ADIGATOR.OPTIONS.LOOPBOUND struct array (fields .name/.value,
% see adigator.m) and the analyzed trip count of a rolled loop, returns
% the name of the runtime bound parameter whose maximum value equals the
% trip count, or '' if the loop keeps its fixed literal bound. Loops are
% matched by trip-count value; the option documentation requires each
% runtime-bound parameter to carry a value no fixed loop shares.
%
% See also adigator adigatorOptions adigatorForInitialize adigatorForIterEnd
name = '';
if ~isempty(loopbound)
  loc = find([loopbound.value] == triplen,1);
  if ~isempty(loc)
    name = loopbound(loc).name;
  end
end
end
