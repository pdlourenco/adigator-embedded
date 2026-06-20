classdef UForwardTapeTest < matlab.unittest.TestCase
    % UForwardTapeTest  Unit tests for adigatorForwardTapeSlice, the
    % statement parser / backward value-tape slicer extracted from
    % adigatorGenRevGradFile (roadmap R7a follow-up; foundation for the R7b
    % field-slice, issue #21). Exercises parsing, dependency extraction, the
    % backward slice (dead-statement removal, derivative-chain exclusion,
    % scatter reads-old), and the rejection guards - in isolation, with
    % hand-written tape snippets, no MATLAB-toolbox dependency.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
        end
    end

    methods (Test)
        function parsesAndSlicesValueTape(tc)
            % keeps the value chain to y.f, drops a dead statement, and never
            % admits the derivative field y.dx (which trails the output)
            body = [ ...
                "cada1f1 = w.*x;"; ...
                "cada1f2 = exp(cada1f1);"; ...
                "deadv = x.*w;"; ...
                "y.f = sum(cada1f2);"; ...
                "y.dx = cada1f2.*w;"];
            S = adigatorForwardTapeSlice(body, {'x','w'}, 'y', 'x');

            tc.verifyEqual(numel(S), 3);
            tc.verifyEqual({S.lhs}, {'cada1f1','cada1f2','y.f'});
            tc.verifyEqual(S(1).rhs, 'w.*x');
            tc.verifyEqual(S(3).lhs, 'y.f');
            tc.verifyEqual(S(3).lhsSubs, '');
            tc.verifyEqual(S(3).deps, {'cada1f2'});
            % the dead statement and the derivative field are gone
            tc.verifyFalse(any(strcmp({S.lhs},'deadv')));
            tc.verifyFalse(any(strcmp({S.lhs},'y.dx')));
            % classify/execute fields are left empty for a downstream pass
            tc.verifyTrue(all(cellfun(@isempty,{S.active})));
        end

        function excludesDerivativeFieldBeforeOutput(tc)
            % a derivative-field writer (y.dx) that precedes y.f must still be
            % excluded even though its base 'y' is wanted
            body = [ ...
                "cada1f1 = x;"; ...
                "y.dx = cada1f1;"; ...
                "y.f = sum(cada1f1);"];
            S = adigatorForwardTapeSlice(body, {'x'}, 'y', 'x');
            tc.verifyEqual({S.lhs}, {'cada1f1','y.f'});
            tc.verifyFalse(any(strcmp({S.lhs},'y.dx')));
        end

        function scatterReadsOldValue(tc)
            % a scatter assignment v(subs)=... depends on the prior v AND on
            % the RHS variables; both v=zeros and the scatter stay live
            body = [ ...
                "v = zeros(4,1);"; ...
                "v(1:2) = x;"; ...
                "y.f = sum(v);"];
            S = adigatorForwardTapeSlice(body, {'x'}, 'y', 'x');
            tc.verifyEqual(numel(S), 3);
            tc.verifyEqual(S(2).lhs, 'v');
            tc.verifyEqual(S(2).lhsSubs, '1:2');
            tc.verifyTrue(ismember('v', S(2).deps)); % reads the old v
            tc.verifyTrue(ismember('x', S(2).deps)); % and the RHS
        end

        function rejectsRolledControlFlow(tc)
            body = [ ...
                "y.f = 1;"; ...
                "for cadaforcount1 = 1:3"; ...
                "  a = cadaforcount1;"; ...
                "end"];
            tc.verifyError(@() adigatorForwardTapeSlice(body, {'x'}, 'y', 'x'), ...
                'adigator:fwdtape:controlflow');
        end

        function rejectsUnparseableStatement(tc)
            % missing terminating semicolon
            tc.verifyError(@() adigatorForwardTapeSlice( ...
                "y.f = sum(x)", {'x'}, 'y', 'x'), ...
                'adigator:fwdtape:parse');
        end

        function rejectsMissingOutputAssignment(tc)
            % no <OutName>.f in the body
            tc.verifyError(@() adigatorForwardTapeSlice( ...
                "a = x;", {'x'}, 'y', 'x'), ...
                'adigator:fwdtape:parse');
        end
    end
end
