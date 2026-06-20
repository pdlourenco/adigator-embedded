classdef UPeepholeTest < matlab.unittest.TestCase
    % UPeepholeTest  Unit tests for adigatorPeepholeUnionCopy (roadmap R7c,
    % issue #21): collapsing no-op union-copy pairs
    %   v = zeros(K,1); v(idx) = src;   ->   v = reshape(src,K,1);
    % only when idx resolves to the ORDERED identity 1:K. Exercises the
    % Gator-index and literal-range resolutions, the ordered-vs-permuted and
    % partial-fill distinctions, the self-reference and vectorized-form skips,
    % and the conservative bail-outs. Text-in / text-out on hand-written
    % snippets with a synthetic gator-data struct; no toolbox, no file I/O.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
        end
    end

    methods (Test)
        function collapsesOrderedIdentity(tc)
            gd.Gator1Data.Index1 = [1;2;3];   % ordered identity -> collapse
            gd.Gator1Data.Index2 = [2;1;3];   % permuted        -> keep
            [out, info] = adigatorPeepholeUnionCopy(fixtureFile(), gd);

            tc.verifyTrue(info.changed);
            tc.verifyEqual(info.count, 1);
            tc.verifyTrue(any(contains(out,'cada1td1 = reshape(cada1f2,3,1);')));
            tc.verifyFalse(any(contains(out,'cada1td1 = zeros')));
            tc.verifyFalse(any(contains(out,'cada1td1(Gator1Data.Index1')));
            % the permuted (non-identity) pair is untouched
            tc.verifyTrue(any(contains(out,'cada1td2 = zeros(3,1);')));
            tc.verifyTrue(any(contains(out,'cada1td2(Gator1Data.Index2,1) = cada1f3;')));
            % skeleton preserved
            tc.verifyTrue(any(contains(out,'function ADiGator_LoadData()')));
        end

        function partialFillIsKept(tc)
            gd.Gator1Data.Index1 = [1;2;3];
            gd.Gator1Data.Index2 = [1;3];     % fills 2 of 3 rows -> not identity
            [~, info] = adigatorPeepholeUnionCopy(fixtureFile(), gd);
            tc.verifyEqual(info.count, 1);    % only cada1td1 collapses
        end

        function collapsesLiteralRange(tc)
            f = [ ...
                preamble(); ...
                "cada1td3 = zeros(2,1);"; ...
                "cada1td3(1:2,1) = cada1f5;"; ...
                "y.f = cada1f1;"; ...
                postamble()];
            [out, info] = adigatorPeepholeUnionCopy(f, struct('Gator1Data',struct()));
            tc.verifyEqual(info.count, 1);
            tc.verifyTrue(any(contains(out,'cada1td3 = reshape(cada1f5,2,1);')));
        end

        function skipsSelfReference(tc)
            f = [ ...
                preamble(); ...
                "cada1td4 = zeros(2,1);"; ...
                "cada1td4(1:2) = cada1td4 + 1;"; ...   % RHS reads v -> unsafe
                "y.f = cada1f1;"; ...
                postamble()];
            [~, info] = adigatorPeepholeUnionCopy(f, struct('Gator1Data',struct()));
            tc.verifyFalse(info.changed);
        end

        function skipsUnresolvableIndex(tc)
            f = [ ...
                preamble(); ...
                "cada1td5 = zeros(3,1);"; ...
                "cada1td5(somevar,1) = cada1f6;"; ...  % index not a constant
                "y.f = cada1f1;"; ...
                postamble()];
            [~, info] = adigatorPeepholeUnionCopy(f, struct('Gator1Data',struct()));
            tc.verifyFalse(info.changed);
        end

        function skipsVectorizedForm(tc)
            f = [ ...
                preamble(); ...
                "cada1td6 = zeros(size(cada1f7,1),3);"; ...
                "cada1td6(:,Gator1Data.Index1) = cada1f8;"; ...
                "y.f = cada1f1;"; ...
                postamble()];
            gd.Gator1Data.Index1 = [1;2;3];
            [~, info] = adigatorPeepholeUnionCopy(f, gd);
            tc.verifyFalse(info.changed); % zeros(size(..),m) is not zeros(K,1)
        end

        function bailsWithoutGatorData(tc)
            [out, info] = adigatorPeepholeUnionCopy(fixtureFile(), []);
            tc.verifyFalse(info.changed);
            tc.verifyEqual(info.reason, 'no gator data');
            tc.verifyEqual(out, string(fixtureFile()));
        end

        function bailsOnMissingMarkers(tc)
            f = ["function y = mf_ADiGatorJac(gator_x)"; "y.f = gator_x.f;"; "end"];
            [~, info] = adigatorPeepholeUnionCopy(f, struct('Gator1Data',struct()));
            tc.verifyFalse(info.changed);
            tc.verifyEqual(info.reason, 'body markers not found');
        end
    end
end

% ---------------------------- fixtures --------------------------------- %
function f = preamble()
f = [ ...
    "function y = mf_ADiGatorJac(gator_x)"; ...
    "global ADiGator_mf_ADiGatorJac"; ...
    "if isempty(ADiGator_mf_ADiGatorJac); ADiGator_LoadData(); end"; ...
    "Gator1Data = ADiGator_mf_ADiGatorJac.mf_ADiGatorJac.Gator1Data;"; ...
    "% ADiGator Start Derivative Computations"];
end

function f = postamble()
f = [ ...
    "end"; ...
    "function ADiGator_LoadData()"; ...
    "global ADiGator_mf_ADiGatorJac"; ...
    "load('mf_ADiGatorJac.mat')"; ...
    "end"];
end

function f = fixtureFile()
% two union-copy pairs: cada1td1 (Index1) and cada1td2 (Index2)
f = [ ...
    preamble(); ...
    "cada1td1 = zeros(3,1);"; ...
    "cada1td1(Gator1Data.Index1,1) = cada1f2;"; ...
    "cada1td2 = zeros(3,1);"; ...
    "cada1td2(Gator1Data.Index2,1) = cada1f3;"; ...
    "y.dx = cada1td1;"; ...
    "y.f = cada1f1;"; ...
    postamble()];
end
