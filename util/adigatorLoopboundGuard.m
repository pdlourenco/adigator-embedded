function g = adigatorLoopboundGuard()
% ADIGATORLOOPBOUNDGUARD  Single source of truth for the generated-file
% precondition guard shapes.
%
%   g = adigatorLoopboundGuard() returns
%     g.template   - sprintf template for the RUNTIME-BOUND guard:
%                    sprintf(g.template, name, maxtrip) -> 'assert(N <= 8);'
%     g.match      - anchored regex recognizing exactly that shape on a
%                    strtrim'd line; tokens = {name, bound}.
%     g.eqTemplate - sprintf template for the SPECIALIZED-TRIP-COUNT guard:
%                    sprintf(g.eqTemplate, name, trip) -> 'assert(N == 5);'
%     g.eqMatch    - anchored regex for that shape; tokens = {name, value}.
%     g.anyMatch   - anchored regex matching EITHER shape; tokens = {name, value}.
%                    Use this wherever a consumer only needs to know "is this a
%                    machine-emitted guard?" rather than which kind.
%
% Two guards, two different claims about the same kind of parameter:
%
%   `assert(N <= Nmax)`  the file was analyzed at the MAXIMUM trip count and runs
%                        a padded program for any n <= Nmax ('loopbound' option,
%                        issue #6 Tier 1). An inequality: smaller is fine.
%   `assert(N == n)`     the file was SPECIALIZED to exactly one trip count (no
%                        'loopbound' option, but the loop range names a function
%                        input, so the name survives into the generated file
%                        while the loop header does not). An equality: the index
%                        tables fit exactly one value and nothing else is served
%                        correctly - B36, issue #210.
%
% Both are emitted once per declared/derived parameter at the TOP of the main
% function body (B35, ADR-0034): a trip-count parameter also sizes expressions
% that run before the first loop, so guarding at the loop header leaves those
% unbounded and the file is not embeddable.
%
% Consumers (kept in lockstep, pinned by tests/unit/ULoopboundGuardTest.m):
%   lib/adigatorFunctionInitialize.m - emits both guards in the body prologue
%   lib/adigatorForInitialize.m      - emits the runtime-bound guard before every
%                                      runtime-bound loop header (outer + inner)
%   lib/adigatorPrintTempFiles.m     - recognizes a source-line guard on
%                                      re-differentiation (drop-and-regenerate /
%                                      adigator:loopbound:rediff, issue #173)
%   util/adigatorParseTape.m         - slim whitelist: a guard is an opaque
%                                      keep-always statement
%
% Before this function existed the shape lived in five hand-synced copies and
% two of the recognizer regexes had already drifted (';?' vs ';') - issue #181
% tech-debt item. The unified recognizer requires the terminating semicolon
% (the emitter always prints one) and tolerates trailing whitespace.
%
% Both values are matched as integers - each emitter formats one (a maximum
% trip count; or a parameter restricted to integer values at collection time),
% so a fractional literal is by construction not one of ours. The equality form
% additionally admits a NEGATIVE value: a specialized parameter can be any
% endpoint of the range (`for k = a:b`), not only a count, so `a` may be <= 0.
% A loopbound maximum is a trip count and is always positive, so g.match stays
% unsigned - keep it that way, it is the tighter statement.
%
% g.anyMatch is deliberately the LOOSE union (signed after either operator): its
% consumers only ask "is this a machine-emitted guard?", and a shape we never
% emit costs nothing to recognize. Use g.match / g.eqMatch when the distinction
% matters.
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public
% License v3.0.
g.template   = 'assert(%s <= %1.0d);';
g.match      = '^assert\(\s*([A-Za-z]\w*)\s*<=\s*(\d+)\s*\)\s*;\s*$';
g.eqTemplate = 'assert(%s == %1.0d);';
g.eqMatch    = '^assert\(\s*([A-Za-z]\w*)\s*==\s*(-?\d+)\s*\)\s*;\s*$';
g.anyMatch   = '^assert\(\s*([A-Za-z]\w*)\s*(?:<=|==)\s*(-?\d+)\s*\)\s*;\s*$';
end
