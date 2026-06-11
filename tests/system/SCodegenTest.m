classdef SCodegenTest < matlab.unittest.TestCase
    % SCodegenTest  MATLAB Coder validation of embed-mode output.
    %
    % CI plan: TS-S-02, validates REQ-T-05: the inline-mode ('i') generated
    % gradient file must pass codegen, and the compiled MEX must reproduce
    % the MATLAB results exactly. A static-library build is also generated
    % to prove embedded-C viability (no MEX-only constructs).
    %
    % Skips via assumption when MATLAB Coder is not licensed/installed
    % (PR-gate runners); the nightly products job runs it.

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
            tc.assumeTrue(license('test','MATLAB_Coder') && ...
                ~isempty(which('codegen')), ...
                'TS-S-02 requires MATLAB Coder');
        end
    end

    methods (Test)
        function inlineGradientCompilesAndMatches(tc)
            % generate the pipg gap-function gradient in inline mode
            z = adigatorCreateDerivInput([2 1], 'z');
            w = adigatorCreateAuxInput([2 1]);
            opts = struct('embed_mode', 'i', 'path', pwd, 'echo', 0);
            adigatorGenDerFile_embedded('gradient', 'gapfun', {w, z}, opts);
            rehash;

            % MEX build + execution equivalence
            codegen('gapfun_Grd', '-args', {zeros(2,1), zeros(2,1)});
            rehash;
            wv = [0.5; 1.2];
            zv = [0.3; -0.7];
            [Gm, Fm] = gapfun_Grd(wv, zv);        % MATLAB
            [Gx, Fx] = gapfun_Grd_mex(wv, zv);    % compiled
            tc.verifyEqual(Gx, Gm, 'AbsTol', 1e-14, ...
                'MEX gradient differs from MATLAB');
            tc.verifyEqual(Fx, Fm, 'AbsTol', 1e-14, ...
                'MEX function value differs from MATLAB');
            tc.verifyEqual(Gm, wv + 2*zv, 'AbsTol', 1e-12, ...
                'gradient differs from analytic value');
            clear gapfun_Grd_mex % release the MEX before folder teardown

            % static-library build: embedded-C viability (generation only)
            cfg = coder.config('lib');
            cfg.GenerateReport = false;
            codegen('gapfun_Grd', '-config', cfg, ...
                '-args', {zeros(2,1), zeros(2,1)}, '-d', 'codegen_lib');
            tc.verifyTrue(isfolder('codegen_lib'), ...
                'lib codegen did not produce an output folder');
        end
    end
end
