classdef UParseBlockTest < matlab.unittest.TestCase
    % UParseBlockTest  Unit tests for the opt-in rolled-'for...end'-as-a-unit
    % parsing in adigatorParseTape (roadmap R7b/#44): a rolled loop becomes one
    % atomic .block statement whose .writes is the union of bases it assigns and
    % whose .deps are the externally defined bases it reads (loop variables and
    % loop-local temporaries excluded; loop-carried bases also initialised
    % outside kept). Exercises the line span, nested control-flow swallowing,
    % and that strict mode (the default) and top-level non-for control flow are
    % still rejected. Hand-written tape snippets, no toolbox.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
        end
    end

    methods (Test)
        function parsesForBlockAsUnit(tc)
            body = [ ...
                "cada1f1 = w.*x;"; ...
                "for i = 1:3"; ...
                "  cadaJ(i) = cada1f1;"; ...
                "end"; ...
                "y.f = cadaJ;"];
            S = adigatorParseTape(body, {'x','w'}, true);

            tc.verifyEqual(numel(S), 3);
            % the loop collapsed into a single block spanning its lines
            tc.verifyFalse(S(1).block);
            tc.verifyTrue(S(2).block);
            tc.verifyFalse(S(3).block);
            tc.verifyEqual([S(2).line S(2).lineEnd], [2 4]);
            tc.verifyEqual(S(2).writes, {'cadaJ'});
            tc.verifyEqual(S(2).deps, {'cada1f1'}); % loop var i excluded
            tc.verifyEmpty(S(2).lhs);
            % the surrounding straight-line statements parse as usual
            tc.verifyEqual(S(1).writes, {'cada1f1'});
            tc.verifyEqual([S(3).line S(3).lineEnd], [5 5]);
            tc.verifyEqual(S(3).writes, {'y'});
        end

        function blockDepsIncludeLoopCarriedExternalInit(tc)
            % acc is written inside AND initialised outside -> it is a genuine
            % external dep (first iteration reads acc=0), so it must appear in
            % deps even though the block also writes it
            body = [ ...
                "acc = 0;"; ...
                "for i = 1:n"; ...
                "  acc = acc + x(i);"; ...
                "end"; ...
                "y.f = acc;"];
            S = adigatorParseTape(body, {'x','n'}, true);

            tc.verifyTrue(S(2).block);
            tc.verifyEqual(sort(S(2).deps(:)), {'acc';'n';'x'});
            tc.verifyEqual(S(2).writes, {'acc'});
        end

        function swallowsNestedControlFlow(tc)
            % a nested if...end inside the for is consumed into the one unit;
            % matchEnd pairs the correct closing 'end'
            body = [ ...
                "for i = 1:3"; ...
                "  if x(i) > 0"; ...
                "    a(i) = x(i);"; ...
                "  end"; ...
                "end"; ...
                "y.f = a;"];
            S = adigatorParseTape(body, {'x'}, true);

            tc.verifyEqual(numel(S), 2);
            tc.verifyTrue(S(1).block);
            tc.verifyEqual([S(1).line S(1).lineEnd], [1 5]);
            tc.verifyEqual(S(1).writes, {'a'});
            tc.verifyEqual(S(1).deps, {'x'}); % loop var i excluded
        end

        function bareExpressionBlockReadsIdsAndWritesNothing(tc)
            % a non-assignment, non-control-flow inner line (the defensive
            % bare-expression branch) still contributes its identifiers as
            % reads, and a loop that assigns nothing has empty .writes
            body = [ ...
                "zz = x;"; ...
                "for i = 1:3"; ...
                "  somecall(zz);"; ...   % bare expression, not an assignment
                "end"; ...
                "y.f = x;"];
            S = adigatorParseTape(body, {'x'}, true);
            blk = S([S.block]);
            tc.verifyEqual(numel(blk), 1);
            tc.verifyEmpty(blk.writes);                  % loop assigns nothing
            tc.verifyTrue(any(strcmp(blk.deps,'zz')));   % zz read inside loop
        end

        function defaultModeStillRejectsRolledLoops(tc)
            body = ["y.f = x;"; "for i = 1:3"; "  a = i;"; "end"];
            % strict by default (no third arg) ...
            tc.verifyError(@() adigatorParseTape(body, {'x'}), ...
                'adigator:fwdtape:controlflow');
            % ... and explicitly false
            tc.verifyError(@() adigatorParseTape(body, {'x'}, false), ...
                'adigator:fwdtape:controlflow');
        end

        function topLevelNonForRejectedEvenInBlockMode(tc)
            body = ["if x > 0"; "  y.f = x;"; "end"];
            tc.verifyError(@() adigatorParseTape(body, {'x'}, true), ...
                'adigator:fwdtape:controlflow');
        end

        function unterminatedBlockRejected(tc)
            body = ["for i = 1:3"; "  a(i) = x;"]; % no closing end
            tc.verifyError(@() adigatorParseTape(body, {'x'}, true), ...
                'adigator:fwdtape:controlflow');
        end

        function normalStatementsUnchangedInBlockMode(tc)
            % with no loops, allowBlocks=true parses identically to strict mode
            body = ["cada1f1 = w.*x;"; "y.f = sum(cada1f1);"];
            S = adigatorParseTape(body, {'x','w'}, true);
            tc.verifyFalse(any([S.block]));
            tc.verifyEqual(S(1).lhs, 'cada1f1');
            tc.verifyEqual(sort(S(1).deps(:)), {'w';'x'});
            tc.verifyEqual(S(2).deps(:), {'cada1f1'});
            tc.verifyEqual(S(2).writes, {'y'});
        end
    end
end
