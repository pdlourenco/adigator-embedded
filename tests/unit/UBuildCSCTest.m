classdef UBuildCSCTest < matlab.unittest.TestCase
    % UBuildCSCTest  The CSC canonicalizer adigatorBuildCSC and its host-only
    % reconstruction helpers (issue #192, ADR-0030, R31 Phase A; CI_PLAN
    % TS-U-20, REQ-T-03).
    %
    % Pins the sole v2.0 sparse-pattern contract before any generator adopts it
    % (Phase B): the CSC invariants, native->CSC identity detection, the
    % constant-gather permutation on non-native order, input validation, the
    % uint32 index-class policy with its double fallback, and the
    % adigatorCSCToLocs / adigatorCSCToSparse round-trips.
    %
    % util/-only path fixture on purpose: the canonicalizer and helpers must
    % resolve from util/ alone (the generators call them with only util/ on the
    % path), so a stray dependency on lib/ would fail here.
    %
    % Copyright Pedro Lourenço and GMV. Distributed under the GNU General
    % Public License version 3.0.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(root, 'util')));
        end
    end

    methods (Test)
        %% ---- the documented canonical example (ADR-0030 / #192) -------- %%
        function documentedExampleMatchesADR(tc)
            % The exact example from issue #192 / ADR-0030: the native value
            % stream is already CSC order, so perm is identity.
            locs = [1 1; 4 1; 1 2; 2 2; 4 2; 1 3; 3 3];
            [csc, perm, isId] = adigatorBuildCSC([4 3], locs);
            tc.verifyEqual(double(csc.ColPtr(:).'), [1 3 6 8]);
            tc.verifyEqual(double(csc.RowIdx(:).'), [1 4 1 2 4 1 3]);
            tc.verifyEqual(csc.Size, [4 3]);
            tc.verifyEqual(csc.Nnz, 7);
            tc.verifyEqual(csc.IndexBase, 1);
            tc.verifyEqual(perm, (1:7).');
            tc.verifyTrue(isId);
            tc.verifyInvariants(csc);
        end

        %% ---- generic invariants over several shapes ------------------- %%
        function invariantsHoldAcrossShapes(tc)
            cases = { ...
                [4 3], [1 1; 4 1; 1 2; 2 2; 4 2; 1 3; 3 3]; ... % dense-ish
                [5 5], [1 1; 5 5];                              % diagonal ends
                [1 6], [1 1; 1 4; 1 6];                         % single row
                [6 1], [2 1; 5 1];                              % single col
                [3 4], zeros(0,2) };                            % empty
            for k = 1:size(cases, 1)
                [csc, ~, ~] = adigatorBuildCSC(cases{k,1}, cases{k,2});
                tc.verifyInvariants(csc);
            end
        end

        %% ---- identity detection vs non-native gather ------------------ %%
        function identityDetectedOnNativeOrder(tc)
            locs = [1 1; 4 1; 1 2; 2 2];   % already (col,row) sorted
            [~, perm, isId] = adigatorBuildCSC([4 2], locs);
            tc.verifyTrue(isId);
            tc.verifyEqual(perm, (1:4).');
        end

        function nonIdentityPermutationGathersCorrectly(tc)
            % Present the documented pattern in a NON-CSC native order, tag each
            % structural entry with a unique value, and confirm perm gathers the
            % native values into CSC order such that reconstruction is exact.
            cscLocs = [1 1; 4 1; 1 2; 2 2; 4 2; 1 3; 3 3];
            order   = [5 1 7 3 2 6 4];            % an arbitrary native order
            nativeLocs = cscLocs(order, :);
            nativeVals = (10 * nativeLocs(:,1) + nativeLocs(:,2));  % unique tags

            [csc, perm, isId] = adigatorBuildCSC([4 3], nativeLocs);
            tc.verifyFalse(isId, 'shuffled native order must not be identity');

            cscVals = nativeVals(perm);
            % CSC-ordered values must equal the tag of each CSC location
            expectVals = 10 * cscLocs(:,1) + cscLocs(:,2);
            tc.verifyEqual(cscVals, expectVals, ...
                'perm must gather native values into CSC order');

            % and full reconstruction matches an order-independent reference
            ref = sparse(nativeLocs(:,1), nativeLocs(:,2), nativeVals, 4, 3);
            tc.verifyEqual(adigatorCSCToSparse(csc, cscVals), ref);
            tc.verifyInvariants(csc);
        end

        %% ---- empty columns / empty derivative / degenerate shapes ----- %%
        function emptyColumnsAreAdjacentEqualPointers(tc)
            % column 2 has no entries -> ColPtr(2)==ColPtr(3)
            locs = [1 1; 3 1; 2 3];
            [csc, ~, ~] = adigatorBuildCSC([3 3], locs);
            cp = double(csc.ColPtr(:).');
            tc.verifyEqual(cp, [1 3 3 4]);
            tc.verifyEqual(cp(2), cp(3), 'empty column must repeat the pointer');
            tc.verifyInvariants(csc);
        end

        function emptyDerivative(tc)
            [csc, perm, isId] = adigatorBuildCSC([3 2], zeros(0,2));
            tc.verifyEqual(csc.Nnz, 0);
            tc.verifyEqual(double(csc.ColPtr(:).'), [1 1 1]);
            tc.verifyEqual(numel(csc.RowIdx), 0);
            tc.verifyEqual(perm, zeros(0,1));
            tc.verifyTrue(isId, 'empty pattern is trivially identity');
            tc.verifyInvariants(csc);
            % helpers tolerate the empty pattern
            tc.verifyEqual(size(adigatorCSCToLocs(csc)), [0 2]);
            tc.verifyEqual(nnz(adigatorCSCToSparse(csc, zeros(0,1))), 0);
        end

        function acceptsEmptyBracketLocations(tc)
            % [] (not just 0x2) is a valid empty pattern
            [csc, ~, ~] = adigatorBuildCSC([2 2], []);
            tc.verifyEqual(csc.Nnz, 0);
            tc.verifyInvariants(csc);
        end

        %% ---- index-class policy (ADR-0030 D4) ------------------------- %%
        function indexMetadataIsUint32(tc)
            [csc, ~, ~] = adigatorBuildCSC([4 3], [1 1; 4 1; 1 2]);
            tc.verifyClass(csc.ColPtr, 'uint32');
            tc.verifyClass(csc.RowIdx, 'uint32');
            tc.verifyClass(csc.Nnz, 'double');     % Nnz stays double scalar
        end

        function uint32RangeGuardFallsBackToDouble(tc)
            % nrows beyond intmax('uint32') must NOT saturate: fall back to
            % double index metadata with a warning (a silent saturation would be
            % a principle-1 wrong-gather). Uses a huge nrows with few entries so
            % nothing large is allocated.
            hugeRows = double(intmax('uint32')) + 100;
            f = @() adigatorBuildCSC([hugeRows 1], [1 1; 3 1]);
            csc = tc.verifyWarning(f, 'adigator:buildcsc:indexRange');
            tc.verifyClass(csc.ColPtr, 'double');
            tc.verifyClass(csc.RowIdx, 'double');
            tc.verifyInvariants(csc);
        end

        %% ---- input validation ---------------------------------------- %%
        function duplicateLocationsRejected(tc)
            tc.verifyError(@() adigatorBuildCSC([3 3], [1 1; 2 2; 1 1]), ...
                'adigator:buildcsc:duplicate');
        end

        function outOfRangeLocationsRejected(tc)
            tc.verifyError(@() adigatorBuildCSC([3 3], [4 1]), ...
                'adigator:buildcsc:outOfRange');
            tc.verifyError(@() adigatorBuildCSC([3 3], [1 4]), ...
                'adigator:buildcsc:outOfRange');
            tc.verifyError(@() adigatorBuildCSC([3 3], [0 1]), ...
                'adigator:buildcsc:outOfRange');
        end

        function nonIntegerLocationsRejected(tc)
            tc.verifyError(@() adigatorBuildCSC([3 3], [1.5 1]), ...
                'adigator:buildcsc:notInteger');
        end

        function badShapesRejected(tc)
            tc.verifyError(@() adigatorBuildCSC([3 3], [1 2 3]), ...
                'adigator:buildcsc:locShape');
            tc.verifyError(@() adigatorBuildCSC([3 3 3], [1 1]), ...
                'adigator:buildcsc:size');
            tc.verifyError(@() adigatorBuildCSC([-1 3], [1 1]), ...
                'adigator:buildcsc:size');
        end

        %% ---- host-only reconstruction helpers ------------------------- %%
        function helpersRoundTrip(tc)
            locs = [1 1; 4 1; 1 2; 2 2; 4 2; 1 3; 3 3];
            [csc, ~, ~] = adigatorBuildCSC([4 3], locs);

            % CSC -> locs reproduces the CSC-ordered locations
            reLocs = adigatorCSCToLocs(csc);
            tc.verifyEqual(reLocs, locs);                 % this example is CSC order
            tc.verifyClass(reLocs, 'double');

            % locs -> CSC -> locs is a fixed point, and identity (already CSC)
            [csc2, perm2, isId2] = adigatorBuildCSC(csc.Size, reLocs);
            tc.verifyTrue(isId2);
            tc.verifyEqual(perm2, (1:csc.Nnz).');
            tc.verifyEqual(double(csc2.ColPtr), double(csc.ColPtr));
            tc.verifyEqual(double(csc2.RowIdx), double(csc.RowIdx));

            % pattern reconstruction: ones -> logical superset matches locs
            pat = adigatorCSCToSparse(csc, ones(csc.Nnz,1));
            [I, J] = find(pat);
            tc.verifyEqual(sortrows([I J]), sortrows(locs));
        end

        function toSparseLengthMismatchRejected(tc)
            [csc, ~, ~] = adigatorBuildCSC([3 3], [1 1; 2 2]);
            tc.verifyError(@() adigatorCSCToSparse(csc, [1;2;3]), ...
                'adigator:csctosparse:length');
        end
    end

    methods
        function verifyInvariants(tc, csc)
            % The binding CSC invariants (ADR-0030 D2), checked structurally.
            cp = double(csc.ColPtr(:));
            ri = double(csc.RowIdx(:));
            ncols = csc.Size(2);
            nrows = csc.Size(1);

            tc.verifyEqual(numel(cp), ncols + 1, 'ColPtr length must be ncols+1');
            tc.verifyEqual(numel(ri), csc.Nnz, 'RowIdx length must be Nnz');
            tc.verifyEqual(cp(1), 1, 'ColPtr(1) must be 1');
            tc.verifyEqual(cp(end), csc.Nnz + 1, 'ColPtr(end) must be Nnz+1');
            tc.verifyTrue(all(diff(cp) >= 0), 'ColPtr must be non-decreasing');
            if ~isempty(ri)
                tc.verifyTrue(all(ri >= 1 & ri <= nrows), 'RowIdx in [1,nrows]');
            end
            % strictly increasing RowIdx within each column
            for j = 1:ncols
                seg = ri(cp(j):cp(j+1)-1);
                if numel(seg) > 1
                    tc.verifyTrue(all(diff(seg) > 0), ...
                        sprintf('RowIdx must strictly increase within column %d', j));
                end
            end
        end
    end
end
