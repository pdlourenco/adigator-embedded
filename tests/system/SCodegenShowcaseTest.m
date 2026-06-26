classdef SCodegenShowcaseTest < matlab.unittest.TestCase
    % SCodegenShowcaseTest  Guards the R17b C-level derivative showcase
    % (issue #73 item B): compiles the embeddable derivative cells through MATLAB
    % Coder and asserts they build, the compiled MEX matches MATLAB, and the
    % headline holds - the reverse gradient's compiled C is leaner than the
    % forward gradient's (the §3.5 zero-ROM result carried through to C).
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
        function cellsCompileMatchAndReverseIsLeaner(tc)
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

            % headline: reverse AD gradient C < forward AD gradient C (same
            % cost), and the hand-coded analytical gradient is leaner still (the
            % AD-vs-analytical floor, #73).
            gr = report.rows(strcmp({report.rows.DerType},'gradient'));
            fwd = gr(strcmp({gr.impl},'AD'));
            ana = gr(strcmp({gr.impl},'analytic'));
            rv = report.rows(strcmp({report.rows.DerType},'gradient-reverse'));
            rev = rv(strcmp({rv.impl},'AD'));   % impl filter for symmetry (future-proof)
            tc.assertNotEmpty(fwd, 'forward AD gradient cell missing');
            tc.assertNotEmpty(rev, 'reverse AD gradient cell missing');
            tc.assertNotEmpty(ana, 'analytical gradient reference missing');
            if fwd.ok && rev.ok
                tc.verifyLessThan(rev.cBytes, fwd.cBytes, ...
                    'reverse gradient compiled C should be leaner than forward (§3.5)');
            end
            if fwd.ok && ana.ok
                tc.verifyLessThanOrEqual(ana.cBytes, fwd.cBytes, ...
                    'hand-coded analytical gradient should not be larger than forward AD');
            end
        end
    end
end
