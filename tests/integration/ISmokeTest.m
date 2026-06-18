classdef ISmokeTest < matlab.unittest.TestCase
    % ISmokeTest  CI Phase-0 end-to-end smoke test.
    %
    % Generates the gradient of the pipg example's gap function through the
    % full embedded pipeline (classic mode) and checks the result against
    % the analytic gradient and finite differences.
    %
    % gapfun(w,z) = w'*(H*z - g) + z'*z with H = eye(2), so
    %   dgapfun/dz = H'*w + 2*z = w + 2*z   (smooth everywhere).
    %
    % Covers (smoke level): REQ-T-01, REQ-T-02 (gradient is a column),
    % REQ-T-06 (artifacts land in the working folder).

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
            tc.applyFixture(PathFixture(fullfile(root,'examples','optimization','pipg')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function gapfunGradientClassicMode(tc)
            z = adigatorCreateDerivInput([2 1], 'z');
            w = adigatorCreateAuxInput([2 1]);
            opts.embed_mode = 'c';
            opts.echo = 0;

            adigatorGenDerFile_embedded('gradient', 'gapfun', {w, z}, opts);
            rehash;
            tc.assertTrue(isfile(fullfile(pwd, 'gapfun_Grd.m')), ...
                'gradient wrapper not generated in the working folder');

            wv = [0.5; 1.2];
            zv = [0.3; -0.7];
            [G, F] = gapfun_Grd(wv, zv);

            % function value passes through unchanged
            tc.verifyEqual(F, gapfun(wv, zv), 'AbsTol', 1e-14);

            % gradient convention: column vector (REQ-T-02)
            tc.verifySize(G, [2 1]);

            % analytic gradient: w + 2z (H = eye(2))
            tc.verifyEqual(G, wv + 2*zv, 'AbsTol', 1e-12, ...
                'gradient does not match analytic value');

            % central finite differences
            ee = 1e-6;
            Gfd = zeros(2,1);
            for i = 1:2
                e_i = zeros(2,1); e_i(i) = ee;
                Gfd(i) = (gapfun(wv, zv + e_i) - gapfun(wv, zv - e_i))/(2*ee);
            end
            tc.verifyEqual(G, Gfd, 'AbsTol', 1e-6, ...
                'gradient does not match finite differences');
        end
    end
end
