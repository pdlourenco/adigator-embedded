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

        function oversizedIndexErrorsInsteadOfSaturating(tc)
            % M7: an Index entry above the uint32 range must error, not silently
            % saturate to intmax('uint32') (which would corrupt the embedded
            % index table). ANALYSIS 1.5 assumed 2^32 but never checked it.
            s.myfun.Gator1Data.Index1 = [1 2 2^32];   % 2^32 > intmax('uint32')
            tc.verifyError(@() prune_adigator_mat(s, {'myfun'}), ...
                'adigator:embed:indexRange');
        end

        function largestInRangeIndexStillDowncasts(tc)
            % M7 control: the largest in-range value (intmax('uint32')) is not
            % rejected and still down-casts cleanly.
            top = double(intmax('uint32'));           % 4294967295
            s.myfun.Gator1Data.Index1 = [1 top];
            out = prune_adigator_mat(s, {'myfun'});
            tc.verifyClass(out.myfun.Gator1Data.Index1, 'uint32');
            tc.verifyEqual(double(out.myfun.Gator1Data.Index1), [1 top]);
        end

        function emptyIndexStillDowncastsToUint32(tc)
            % M7 boundary: an empty Index* field must still down-cast to uint32
            % (the pre-M7 behaviour: empty takes the vacuously-true nonnegative
            % branch). The range guard must not skip the cast for empty arrays.
            s.myfun.Gator1Data.Index1 = zeros(0,1);   % empty double
            out = prune_adigator_mat(s, {'myfun'});
            tc.verifyTrue(isfield(out.myfun.Gator1Data, 'Index1'));
            tc.verifyClass(out.myfun.Gator1Data.Index1, 'uint32');
            tc.verifyEmpty(out.myfun.Gator1Data.Index1);
        end

        function belowRangeNegativeIndexErrors(tc)
            % M7 symmetric guard: a negative entry below the int32 range must
            % also error rather than saturate.
            s.myfun.Gator1Data.Index1 = [-2^31 - 1, 0];  % < intmin('int32')
            tc.verifyError(@() prune_adigator_mat(s, {'myfun'}), ...
                'adigator:embed:indexRange');
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

        % --- slice-before-prune data half (issue #21): the optional REFERENCED
        % map drops Index* the slimmed code no longer reads -----------------

        function referencedDropsUnreadIndex(tc)
            % dead index drops, live index kept (the data-shrink payoff)
            s.myfun.Gator1Data.Index1 = [1 2 3];
            s.myfun.Gator1Data.Index2 = [4 5];
            ref.myfun.index = "Gator1Data.Index1";
            ref.myfun.table = "Gator1Data";
            out = prune_adigator_mat(s, {'myfun'}, ref);
            tc.verifyTrue(isfield(out.myfun.Gator1Data, 'Index1'));
            tc.verifyFalse(isfield(out.myfun.Gator1Data, 'Index2'));
            tc.verifyClass(out.myfun.Gator1Data.Index1, 'uint32'); % still down-cast
        end

        function referencedKeepsReferencedEmptyIndex(tc)
            % an empty Index that the code DOES reference must survive (the
            % boilerplate still accesses the field)
            s.myfun.Gator1Data.Index1 = zeros(0,0,'uint32');
            ref.myfun.index = "Gator1Data.Index1";
            ref.myfun.table = "Gator1Data";
            out = prune_adigator_mat(s, {'myfun'}, ref);
            tc.verifyTrue(isfield(out.myfun.Gator1Data, 'Index1'));
        end

        function referencedFallsBackWhenShrinkWouldEmptyReferencedTable(tc)
            % a function that reads the table name but indexes nothing must NOT
            % shrink to a zero-field struct (coder.const(struct()) is an
            % unexercised codegen shape); it falls back to the unshrunk keep-set
            % so `Gator1Data = coder.const(...Gator1Data)` keeps its proven
            % shape (the setfun case)
            s.myfun.Gator1Data.Index1 = [1 2]; % unreferenced
            ref.myfun.index = strings(0,1);
            ref.myfun.table = "Gator1Data";
            out = prune_adigator_mat(s, {'myfun'}, ref);
            tc.verifyTrue(isfield(out.myfun, 'Gator1Data'));
            tc.verifyTrue(isfield(out.myfun.Gator1Data, 'Index1')); % unshrunk fallback
        end

        function referencedDropsWholeTableWhenUnreferenced(tc)
            % a table neither indexed nor named by the slimmed code is dropped
            s.myfun.Gator1Data.Index1 = [1 2];
            ref.myfun.index = strings(0,1);
            ref.myfun.table = strings(0,1);
            out = prune_adigator_mat(s, {'myfun'}, ref);
            tc.verifyTrue(isfield(out, 'myfun'));
            tc.verifyFalse(isfield(out.myfun, 'Gator1Data'));
        end

        function referencedLeavesDataFieldsAlone(tc)
            % the map governs Index* only; Data* stays under the non-empty rule
            s.myfun.Gator1Data.Index1 = [1 2]; % unreferenced -> dropped
            s.myfun.Gator1Data.Data1  = [2 0; 0 2];
            ref.myfun.index = strings(0,1);
            ref.myfun.table = "Gator1Data";
            out = prune_adigator_mat(s, {'myfun'}, ref);
            tc.verifyFalse(isfield(out.myfun.Gator1Data, 'Index1'));
            tc.verifyTrue(isfield(out.myfun.Gator1Data, 'Data1'));
            tc.verifyClass(out.myfun.Gator1Data.Data1, 'double');
        end

        function absentFunctionKeepsAllIndex(tc)
            % a map that does not mention this function => keep-all (the
            % conservative default for a not-confidently-parsed function)
            s.myfun.Gator1Data.Index1 = [1 2];
            s.myfun.Gator1Data.Index2 = [3 4];
            ref.otherfun.index = "Gator1Data.Index1";
            ref.otherfun.table = "Gator1Data";
            out = prune_adigator_mat(s, {'myfun'}, ref);
            tc.verifyTrue(isfield(out.myfun.Gator1Data, 'Index1'));
            tc.verifyTrue(isfield(out.myfun.Gator1Data, 'Index2'));
        end

        function emptyMapMatchesTwoArgBehaviour(tc)
            % an empty map (or the omitted third arg) keeps all Index*
            s.myfun.Gator1Data.Index1 = [1 2];
            s.myfun.Gator1Data.Index2 = [3 4];
            out3 = prune_adigator_mat(s, {'myfun'}, struct());
            out2 = prune_adigator_mat(s, {'myfun'});
            tc.verifyEqual(out3, out2);
            tc.verifyTrue(isfield(out3.myfun.Gator1Data, 'Index1'));
            tc.verifyTrue(isfield(out3.myfun.Gator1Data, 'Index2'));
        end
    end
end
