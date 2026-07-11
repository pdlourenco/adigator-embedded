classdef ULoopboundGuardTest < matlab.unittest.TestCase
    % ULoopboundGuardTest  Lockstep pin for the shared loopbound guard shape
    % (util/adigatorLoopboundGuard, issue #181; CI_PLAN TS-U-19).
    %
    % The runtime-bound guard `assert(name <= max);` is emitted by
    % adigatorForInitialize and recognized by adigatorPrintTempFiles (the #173
    % drop/rediff logic) and adigatorParseTape (the slim keep-always whitelist).
    % Before the shared constant, the shape lived in five hand-synced copies and
    % two recognizers had already drifted (';?' vs ';'). This test pins the one
    % invariant everything rests on: WHAT THE TEMPLATE EMITS, THE RECOGNIZER
    % MATCHES (with the right tokens) - so any future edit to either side that
    % breaks the lockstep fails here rather than silently dropping or
    % mis-classifying guards in generated files.
    %
    % util/-only path fixture on purpose: adigatorParseTape's unit tests run
    % with only util/ on the path, so the shared constant must resolve
    % util-locally (this test would catch a move into lib/).
    %
    % Copyright Pedro Lourenço and GMV. Distributed under the GNU General
    % Public License v3.0.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
        end
    end

    methods (Test)
        function templateMatchesRecognizer(tc)
            % the load-bearing lockstep: emitted text is byte-stable and the
            % recognizer extracts {name, bound} from it
            g = adigatorLoopboundGuard();
            line = sprintf(g.template,'N',8);
            tc.verifyEqual(line,'assert(N <= 8);', ...
                'emitted guard text changed - generated-file dialect break');
            tok = regexp(line,g.match,'once','tokens');
            tc.verifyEqual(tok,{'N','8'}, ...
                'recognizer must match the emitted shape with {name,bound} tokens');
        end

        function multiDigitBoundAndLongName(tc)
            g = adigatorLoopboundGuard();
            line = sprintf(g.template,'nSteps',4096);
            tok = regexp(line,g.match,'once','tokens');
            tc.verifyEqual(tok,{'nSteps','4096'});
        end

        function recognizerToleratesTrailingWhitespaceOnly(tc)
            % consumers feed strtrim'd lines, but trailing space after the
            % semicolon is tolerated by design; leading text is not
            g = adigatorLoopboundGuard();
            tc.verifyNotEmpty(regexp(sprintf('assert(N <= 8);  '),g.match,'once'));
            tc.verifyEmpty(regexp('x = 1; assert(N <= 8);',g.match,'once'), ...
                'guard must be the whole statement, not a suffix');
        end

        function nonGuardShapesRejected(tc)
            % user asserts that merely resemble the guard must NOT match:
            % they take the fail-loud adigator:loopbound:rediff path, never
            % the silent drop (#173 PR A semantics)
            g = adigatorLoopboundGuard();
            tc.verifyEmpty(regexp('assert(N <= Nmax);',g.match,'once'), ...
                'non-numeric bound is a user assert');
            tc.verifyEmpty(regexp('assert(N < 8);',g.match,'once'), ...
                'wrong operator is a user assert');
            tc.verifyEmpty(regexp('myassert(N <= 8);',g.match,'once'), ...
                'prefixed name is not the guard');
            tc.verifyEmpty(regexp('assert(N <= 8)',g.match,'once'), ...
                'missing semicolon is not the emitted shape');
        end
    end
end
