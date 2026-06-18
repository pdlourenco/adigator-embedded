classdef UPruneMatTest < matlab.unittest.TestCase
    % UPruneMatTest  Unit tests for embedding/prune_adigator_mat.m
    %
    % CI plan: TS-U-04, verifies REQ-C-05.
    % Pins ANALYSIS.md bugs: B1 (Data* must remain double), B5 (output
    % initialized when no function matches).

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            repoRoot = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(repoRoot,'embedding')));
        end
    end

    methods (Test)
        function indexFieldsAreDowncast(tc)
            s.myfun.Gator1Data.Index1 = [1 2 3];
            out = prune_adigator_mat(s, {'myfun'});
            tc.verifyClass(out.myfun.Gator1Data.Index1, 'uint32');
            tc.verifyEqual(double(out.myfun.Gator1Data.Index1), [1 2 3]);
        end

        function negativeIndexFieldsUseInt32(tc)
            s.myfun.Gator1Data.Index1 = [-1 0 5];
            out = prune_adigator_mat(s, {'myfun'});
            tc.verifyClass(out.myfun.Gator1Data.Index1, 'int32');
            tc.verifyEqual(double(out.myfun.Gator1Data.Index1), [-1 0 5]);
        end

        function dataFieldsStayDouble(tc)
            % B1: integer-valued value constants are used in arithmetic by
            % the generated code and must not be down-cast.
            s.myfun.Gator1Data.Index1 = [1 2];
            s.myfun.Gator1Data.Data1  = [2 0; 0 2];   % e.g. constant matrix
            s.myfun.Gator1Data.Data2  = 3;            % integer-valued scalar
            out = prune_adigator_mat(s, {'myfun'});
            tc.verifyClass(out.myfun.Gator1Data.Data1, 'double');
            tc.verifyEqual(out.myfun.Gator1Data.Data1, [2 0; 0 2]);
            tc.verifyClass(out.myfun.Gator1Data.Data2, 'double');
        end

        function nearIntegerDataIsNotRounded(tc)
            v = 1 + 1e-13; % previously down-cast by the 1e-12 tolerance
            s.myfun.Gator1Data.Data1 = v;
            out = prune_adigator_mat(s, {'myfun'});
            tc.verifyEqual(out.myfun.Gator1Data.Data1, v);
        end

        function sparseFieldsAreLeftAlone(tc)
            s.myfun.Gator1Data.Data1 = sparse([1 0; 0 1]);
            out = prune_adigator_mat(s, {'myfun'});
            tc.verifyTrue(issparse(out.myfun.Gator1Data.Data1));
            tc.verifyEqual(full(out.myfun.Gator1Data.Data1), [1 0; 0 1]);
        end

        function emptyDataFieldsAreDropped(tc)
            s.myfun.Gator1Data.Data1 = [];
            s.myfun.Gator1Data.Index1 = [1 2];
            out = prune_adigator_mat(s, {'myfun'});
            tc.verifyFalse(isfield(out.myfun.Gator1Data, 'Data1'));
            tc.verifyTrue(isfield(out.myfun.Gator1Data, 'Index1'));
        end

        function nonGatorFieldsAreDropped(tc)
            s.myfun.Gator1Data.Index1 = 1;
            s.myfun.Derivative = struct('foo', 1); % re-differentiation metadata
            out = prune_adigator_mat(s, {'myfun'});
            tc.verifyFalse(isfield(out.myfun, 'Derivative'));
        end

        function missingFunctionDoesNotError(tc)
            % B5: output must be initialized even when nothing matches.
            out = prune_adigator_mat(struct('other', 1), {'myfun'});
            tc.verifyClass(out, 'struct');
            tc.verifyFalse(isfield(out, 'myfun'));
        end

        function secondDerivativeDataKept(tc)
            s.f.Gator1Data.Index1 = [1 2];
            s.f.Gator2Data.Index1 = [3 4];
            out = prune_adigator_mat(s, {'f'});
            tc.verifyTrue(isfield(out.f, 'Gator1Data'));
            tc.verifyTrue(isfield(out.f, 'Gator2Data'));
        end
    end
end
