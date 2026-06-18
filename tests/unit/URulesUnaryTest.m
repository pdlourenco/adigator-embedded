classdef URulesUnaryTest < matlab.unittest.TestCase
    % URulesUnaryTest  Finite-difference check of every unary derivative rule.
    %
    % CI plan: TS-U-01, verifies REQ-C-01. This is a matlab.unittest port of
    % unit_tests/test_unarymath_rules.m (same test points, perturbation,
    % tolerance, and singularity-skip rules), parameterized so each rule in
    % lib/@cada/cadaunarymath.m>getdydx reports individually.

    properties (TestParameter)
        rulename
    end

    methods (TestParameterDefinition, Static)
        function rulename = listRules()
            thisDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(thisDir));
            txt = fileread(fullfile(root,'lib','@cada','cadaunarymath.m'));
            % restrict to the getdydx rule table
            k = strfind(txt, 'function dydx = getdydx');
            assert(~isempty(k), 'getdydx subfunction not found in cadaunarymath.m');
            txt = txt(k(1):end);
            tok = regexp(txt, 'case\s+''(\w+)''', 'tokens');
            rulename = cellfun(@(c) c{1}, tok, 'UniformOutput', false);
            assert(~isempty(rulename), 'no derivative rules found to test');
        end
    end

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function ruleMatchesFiniteDifference(tc, rulename)
            % generate a one-line user function y = <rule>(x)
            fname = ['adigator_ut_', rulename];
            fid = fopen([fname,'.m'], 'w');
            tc.assertGreaterThan(fid, 0);
            fprintf(fid, 'function y = %s(x)\ny = %s(x);\nend\n', fname, rulename);
            fclose(fid);
            rehash;

            % differentiate it
            dname = [fname, '_dx'];
            ax = adigatorCreateDerivInput([1 1], 'x');
            adigator(fname, {ax}, dname, adigatorOptions('overwrite',1,'echo',0));
            rehash;

            % same points, perturbation, tolerance, and skip rules as the
            % original unit_tests/test_unarymath_rules.m
            xtest = [linspace(-0.9,0.9,10), linspace(-2*pi,2*pi,10), linspace(-360,360,10)];
            ee = 1e-6;
            bad = strings(1,0);
            for x0 = xtest
                xx.f = x0; xx.dx = 1;
                yy = feval(dname, xx);
                f1 = feval(fname, x0);
                f2 = feval(fname, x0 + ee);
                df = (f2 - f1)/ee;
                if abs(yy.dx - df)/(1 + abs(df)) > 1e-4
                    if ~(isnan(f1) || isinf(f1) || abs(df) > 1e8)
                        % (corner cases near singularities are skipped: there
                        % the finite difference is as wrong as anything)
                        bad(end+1) = sprintf('x=%.6g: AD=%.6g FD=%.6g', ...
                            x0, real(yy.dx), real(df)); %#ok<AGROW>
                    end
                end
            end
            tc.verifyEmpty(bad, sprintf('%s: %d finite-difference violation(s): %s', ...
                rulename, numel(bad), strjoin(bad, ' | ')));
        end
    end
end
