function stamp = adigatorStampOf(FunctionInfo)
%ADIGATORSTAMPOF  Recover a generation stamp from adigator's returned info (#200).
%
% `adigator` computes the stamp once and attaches it to `FunctionInfo(1)`, so
% the wrapper generators - which run after it returns, when B16's cleanup has
% already cleared the transformation globals - emit the SAME id as the
% derivative file they call. That shared id is what makes a mismatch across a
% wrapper / derivative / data-function set mean "mixed vintages".
%
% Degrades rather than throws: an older or hand-built FunctionInfo without the
% field yields a stamp whose id says so, so a header is still emitted and the
% generation still succeeds. A missing stamp is a provenance gap, not a reason
% to fail a differentiation.
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

if ~isempty(FunctionInfo) && isstruct(FunctionInfo) ...
        && isfield(FunctionInfo, 'Stamp') && ~isempty(FunctionInfo(1).Stamp)
    stamp = FunctionInfo(1).Stamp;
    return
end
stamp = struct('id', 'unavailable', 'when', '', 'version', '');
end
