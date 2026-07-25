classdef SCscMetadataTest < matlab.unittest.TestCase
    % SCscMetadataTest  Guards the CSC pattern-metadata measurement
    % (issue #192, ADR-0030 phase-C bench acceptance; bench/cscMetadataSize.m,
    % bench/SHOWCASE.md ## CSC pattern metadata). Confirms the exported CSC
    % pattern index count is `nnz + ncols + 1`, that this is smaller than the
    % removed two-copy surface (coordinate `*Locs` + sparse `*Structure`), and
    % that CSC beats coordinates outright when `nnz > ncols+1`. Also pins each
    % shape's structural `nnz` in closed form so an overmap-widened pattern (the
    % B23/B27 class) trips here instead of silently staling the SHOWCASE numbers.
    %
    % Lightweight: interpreted generation only (no Embedded Coder), so it runs
    % in the PR gate unlike the loopbound-footprint test.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(root,'bench')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function metadataSizeInvariantsHold(tc)
            n = 8;
            r = cscMetadataSize('n', n, 'verbose', false);
            tc.verifyNumElements(r, 4, 'expected the four measured shapes');

            for i = 1:numel(r)
                s = r(i);
                % the sole exported pattern is ColPtr(ncols+1) + RowIdx(nnz)
                tc.verifyEqual(s.cscIdx, s.nnz + s.cols + 1, ...
                    sprintf('%s: cscIdx must be nnz+ncols+1', s.label));
                % the removed coordinate *Locs held 2*nnz indices
                tc.verifyEqual(s.coordIdx, 2 * s.nnz, ...
                    sprintf('%s: coordIdx must be 2*nnz', s.label));
                % old exported BOTH copies (Locs + sparse Structure)
                tc.verifyEqual(s.oldPattern, s.coordIdx + s.cscIdx, ...
                    sprintf('%s: oldPattern must be coordIdx+cscIdx', s.label));
                % exporting one representation instead of two is a net reduction
                tc.verifyGreaterThan(s.reduction, 1, ...
                    sprintf('%s: CSC must be smaller than the two-copy surface', s.label));
            end

            % CSC beats coordinates outright exactly when nnz > ncols+1
            for i = 1:numel(r)
                s = r(i);
                if s.nnz > s.cols + 1
                    tc.verifyLessThan(s.cscIdx, s.coordIdx, ...
                        sprintf('%s: nnz>ncols+1 so CSC index count must beat 2*nnz', s.label));
                end
            end

            % pin each shape's structural nnz in closed form: a future overmap
            % that widened the pattern (the B23/B27 class) would silently stale
            % the published SHOWCASE numbers while the identity checks above
            % stayed green - this makes the bench a structural-sparsity tripwire.
            expNnz = containers.Map( ...
                {'scalar-cost gradient [n x 1] (dense)', ...
                 'arrowhead Jacobian [n x n] (dense row+col)', ...
                 'diagonal Jacobian [n x n] (sparse)', ...
                 'scalar-cost Hessian [n x n] (diagonal)'}, ...
                {n, 3*n-2, n, n});
            for i = 1:numel(r)
                tc.verifyEqual(r(i).nnz, expNnz(r(i).label), ...
                    sprintf('%s: structural nnz drifted from the documented pattern', ...
                    r(i).label));
            end

            % the dense gradient ([n,1], ncols=1) is the clearest win
            grad = r(strcmp({r.label}, 'scalar-cost gradient [n x 1] (dense)'));
            tc.assertNotEmpty(grad);
            tc.verifyEqual(grad.cols, 1);
            tc.verifyLessThan(grad.cscIdx, grad.coordIdx);
        end
    end
end
