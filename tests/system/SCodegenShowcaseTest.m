classdef SCodegenShowcaseTest < matlab.unittest.TestCase
    % SCodegenShowcaseTest  Guards the R17b/R17c C-level derivative showcase
    % (issue #73 item B): compiles the embeddable derivative cells through
    % Embedded Coder and asserts they build, the compiled MEX matches MATLAB, and
    % the honest compiled footprint (ROM/RAM/stack) is measured and behaves as
    % R17c found - the vectorized forward/reverse gradient ROM CONVERGES and
    % static RAM is 0 (embeddable forms carry ~0 static data). A source-byte size
    % ordering is deliberately NOT asserted - the `cBytes` column is a
    % boilerplate-dominated proxy, kept only as a labelled secondary (ADR-0027).
    %
    % Heavyweight (each cell is a Coder build) and Coder-gated: on a runner
    % without MATLAB Coder the whole test skips cleanly via assumption, exactly
    % like SCodegenTest. The compiled-footprint assertions additionally require
    % the standalone gcc/size toolchain; where it is absent the footprint fields
    % stay -1 and those checks skip (the build/equivalence checks still run).
    % Runs in the extended/codegen CI suite, not the PR gate.

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
                    % R17c+: the numerical-FD baseline is codegen-independent, so
                    % it must measure for the showcase anchors; -1 means localFD
                    % silently broke (nothing else here would catch it).
                    tc.verifyGreaterThanOrEqual(r.fdMs, 0, ...
                        sprintf('%s/%s: numerical-FD cost not measured (localFD broke?)', r.fn, r.DerType));
                    % R17c: the honest compiled footprint, when the gcc/size
                    % toolchain is present (fields stay -1 on a Coder-only box).
                    if r.romBytes >= 0
                        tc.verifyGreaterThan(r.romBytes, 0, ...
                            sprintf('%s/%s: ROM not measured', r.fn, r.DerType));
                        % every derivative function here has a real (>0) frame,
                        % so stack==0 means a missing .su, not a leaf function -
                        % assert >0 so it is caught rather than silently reported.
                        tc.verifyGreaterThan(r.stackBytes, 0, ...
                            sprintf('%s/%s: stack not measured (missing .su?)', r.fn, r.DerType));
                        % RAM can legitimately be 0 (embeddable forms carry ~0
                        % static data), so a presence check is all we can assert.
                        tc.verifyGreaterThanOrEqual(r.ramBytes, 0, ...
                            sprintf('%s/%s: RAM not measured', r.fn, r.DerType));
                    end
                end
            end

            % the forward / reverse / analytical gradient cells all build and
            % match. NB: we deliberately do NOT assert a source-byte size
            % ordering - the `cBytes` column is a sum of generated source bytes
            % (boilerplate-dominated), a poor ROM proxy (ADR-0027). The honest
            % compiled comparison is on ROM below.
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

            % R17c headline: for the vectorized cost the forward and reverse
            % gradient compiled ROM CONVERGE (embeddable forms carry ~0 static
            % data) and static RAM is 0. Assert only when the footprint toolchain
            % measured both; allow a small cross-compiler tolerance rather than
            % byte-exact equality.
            if fwd.romBytes >= 0 && rev.romBytes >= 0
                tc.verifyLessThanOrEqual(abs(rev.romBytes - fwd.romBytes), ...
                    max(16, 0.10*fwd.romBytes), ...
                    'forward/reverse gradient compiled ROM should converge');
                tc.verifyEqual(fwd.ramBytes, 0, ...
                    'vectorized forward gradient should carry 0 static RAM');
                tc.verifyEqual(rev.ramBytes, 0, ...
                    'vectorized reverse gradient should carry 0 static RAM');
            end

            % issue #73: the FINITE-DIFFERENCE method is now a first-class
            % compiled cell (not just an interpreted-cost column). It builds and
            % matches at the loose FD tolerance, and - because it evaluates the
            % cost n times - its compiled ROM is HEAVIER than the hand-coded
            % analytical derivative's (the "cheap to write, but O(n) evals in
            % flash, and inexact" story that motivates AD).
            fdrows = report.rows(strcmp({report.rows.impl},'FD'));
            tc.assertNotEmpty(fdrows, 'FD method cells missing from the C showcase');
            for f = fdrows
                tc.verifyTrue(f.ok, ...
                    sprintf('FD %s/%s must build + match at FD tolerance: %s', f.fn, f.DerType, f.note));
                a = report.rows(strcmp({report.rows.impl},'analytic') & ...
                    strcmp({report.rows.fn},f.fn) & strcmp({report.rows.DerType},f.DerType));
                if ~isempty(a) && f.romBytes >= 0 && a.romBytes >= 0
                    tc.verifyGreaterThan(f.romBytes, a.romBytes, ...
                        sprintf('FD %s/%s ROM should exceed the analytical derivative''s', f.fn, f.DerType));
                end
            end
        end
    end
end
