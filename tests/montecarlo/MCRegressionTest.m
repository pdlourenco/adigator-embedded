classdef MCRegressionTest < matlab.unittest.TestCase
    % MCRegressionTest  Re-check promoted Monte-Carlo reproducers (ADR-0007).
    %
    % Discovers every mcreg_*.m reproducer that mcPromote wrote into
    % tests/montecarlo/regressions/ and re-runs it deterministically: the
    % structural + cross-mode oracles must pass, and any frozen closed-form
    % expectation must still match. This is the deterministic, durable half of
    % the capability — a campaign finding survives as a gated-on-merge guard.
    %
    % Until the first failure is promoted the folder is empty; the test then
    % reports a single filtered (assumption) result rather than erroring.

    properties (TestParameter)
        reproducer = listReproducers();
    end

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            mcDir = fileparts(mfilename('fullpath'));
            root  = fileparts(fileparts(mcDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
            tc.applyFixture(PathFixture(fullfile(root,'embedding')));
            tc.applyFixture(PathFixture(fullfile(root,'tests','helpers')));
            tc.applyFixture(PathFixture(mcDir));
            tc.applyFixture(PathFixture(fullfile(mcDir,'generators')));
            tc.applyFixture(PathFixture(fullfile(mcDir,'oracles')));
            tc.applyFixture(PathFixture(fullfile(mcDir,'regressions')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function reproducerStillPasses(tc, reproducer)
            if strcmp(reproducer, '__none__')
                tc.assumeFail('no promoted Monte-Carlo regressions yet');
            end

            r = feval(reproducer);
            cc = mcCase('name', r.name, 'body', r.body, 'xsize', r.xsize, ...
                'deriv', r.deriv, 'x0', r.x0);
            writeFixtureFile(cc.name, cc.body);

            rs = oracleSparsitySuperset(cc);
            tc.verifyTrue(rs.pass, sprintf('sparsity superset: %s', rs.message));

            rc = oracleCrossMode(cc);
            tc.verifyTrue(rc.pass, sprintf('cross-mode: %s', rc.message));

            if isfield(r, 'expected')
                g = mcGenClassic(cc);
                if strcmp(r.expectedKind, 'hessian')
                    out = mcEval(g.wrapper, 3, cc.x0);
                else
                    out = mcEval(g.wrapper, 2, cc.x0);
                end
                tc.verifyEqual(out{1}, r.expected, 'AbsTol', 1e-9, 'RelTol', 1e-9, ...
                    'frozen closed-form derivative no longer matches');
            end
        end
    end
end

function names = listReproducers()
% Base names of the mcreg_*.m reproducers, or a sentinel when none exist.
regDir = fullfile(fileparts(mfilename('fullpath')), 'regressions');
names = {};
if isfolder(regDir)
    d = dir(fullfile(regDir, 'mcreg_*.m'));
    names = cellfun(@(f) f(1:end-2), {d.name}, 'UniformOutput', false);
end
if isempty(names)
    names = {'__none__'};
end
end
