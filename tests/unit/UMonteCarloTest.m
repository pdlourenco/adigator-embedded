classdef UMonteCarloTest < matlab.unittest.TestCase
    % UMonteCarloTest  Unit coverage of the Monte-Carlo harness logic (issue
    % #38, ADR-0007). Exercises the parts that need no derivative generation —
    % the case contract, the generators' well-formedness, and the promote
    % serialization round-trip — so they are gated by the PR pipeline
    % (tests/unit). The generation-driven oracles, shrinker and full campaign
    % run in the extended suite via MCSmokeTest (tests/montecarlo).

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));     % tests/unit
            root = fileparts(fileparts(testDir));
            mcDir = fullfile(root,'tests','montecarlo');
            tc.applyFixture(PathFixture(mcDir));
            tc.applyFixture(PathFixture(fullfile(mcDir,'generators')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function caseBuildsAndValidates(tc)
            c = mcCase('name','foo','body','y = x;','xsize',[3 1], ...
                'deriv','jacobian','x0',[1;2;3]);
            tc.verifyEqual(c.name,'foo');
            tc.verifyEqual(c.deriv,'jacobian');
            tc.verifyEqual(c.xsize,[3 1]);
            tc.verifyTrue(iscellstr(c.body));
        end

        function caseRejectsBadInput(tc)
            tc.verifyError(@() mcCase('name','1bad','body','y=x;', ...
                'xsize',[2 1],'deriv','jacobian','x0',[1;2]), 'mcCase:name');
            tc.verifyError(@() mcCase('name','f','body','y=x;', ...
                'xsize',[2 1],'deriv','curl','x0',[1;2]), 'mcCase:deriv');
            tc.verifyError(@() mcCase('name','f','body','y=x;', ...
                'xsize',[2 1],'deriv','jacobian','x0',[1 2 3]), 'mcCase:x0');
        end

        function affineGeneratorWellFormed(tc)
            rng(1);
            c = mcGenAffine(7);
            tc.verifySize(c.x0, c.xsize);
            tc.verifyEqual(c.deriv,'jacobian');
            n = c.xsize(1); m = c.tags.outShape(1);
            tc.verifySize(c.exactJac(c.x0), [m n]);   % constant Jacobian A
            tc.verifyMatches(c.name, '^mc_affine_7$');
        end

        function quadraticGeneratorWellFormed(tc)
            rng(2);
            c = mcGenQuadratic(3);
            n = c.xsize(1);
            tc.verifyEqual(c.deriv,'hessian');
            H = c.exactHess(c.x0);
            tc.verifySize(H, [n n]);
            tc.verifyEqual(H, H.', 'AbsTol', 0, 'Hessian must be symmetric by construction');
            tc.verifySize(c.exactJac(c.x0), [n 1]);   % gradient
        end

        function shapeFuzzGeneratorWellFormed(tc)
            rng(3);
            c = mcGenShapeFuzz(5);
            tc.verifySize(c.x0, c.xsize);
            tc.verifyEqual(c.deriv,'jacobian');
            tc.verifyEmpty(c.exactJac);               % FD-checked, no closed form
            tc.verifyTrue(iscellstr(c.body) && isscalar(c.body));
            tc.verifyMatches(strtrim(c.body{1}), '^y = \[.*\];$');
        end

        function promoteRoundTrips(tc)
            c = mcCase('name','rt','body',{'y = [4 0; 0 9]*x;'}, ...
                'xsize',[2 1],'deriv','jacobian','x0',[0.5; -0.25], ...
                'exactJac', @(x) [4 0; 0 9]);
            results = struct('name',{'oracleKnownDeriv'}, 'pass',{false}, ...
                'skipped',{false}, 'message',{'planted'});
            fpath = mcPromote(c, 999, results, pwd);
            tc.assertTrue(isfile(fpath));

            [~, base] = fileparts(fpath);
            rehash;
            r = feval(base);
            tc.verifyEqual(r.name, 'rt');
            tc.verifyEqual(r.deriv, 'jacobian');
            tc.verifyEqual(r.xsize, [2 1]);
            tc.verifyEqual(r.x0, [0.5; -0.25], 'AbsTol', 0);
            tc.verifyEqual(r.seed, 999);
            tc.verifyEqual(r.expected, [4 0; 0 9], 'AbsTol', 0);
            tc.verifyEqual(r.expectedKind, 'jacobian');
        end

        function elementwiseGeneratorWellFormed(tc)
            rng(4);
            c = mcGenElementwise(9);
            n = c.xsize(1);
            tc.verifyEqual(c.deriv, 'jacobian');
            J = c.exactJac(c.x0);
            tc.verifySize(J, [n n]);
            tc.verifyEqual(J, diag(diag(J)), 'AbsTol', 0, 'Jacobian must be diagonal');
            tc.verifyTrue(iscellstr(c.body) && numel(c.body) == 2);
            tc.verifyMatches(strtrim(c.body{end}), '^y = \w+\(t\);$');
        end

        function coverageCountsDistinctTuples(tc)
            t1 = struct('gen','affine','order',1,'density','dense','inShape',[3 1],'outShape',[2 1]);
            t2 = t1;                                   % same tuple
            t3 = struct('gen','quadratic','order',2,'density','dense','inShape',[4 1],'outShape',[1 1]);
            cov = mcCoverage({t1, t2, t3});
            tc.verifyEqual(cov.total, 3);
            tc.verifyEqual(cov.nDistinct, 2);          % t1==t2 collapse, t3 distinct
            tc.verifyEqual(sum(cov.counts), 3);

            cov0 = mcCoverage({});
            tc.verifyEqual(cov0.nDistinct, 0);
            tc.verifyEqual(cov0.total, 0);
        end

        function scalarSumGeneratorWellFormed(tc)
            rng(6);
            c = mcGenScalarSum(11);
            n = c.xsize(1);
            tc.verifyEqual(c.deriv, 'gradient');
            tc.verifyTrue(c.tags.scalarCost);
            tc.verifyEqual(c.tags.outShape, [1 1]);
            tc.verifySize(c.exactJac(c.x0), [n 1]);          % gradient
            tc.verifyMatches(strtrim(c.body{end}), '^y = sum\(\w+\(t\)\);$');
        end
    end
end
