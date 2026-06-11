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
    % Runs in the nightly products job; base-MATLAB examples run anywhere.

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
            % Jacobian of the polynomial data-fitting function vs numjac
            ws = runExample(tc, fullfile('examples','jacobians','polydatafit'));
            tc.assertTrue(isfield(ws,'J') && isfield(ws,'dpdx2'), ...
                'polydatafit main did not produce J/dpdx2');
            tc.verifyEqual(full(ws.J), full(ws.dpdx2), ...
                'AbsTol', 1e-3, 'RelTol', 1e-3, ...
                'ADiGator Jacobian differs from finite differences');
        end

        function brusselatorExample(tc)
            % stiff ODE solved with ADiGator-, FD-, and compressed-FD-based
            % Jacobians; completing without error is the assertion (the
            % script compares solver behavior internally)
            runExample(tc, fullfile('examples','stiffodes','brusselator'));
        end

        function pipgEmbeddedExample(tc)
            % the embedded-pipeline showcase: hessian generation in
            % coderload mode + evaluation. Evaluation needs the coder.*
            % namespace (MATLAB Coder).
            tc.assumeTrue(license('test','MATLAB_Coder') && ...
                ~isempty(which('codegen')), ...
                'pipg example evaluation requires MATLAB Coder (coder.load)');
            runExample(tc, fullfile('examples','optimization','pipg'));
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
