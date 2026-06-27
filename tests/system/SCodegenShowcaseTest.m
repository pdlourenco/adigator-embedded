classdef SCodegenShowcaseTest < matlab.unittest.TestCase
    % SCodegenShowcaseTest  Guards the R17b C-level derivative showcase
    % (issue #73 item B): compiles the embeddable derivative cells through MATLAB
    % Coder and asserts they build and the compiled MEX matches MATLAB. A
    % source-byte size ordering is deliberately NOT asserted - the `cBytes`
    % column is a boilerplate-dominated proxy; the honest compiled
    % ROM/RAM/stack comparison is R17c.
    %
    % Heavyweight (each cell is a Coder build) and Coder-gated: on a runner
    % without MATLAB Coder the whole test skips cleanly via assumption, exactly
    % like SCodegenTest. Runs in the extended/codegen CI suite, not the PR gate.

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
        function cellsCompileAndMatch(tc)
            % sweepN = [] -> table cells only (no figure), fast as it gets here.
            report = derivShowcaseC('n',8,'sweepN',[],'verbose',false);
            tc.assumeTrue(report.available, ...
                'MATLAB Coder not available - skipping C-level showcase.');

            % builds succeeded + compiled C matches MATLAB
            tc.verifyEqual(report.nFail, 0, ...
                sprintf('%d cell(s) failed to build or matched MATLAB', report.nFail));
            for r = report.rows
                if ~strcmp(r.note,'skip')
                    tc.verifyTrue(r.ok, sprintf('%s/%s: %s', r.fn, r.DerType, r.note));
                    tc.verifyGreaterThan(r.cBytes, 0, ...
                        sprintf('%s/%s: no generated C measured', r.fn, r.DerType));
                end
            end

            % the forward / reverse / analytical gradient cells all build and
            % match. NB: we deliberately do NOT assert a source-byte size
            % ordering here - the `cBytes` column is a sum of generated source
            % bytes (boilerplate-dominated), a poor ROM proxy; the real compiled
            % ROM/RAM/stack comparison (Embedded Coder + size/-fstack-usage) is
            % R17c, pinned there.
            gr = report.rows(strcmp({report.rows.DerType},'gradient'));
            fwd = gr(strcmp({gr.impl},'AD'));
            ana = gr(strcmp({gr.impl},'analytic'));
            rv = report.rows(strcmp({report.rows.DerType},'gradient-reverse'));
            rev = rv(strcmp({rv.impl},'AD'));   % impl filter for symmetry (future-proof)
            tc.assertNotEmpty(fwd, 'forward AD gradient cell missing');
            tc.assertNotEmpty(rev, 'reverse AD gradient cell missing');
            tc.assertNotEmpty(ana, 'analytical gradient reference missing');
            tc.verifyTrue(fwd.ok && rev.ok && ana.ok, ...
                'forward / reverse / analytical gradient must all build + match');
        end
    end
end
