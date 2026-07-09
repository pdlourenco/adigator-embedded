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
                'oracles', {'oracleKnownDeriv','oracleSparsitySuperset', ...
                            'oracleCrossMode','oracleHessSymmetry'}, ...
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

        function reverseGradientCampaignIsClean(tc)
            % Scalar reduction costs checked by oracleFwdRev: reverse-mode
            % gradient (adigatorGenRevGradFile) must equal the forward 'Grd'
            % wrapper and the closed form.
            report = mcCampaign('nIters', 12, 'seed', 31415, ...
                'generators', {'mcGenScalarSum'}, ...
                'oracles', {'oracleKnownDeriv','oracleFwdRev','oracleSparsitySuperset'}, ...
                'promote', false, 'verbose', false);

            tc.verifyEqual(report.nFail, 0, ...
                sprintf('reverse-gradient smoke found %d failing case(s)', report.nFail));
            fr = report.oracleStats.oracleFwdRev;
            tc.verifyGreaterThan(fr.pass, 0, 'fwdRev never ran (reverse-mode path untested)');
            tc.verifyEqual(fr.fail, 0, 'fwdRev reported a hard failure');
        end

        function finiteDiffValueOracleIsClean(tc)
            % #145 (ADR-0007 R9 Phase C): the FD secondary value oracle closes
            % the gap where a closed-form-free shape-fuzz case got NO value check
            % (knownDeriv skips; the rest are structural). Run the shape-fuzz
            % generator -- which emits exactJac=[] cases -- with oracleFiniteDiff
            % and assert it actually value-checked them (pass > 0, so the guard
            % is non-vacuous) and found no wrong values.
            report = mcCampaign('nIters', 16, 'seed', 161803, ...
                'generators', {'mcGenShapeFuzz'}, ...
                'oracles', {'oracleFiniteDiff','oracleKnownDeriv','oracleCrossMode'}, ...
                'promote', false, 'verbose', false);

            tc.verifyEqual(report.nFail, 0, ...
                sprintf('finiteDiff smoke found %d failing case(s); see report.failures', ...
                report.nFail));
            fd = report.oracleStats.oracleFiniteDiff;
            tc.verifyGreaterThan(fd.pass, 0, ...
                'finiteDiff never value-checked a case — the shape-fuzz value gap is still open');
            tc.verifyEqual(fd.fail, 0, 'finiteDiff reported a wrong-value case');
            % on these closed-form-free cases knownDeriv must be the one skipping
            tc.verifyGreaterThan(report.oracleStats.oracleKnownDeriv.skip, 0, ...
                'knownDeriv should skip the shape-fuzz cases (no closed form) — FD is why they are now checked');
        end

        function negativeHygieneIsClean(tc)
            % Malformed fixtures must fail generation cleanly and leave the
            % session hygienic — no stray transformation globals, path
            % restored, no open file handles (REQ-T-07 / B16), checked by
            % oracleHygiene. Pins the adigator.m onCleanup error-path release.
            report = mcCampaign('nIters', 9, 'seed', 27182, ...
                'generators', {'mcGenNegative'}, ...
                'oracles', {'oracleHygiene'}, ...
                'promote', false, 'verbose', false);

            tc.verifyEqual(report.nFail, 0, ...
                sprintf('hygiene smoke found %d failing case(s); see report.failures', report.nFail));
            hg = report.oracleStats.oracleHygiene;
            tc.verifyGreaterThan(hg.pass, 0, 'hygiene oracle never ran');
            tc.verifyEqual(hg.fail, 0, 'a malformed function did not error cleanly / leaked state');
        end

        function successLeavesNoOpenHandles(tc)
            % SUCCESS-path hygiene (REQ-T-07 / B16): a successful transformation
            % must close every handle it opened (source files, temp files, the
            % generated file) and leave no transformation-state globals. The
            % negative hygiene cases fail at the initial eval, before the source
            % handles open, so they cannot pin this — hence a positive campaign.
            fids0 = openFidsPortable();
            report = mcCampaign('nIters', 8, 'seed', 13579, ...
                'generators', {'mcGenAffine','mcGenScalarSum'}, ...
                'oracles', {'oracleKnownDeriv'}, ...
                'promote', false, 'verbose', false);
            tc.verifyEqual(report.nFail, 0, 'success-hygiene campaign had failures');

            tc.verifyEmpty(setdiff(openFidsPortable(), fids0), ...
                'a successful transformation left file handle(s) open (REQ-T-07)');
            tc.verifyEmpty(intersect(who('global'), ...
                {'ADIGATOR','ADIGATORFORDATA','ADIGATORDATA','ADIGATORVARIABLESTORAGE'}), ...
                'transformation-state globals leaked after successful generation');
        end

        function paramDeliveryInvarianceIsClean(tc)
            % R27 Phase 1 (issue #103): the same bilinear function with its
            % parameters delivered several ways -- inline constant struct (the
            % B17 shape), aux struct (R8), separate aux inputs, inline constant
            % cell (the B22 shape) -- must generate, run, and yield the identical
            % Jacobian. This is the tolerance-free backstop for the B17/B22
            % silent-broken-codegen class the body-only generators never reach.
            report = mcCampaign('nIters', 12, 'seed', 271828, ...
                'generators', {'mcGenParamDelivery'}, ...
                'oracles', {'oracleParamDeliveryInvariance'}, ...
                'promote', false, 'verbose', false);

            tc.verifyEqual(report.nFail, 0, ...
                sprintf('paramDelivery invariance found %d failing case(s); see report.failures', ...
                report.nFail));
            pd = report.oracleStats.oracleParamDeliveryInvariance;
            tc.verifyGreaterThan(pd.pass, 0, ...
                'paramDelivery oracle never passed — harness not exercising the deliveries');
            tc.verifyEqual(pd.fail, 0, 'paramDelivery oracle reported a hard failure');
        end

        function derOutputInvarianceIsClean(tc)
            % R27 Phase 2 (issue #103): the der_output option axis. For a
            % jacobian case, the jac_output='nonzeros' form must reconstruct
            % (scatter into JacobianLocs) to the exact dense matrix form -- an
            % option the body-only battery never swept.
            report = mcCampaign('nIters', 16, 'seed', 141421, ...
                'generators', {'mcGenAffine','mcGenQuadratic'}, ...
                'oracles', {'oracleDerOutputInvariance'}, ...
                'promote', false, 'verbose', false);

            tc.verifyEqual(report.nFail, 0, ...
                sprintf('derOutput invariance found %d failing case(s)', report.nFail));
            do = report.oracleStats.oracleDerOutputInvariance;
            tc.verifyGreaterThan(do.pass, 0, ...
                'derOutput oracle never passed — harness not exercising the matrix/nonzeros forms');
            tc.verifyEqual(do.fail, 0, 'derOutput oracle reported a hard failure');
        end

        function codegenEquivalenceIsClean(tc)
            % R15 (#64, ADR-0014): the codegen-equivalence oracle — compiled-C ==
            % MATLAB over randomized cases, born ERT. This is the compiled-side
            % proof the cross-mode oracle can't give (it compares embed modes
            % interpreter-only). Skip-clean without MATLAB Coder (PR-gate / floor
            % runners filter it); with Coder each case's inline wrapper is built
            % through Embedded Coder (proving strict-target codegen) plus a MEX,
            % and the compiled result is checked against MATLAB. EXPENSIVE
            % (codegen per case) — a tiny deterministic set here (a jacobian and a
            % Hessian case); the full sampled sweep is a release-checklist
            % mcCampaign that includes oracleCodegenEquivalence.
            tc.assumeTrue(license('test','MATLAB_Coder') && ~isempty(which('codegen')), ...
                'codegen-equivalence oracle requires MATLAB Coder (extended/nightly only)');
            report = mcCampaign('nIters', 2, 'seed', 424242, ...
                'generators', {'mcGenAffine','mcGenQuadratic'}, ...
                'oracles', {'oracleCodegenEquivalence'}, ...
                'promote', false, 'verbose', false);

            tc.verifyEqual(report.nFail, 0, ...
                sprintf('codegen-equivalence found %d failing case(s); see report.failures', ...
                report.nFail));
            ce = report.oracleStats.oracleCodegenEquivalence;
            tc.verifyGreaterThan(ce.pass, 0, ...
                'codegen-equivalence never passed — compiled==MATLAB not actually exercised');
            tc.verifyEqual(ce.fail, 0, ...
                'codegen-equivalence reported a compiled != MATLAB case');
        end
    end
end

function fids = openFidsPortable()
% Portable open-file-identifier list: fopen('all') is being removed (errors on
% recent MATLAB); openedFiles is the replacement but is absent on R2022a..
if exist('openedFiles','builtin') == 5 || exist('openedFiles','file') == 2
    fids = openedFiles();
else
    fids = fopen('all');
end
end
