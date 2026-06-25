classdef SExamplesTest < matlab.unittest.TestCase
    % SExamplesTest  Run shipped examples headless with assertions.
    %
    % CI plan: TS-S-01, validates REQ-T-08 and REQ-T-01 on the examples
    % that already contain ADiGator-vs-finite-difference comparisons
    % (docs/CI_PLAN.md §2.4a). The example mains are scripts; they are run
    % inside an isolated helper workspace (some start with `clear`) and
    % their printed comparisons are promoted to assertions where the
    % script's variables allow it.
    %
    % Runs in the extended products job; base-MATLAB examples run anywhere.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
            tc.applyFixture(PathFixture(fullfile(root,'embedding')));
            tc.applyFixture(PathFixture(fullfile(root,'tests','helpers')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
            rng(0); % example mains use rand/randn
        end
    end

    methods (Test)
        function arrowheadExample(tc)
            % Jacobian of the arrowhead function: ADiGator vs numjac
            ws = runExample(tc, fullfile('examples','jacobians','arrowhead'));
            tc.assertTrue(isfield(ws,'Jac') && isfield(ws,'dfdx'), ...
                'arrowhead main did not produce Jac/dfdx');
            tc.verifyEqual(full(ws.Jac), full(ws.dfdx), ...
                'AbsTol', 1e-4, 'RelTol', 1e-4, ...
                'ADiGator Jacobian differs from finite differences');
            % sparsity structure reported to the user must cover the values
            tc.assertTrue(isfield(ws,'S'));
            tc.verifyEmpty(find(full(ws.Jac) ~= 0 & full(ws.S) == 0), ...
                'JacobianStructure misses nonzeros of the actual Jacobian');
        end

        function polydatafitExample(tc)
            % Jacobian of the polynomial data-fitting function. The
            % example's own numjac comparison (one-sided, adaptive steps)
            % is too inaccurate for the ill-conditioned m=8 fit — observed
            % per-column relative errors up to ~8% in the numjac output —
            % so assert against central differences computed here instead.
            ws = runExample(tc, fullfile('examples','jacobians','polydatafit'));
            tc.assertTrue(isfield(ws,'J') && isfield(ws,'x') && ...
                isfield(ws,'d') && isfield(ws,'m'), ...
                'polydatafit main did not produce J/x/d/m');
            h = 1e-6;
            n = numel(ws.x);
            Jc = zeros(ws.m, n);
            for j = 1:n
                e = zeros(n,1); e(j) = h;
                Jc(:,j) = (fit(ws.x+e, ws.d, ws.m) - fit(ws.x-e, ws.d, ws.m))/(2*h);
            end
            tc.verifyEqual(full(ws.J), Jc, 'AbsTol', 1e-3, 'RelTol', 5e-3, ...
                'ADiGator Jacobian differs from central finite differences');
        end

        function brusselatorExample(tc)
            % stiff ODE solved with ADiGator-, FD-, and compressed-FD-based
            % Jacobians; completing without error is the assertion (the
            % script compares solver behavior internally)
            runExample(tc, fullfile('examples','stiffodes','brusselator'));
        end

        function pipgEmbeddedExample(tc)
            % the embedded-pipeline showcase: hessian generation in
            % coderload mode + evaluation. coder.load/coder.const resolve
            % in base MATLAB on current releases (observed on the hosted
            % runners); skip only if the coder.* namespace is truly absent.
            try
                runExample(tc, fullfile('examples','optimization','pipg'));
            catch e
                if strcmp(e.identifier, 'MATLAB:UndefinedFunction') && ...
                        contains(e.message, 'coder.')
                    tc.assumeFail("pipg example needs the coder.* namespace: " + e.message);
                end
                rethrow(e);
            end
        end

        function structinputExample(tc)
            % struct inputs (issue #24): the main asserts gradient/Hessian/
            % Jacobian against closed-form references for flat and nested
            % struct inputs and a Jacobian; its inline ('i') evaluation
            % self-skips when MATLAB Coder is absent. Completing without
            % error is the assertion.
            runExample(tc, fullfile('examples','jacobians','structinput'));
        end

        function discoveryCoversEveryExample(tc)
            % Completeness guard (issue #69): the SAME mechanical discovery that
            % drives examples/runAllExamples (discoverExamples) must agree with
            % this test's bookkeeping, so a newly added examples/**/main*.m
            % cannot be silently un-run. Every discovered entry is either CURATED
            % here (a numeric-assertion method above) or explicitly acknowledged
            % as SMOKE-only (exercised by the runAllExamples sweep). The check is
            % bidirectional: no stale acknowledgment (an id that no longer
            % exists) and no un-acknowledged discovery (a new example missing
            % from both lists).
            curated = [ ...
                "jacobians/arrowhead/main"
                "jacobians/polydatafit/main"
                "jacobians/structinput/main"
                "optimization/pipg/main"
                "stiffodes/brusselator/main"];
            smokeOnly = [ ...
                "gradients/logsumexp/main"
                "hessians/logsumexp/main"
                "jachesvecprods/main"
                "jacobians/loopbound/main"
                "jacobians/ndparam/main"
                "optimization/fminconEx/main"
                "optimization/fminuncEx/main"
                "optimization/fsolveEx/main"
                "optimization/ipoptEx/gl2main"
                "optimization/vectorized/allocation/main"
                "optimization/vectorized/brachistochrone/main_basic_1stderivs"
                "optimization/vectorized/brachistochrone/main_basic_2ndderivs"
                "optimization/vectorized/brachistochrone/main_noderivs"
                "optimization/vectorized/brachistochrone/main_vect_1stderivs"
                "optimization/vectorized/brachistochrone/main_vect_2ndderivs"
                "optimization/vectorized/minimumclimb/main_1stderivs_nonvect"
                "optimization/vectorized/minimumclimb/main_1stderivs_vect"
                "optimization/vectorized/minimumclimb/main_2ndderivs_nonvect"
                "optimization/vectorized/minimumclimb/main_2ndderivs_vect"
                "stiffodes/DCALcontrol/main"
                "stiffodes/burgers/main"];
            ack = [curated; smokeOnly];
            ids = string({discoverExamples().id}).';

            for a = ack.'
                tc.verifyTrue(any(ids == a), ...
                    "acknowledged example no longer discovered (rename/removal?): " + a);
            end
            for d = ids.'
                tc.verifyTrue(any(ack == d), ...
                    "discovered example is neither curated nor smoke-acknowledged " + ...
                    "in SExamplesTest - add it to one list: " + d);
            end
        end
    end
end

% ======================== helpers ======================== %

function ws = runExample(tc, relDir)
% Run <repo>/<relDir>/main.m in an isolated workspace with the example
% folder on the path, returning the script workspace as a struct.
testDir = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(testDir));
exDir = fullfile(root, relDir);
tc.assertTrue(isfolder(exDir), "missing example folder: " + exDir);
tc.applyFixture(matlab.unittest.fixtures.PathFixture(exDir));
ws = runScriptIsolated(fullfile(exDir, 'main.m'));
end

function ws = runScriptIsolated(adigator_script_path__)
% Scripts may `clear` and define arbitrary variables: give them their own
% function workspace and harvest it afterwards.
run(adigator_script_path__);
vars__ = setdiff(who, {'adigator_script_path__','vars__'});
ws = struct();
for k__ = 1:numel(vars__)
    ws.(vars__{k__}) = eval(vars__{k__});
end
close all force; % examples may open figures
end
