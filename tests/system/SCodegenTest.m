classdef SCodegenTest < matlab.unittest.TestCase
    % SCodegenTest  MATLAB Coder validation of embed-mode output.
    %
    % CI plan: TS-S-02, validates REQ-T-05: the inline-mode ('i') generated
    % gradient file must pass codegen, and the compiled MEX must reproduce
    % the MATLAB results exactly (REQ-T-05, MATLAB Coder). Where Embedded Coder is
    % licensed, an Embedded Coder (ERT) static-library build is also generated to
    % prove embedded-C viability under the strict target (#80 R20b, REQ-T-10 -
    % plain Coder was masking ERT-only gaps). Run for both the
    % full embedded data and the slim_embed=true slice-before-prune shrunk data
    % (issue #21), to prove the dropped Index7 leaves the compiled result
    % unchanged.
    %
    % Skips via assumption when MATLAB Coder is not licensed/installed (PR-gate
    % runners). The ERT lib build is separately guarded on Embedded Coder, so a
    % Coder-only runner still checks the MEX equivalence; the extended products
    % job (Coder + Embedded Coder) exercises both.

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
            % Coder is the floor: the MEX runtime-equivalence check (REQ-T-05)
            % needs only MATLAB Coder. The ERT static-lib build (REQ-T-10) is
            % separately guarded on Embedded Coder below, so a Coder-only runner
            % still verifies the equivalence at its true license floor.
            tc.assumeTrue(license('test','MATLAB_Coder') && ...
                ~isempty(which('codegen')), ...
                'TS-S-02 requires MATLAB Coder');
        end
    end

    methods (Test)
        function inlineGradientCompilesAndMatches(tc)
            % Default inline path (no slim_embed): the full, unshrunk embedded
            % data must compile and stay numerically exact.
            tc.genCompileAndCheck(false);
        end

        function inlineSlimGradientCompilesAndMatches(tc)
            % slim_embed=true (issue #21, ADR-0006/0010): slice-before-prune
            % drops the dead Index7 (and the dz_size/dz_location statements)
            % from the embedded gradient. The compiled MEX must still match
            % MATLAB and the analytic value - the shrink removes only
            % unreferenced constants, so the result is unchanged. This is the
            % end-to-end Coder round-trip on the shrunk data.
            tc.genCompileAndCheck(true);
        end
    end

    methods (Access = private)
        function genCompileAndCheck(tc, slim)
            % Generate the pipg gap-function gradient in inline mode, build a
            % MEX and a static lib, and assert MEX == MATLAB == analytic. SLIM
            % toggles slim_embed (shrunk vs. full embedded data); the numeric
            % checks are identical either way.
            z = adigatorCreateDerivInput([2 1], 'z');
            w = adigatorCreateAuxInput([2 1]);
            % slim is explicit (false = full unshrunk data, true = slice-before-
            % prune). The embedded generator now defaults slim_embed ON (ADR-0012), so the false case must opt out for the unshrunk-data point to
            % be exercised.
            opts = struct('embed_mode', 'i', 'path', pwd, 'echo', 0, 'slim_embed', slim);
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

            % static-library build through Embedded Coder (ERT): embedded-C
            % viability under the strict target (#80 R20b, REQ-T-10). Guarded on
            % the Embedded Coder license so a Coder-only runner still checks the
            % MEX equivalence above (REQ-T-05) - only the ERT lib build needs it.
            if license('test', 'RTW_Embedded_Coder')
                cfg = coder.config('lib', 'ecoder', true);
                cfg.GenerateReport = false;
                codegen('gapfun_Grd', '-config', cfg, ...
                    '-args', {zeros(2,1), zeros(2,1)}, '-d', 'codegen_lib');
                tc.verifyTrue(isfolder('codegen_lib'), ...
                    'lib codegen did not produce an output folder');
            end
        end
    end
end
