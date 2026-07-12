function g = adigatorLoopboundGuard()
% ADIGATORLOOPBOUNDGUARD  Single source of truth for the loopbound guard shape.
%
%   g = adigatorLoopboundGuard() returns
%     g.template - sprintf template that emits the runtime-bound guard:
%                  sprintf(g.template, name, maxtrip) -> 'assert(N <= 8);'
%     g.match    - anchored regex recognizing exactly that shape on a
%                  strtrim'd line; tokens = {name, bound}.
%
% Consumers (kept in lockstep, pinned by tests/unit/ULoopboundGuardTest.m):
%   lib/adigatorForInitialize.m  - emits the guard before every runtime-bound
%                                  loop header (outer + inner forms)
%   lib/adigatorPrintTempFiles.m - recognizes a source-line guard on
%                                  re-differentiation (drop-and-regenerate /
%                                  adigator:loopbound:rediff, issue #173)
%   util/adigatorParseTape.m     - slim whitelist: the guard is an opaque
%                                  keep-always statement
%
% Before this function existed the shape lived in five hand-synced copies and
% two of the recognizer regexes had already drifted (';?' vs ';') - issue #181
% tech-debt item. The unified recognizer requires the terminating semicolon
% (the emitter always prints one) and tolerates trailing whitespace.
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public
% License v3.0.
g.template = 'assert(%s <= %1.0d);';
g.match    = '^assert\(\s*([A-Za-z]\w*)\s*<=\s*(\d+)\s*\)\s*;\s*$';
end
