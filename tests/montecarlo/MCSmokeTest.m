classdef MCSmokeTest < matlab.unittest.TestCase
    % MCSmokeTest  Fixed-seed Monte-Carlo smoke (CI_PLAN.md TS-S-04, ADR-0007).
    %
    % Runs a small, deterministic (fixed-seed, fixed-iteration) slice of the
    % campaign so a regression in the tolerance-free invariants is caught
    % per-merge. This class lives under tests/montecarlo/ on purpose: neither
    % the PR gate (ci.yml: tests/unit + tests/integration) nor the local
    % ci_local folder sweep (tests/{unit,integration,system}) selects it, so
    % the random-seed harness never gates a PR. The extended workflow selects
    % tests/montecarlo explicitly to run it.
    %
    % The smoke draws from the known-derivative generators (affine, quadratic)
    % whose exact derivatives make the value check tolerance-free and whose
    % generation paths are rock-solid; shapefuzz and the unbounded campaign are
    % exercised via mcCampaign / the harness unit test, not gated here.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            mcDir = fileparts(mfilename('fullpath'));      % tests/montecarlo
            root  = fileparts(fileparts(mcDir));           % repo root
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
            tc.applyFixture(PathFixture(fullfile(root,'embedding')));
            tc.applyFixture(PathFixture(fullfile(root,'tests','helpers')));
            tc.applyFixture(PathFixture(mcDir));
            tc.applyFixture(PathFixture(fullfile(mcDir,'generators')));
            tc.applyFixture(PathFixture(fullfile(mcDir,'oracles')));
        end
    end

    methods (Test)
        function knownDerivativeCampaignIsClean(tc)
            % Deterministic campaign over the exact-derivative generators.
            report = mcCampaign('nIters', 24, 'seed', 90210, ...
                'generators', {'mcGenAffine','mcGenQuadratic'}, ...
                'promote', false, 'verbose', false);

            tc.verifyEqual(report.nFail, 0, ...
                sprintf('Monte-Carlo smoke found %d failing case(s); see report.failures', ...
                report.nFail));

            % sanity: the value oracle actually ran (not all skipped)
            ks = report.oracleStats.oracleKnownDeriv;
            tc.verifyGreaterThan(ks.pass, 0, ...
                'knownDeriv oracle never produced a pass — harness likely not exercising generation');
            tc.verifyEqual(ks.fail, 0, 'knownDeriv oracle reported a hard failure');

            % cross-mode static invariants must hold even without Coder
            cm = report.oracleStats.oracleCrossMode;
            tc.verifyEqual(cm.fail, 0, 'crossMode oracle reported a hard failure');
        end

        function elementwiseCampaignIsClean(tc)
            % Rule-table generator: y = g(a.*x+b) with the exact diagonal
            % Jacobian. Exercises cadaunarymath rules (REQ-C-01) under
            % randomization; the unary rules are well-trodden (URulesUnaryTest),
            % so this is safe for a per-merge smoke.
            report = mcCampaign('nIters', 16, 'seed', 24601, ...
                'generators', {'mcGenElementwise'}, ...
                'oracles', {'oracleKnownDeriv','oracleSparsitySuperset','oracleCrossMode'}, ...
                'promote', false, 'verbose', false);

            tc.verifyEqual(report.nFail, 0, ...
                sprintf('elementwise smoke found %d failing case(s)', report.nFail));
            ks = report.oracleStats.oracleKnownDeriv;
            tc.verifyGreaterThan(ks.pass, 0, 'knownDeriv never passed on elementwise cases');
            tc.verifyEqual(ks.fail, 0, 'knownDeriv reported a hard failure');
            tc.verifyEqual(report.oracleStats.oracleSparsitySuperset.fail, 0, ...
                'sparsity superset failed on a diagonal Jacobian');
        end
    end
end
