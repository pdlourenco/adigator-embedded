classdef IInterprocGapEquivTest < matlab.unittest.TestCase
    % IInterprocGapEquivTest  Issue #44 part 1b (interprocedural under-demand)
    % regression guard, in the CI gate.
    %
    % Thin wrapper around the license-free core tests/offline/
    % gap_interproc_equiv.m, which executes the committed generated gapfun
    % gradient fixtures (tests/fixtures/gen_dialect/{slim0,slim1}) and checks
    % they reproduce the analytic gradient grad_z gapfun = w + 2*z (itself
    % cross-checked by finite difference) and that the slimmed fixture is
    % numerically identical to the unslimmed one. gapfun is interprocedural
    % (it calls conefun/setfun, conefun calls setfun), so this exercises the
    % multi-subfunction derivative end to end without regenerating it.
    %
    % The core runs in base MATLAB and in GNU Octave alike (it only executes
    % the committed fixtures - generation still needs MATLAB per
    % docs/CI_PLAN.md); this wrapper puts it in the MATLAB CI gate, while the
    % same core stays runnable license-free for local verification.
    %
    % See ADR-0008 for the committed-fixture / offline-core rationale.
    %
    % The equivalence contract is numeric, not structural: slim1 is allowed to
    % shrink (and will, once part 1b's interprocedural slimming lands and the
    % fixtures are regenerated), provided its NUMBERS match slim0 exactly -
    % hence the AbsTol 0 below, and no byte/index comparison.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(root, 'tests', 'offline')));
        end
    end

    methods (Test)
        function fixturesMatchAnalyticAndEachOther(tc)
            r = gap_interproc_equiv();   % errors internally on any mismatch

            % re-assert through the unittest framework so a regression is
            % reported as a verification failure with diagnostics, not a raw error
            tc.verifyEqual(r.Jslim0, r.Jref, 'AbsTol', 1e-9, ...
                'unslimmed fixture gradient differs from analytic w+2z');
            tc.verifyEqual(r.Jslim1, r.Jref, 'AbsTol', 1e-9, ...
                'slimmed fixture gradient differs from analytic w+2z');
            tc.verifyEqual(r.Fslim0, r.Fref, 'AbsTol', 1e-9, ...
                'unslimmed fixture value differs from analytic');
            tc.verifyEqual(r.Fslim1, r.Fref, 'AbsTol', 1e-9, ...
                'slimmed fixture value differs from analytic');

            % the interprocedural-equivalence invariant: numbers identical
            tc.verifyEqual(r.Jslim1, r.Jslim0, 'AbsTol', 0, ...
                'slimmed gradient must be numerically identical to unslimmed');
            tc.verifyEqual(r.Fslim1, r.Fslim0, 'AbsTol', 0, ...
                'slimmed value must be numerically identical to unslimmed');
        end
    end
end
