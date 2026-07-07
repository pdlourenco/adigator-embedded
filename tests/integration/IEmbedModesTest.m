classdef IEmbedModesTest < matlab.unittest.TestCase
    % IEmbedModesTest  Cross-mode equivalence of the embedded pipeline.
    %
    % CI plan: TS-I-02, verifies REQ-T-04 (embeddability) end-to-end across
    % embed_mode 'c' (classic), 'l' (coderload), and 'i' (inline), using the
    % pipg example's gap function: it has subfunctions (conefun, setfun) and
    % an integer-valued constant matrix (eye(2)), so it exercises the data
    % pruning (B1), patching, and inline-emission paths.
    %
    % Checks:
    %  - generation succeeds in all three modes (pruning + patching included)
    %  - static text properties of the generated code per mode
    %  - numeric equality of [Grd, Fun] across modes and vs the analytic
    %    gradient w + 2z
    %
    % Note: evaluating 'l'/'i' outputs in MATLAB requires the coder.*
    % namespace (MATLAB Coder). On runners without it, the numeric
    % cross-mode check is skipped via assumption (the extended-suite Coder job per
    % docs/CI_PLAN.md runs it fully); generation and static checks always run.

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
        function gradientEquivalentAcrossModes(tc)
            baseDir = pwd;
            modes = {'c','l','i'};
            modeDir = struct();

            % --- generate in all three modes, each into its own folder --- %
            for k = 1:numel(modes)
                mode = modes{k};
                mdir = fullfile(baseDir, ['mode_', mode]);
                modeDir.(mode) = mdir;
                z = adigatorCreateDerivInput([2 1], 'z');
                w = adigatorCreateAuxInput([2 1]);
                opts = struct('embed_mode', mode, 'path', mdir, 'echo', 0);
                adigatorGenDerFile_embedded('gradient', 'gapfun', {w, z}, opts);
                tc.assertTrue(isfile(fullfile(mdir, 'gapfun_Grd.m')), ...
                    sprintf('mode %s: wrapper not generated', mode));
            end

            % ------------------- static text properties ------------------ %
            % coderload: persistent + coder.load, no global, no LoadData call
            txtL = readlines(fullfile(modeDir.l, 'gapfun_Grd.m'));
            tc.verifyTrue(any(contains(txtL, 'persistent ADiGator_')), ...
                'mode l: persistent declaration missing');
            tc.verifyTrue(any(contains(txtL, 'coder.load(')), ...
                'mode l: coder.load call missing');
            tc.verifyFalse(any(startsWith(strtrim(txtL), 'global ')), ...
                'mode l: global declaration left in generated code');
            tc.verifyFalse(any(contains(txtL, 'ADiGator_LoadData')), ...
                'mode l: runtime loader left in generated code');
            % M15 (REQ-T-04): no BARE runtime `load(` survives. contains(...,
            % 'coder.load') cannot catch a raw `load(` (it is a substring of
            % `coder.load`); a patcher regression leaving `load(` would pass every
            % static + numeric check (the 'l' .mat legitimately exists) and
            % surface only under codegen, which no test runs on 'l' files.
            tc.verifyFalse(any(~cellfun(@isempty, ...
                regexp(txtL, '(?<!coder\.)\<load\(', 'once'))), ...
                'mode l: a bare load( survives (only coder.load is permitted)');
            tc.verifyTrue(isfile(fullfile(modeDir.l, 'gapfun_ADiGatorGrd.mat')), ...
                'mode l: pruned .mat missing');

            % inline: coder.const data function, no global/load/.mat at all
            txtI = readlines(fullfile(modeDir.i, 'gapfun_Grd.m'));
            tc.verifyTrue(any(contains(txtI, 'coder.const(')), ...
                'mode i: coder.const call missing');
            tc.verifyFalse(any(startsWith(strtrim(txtI), 'global ')), ...
                'mode i: global declaration left in generated code');
            tc.verifyFalse(any(contains(txtI, 'ADiGator_LoadData')), ...
                'mode i: runtime loader left in generated code');
            tc.verifyFalse(any(contains(txtI, 'coder.load(')), ...
                'mode i: coder.load present, data should be inlined');
            matsI = dir(fullfile(modeDir.i, '*.mat'));
            tc.verifyEmpty(matsI, 'mode i: .mat file left behind');

            % ----------------------- numeric checks ---------------------- %
            wv = [0.5; 1.2];
            zv = [0.3; -0.7];
            Gexp = wv + 2*zv; % analytic: d/dz [w'(H z - g) + z'z], H = eye

            G = struct(); F = struct();
            for k = 1:numel(modes)
                mode = modes{k};
                cleanupDir = cdInto(modeDir.(mode)); %#ok<NASGU>
                clear('gapfun_Grd'); rehash;
                if strcmp(mode, 'c')
                    % force a fresh runtime load from this folder's .mat
                    clear('global', 'ADiGator_gapfun_ADiGatorGrd');
                end
                try
                    [G.(mode), F.(mode)] = gapfun_Grd(wv, zv);
                catch e
                    if strcmp(mode, 'c')
                        rethrow(e); % classic mode must always run
                    end
                    if strcmp(e.identifier, 'MATLAB:UndefinedFunction') && ...
                            contains(e.message, 'coder.')
                        tc.assumeFail(sprintf(['mode %s needs the coder.* ', ...
                            'namespace (MATLAB Coder) to run in MATLAB; ', ...
                            'skipping numeric cross-mode check: %s'], mode, e.message));
                    end
                    rethrow(e);
                end
                clear cleanupDir
            end

            for k = 1:numel(modes)
                mode = modes{k};
                tc.verifySize(G.(mode), [2 1]);
                tc.verifyEqual(G.(mode), Gexp, 'AbsTol', 1e-12, ...
                    sprintf('mode %s: gradient differs from analytic value', mode));
                tc.verifyEqual(F.(mode), gapfun(wv, zv), 'AbsTol', 1e-14, ...
                    sprintf('mode %s: function value differs', mode));
            end
            % cross-mode equality must be exact: same arithmetic, same data
            tc.verifyEqual(G.l, G.c, 'AbsTol', 0, 'coderload vs classic gradient');
            tc.verifyEqual(G.i, G.c, 'AbsTol', 0, 'inline vs classic gradient');
        end

        function inlineEmbedLeavesOnlyTheWrapper(tc)
            % Inline mode must clean up every intermediate: after a successful
            % embed the folder holds ONLY the wrapper .m - no derivative source
            % .m, no static .mat, no data_*.m temporaries. (Stricter than
            % gradientEquivalentAcrossModes, which checks the .mat alone.)
            %
            % NOTE on M8: this is a success-path completeness check, not a pin of
            % M8's reordering - the pre-M8 code also deleted the sources on
            % success (just earlier), so this passes either way. M8's guarantee
            % (a mid-embed FAILURE leaves the .m/.mat for regeneration, because
            % the deletes are deferred to after the last writelines) has no clean
            % external fault-injection seam and is verified by inspection.
            writeLocalFixture('m8_fix', 'y = x(1)^2 + x(2)*x(3);');
            idir = fullfile(pwd, 'm8_i');
            adigatorGenDerFile_embedded('gradient', 'm8_fix', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','i','path',idir,'echo',0));
            tc.assertTrue(isfile(fullfile(idir,'m8_fix_Grd.m')), ...
                'inline wrapper not generated');
            % the intermediate derivative source, its .mat, and the inline
            % data_*.m temporaries are all gone -> only the wrapper remains
            ms = dir(fullfile(idir,'*.m'));
            tc.verifyEqual({ms.name}, {'m8_fix_Grd.m'}, ...
                'M8: inline embed must leave only the wrapper .m (source deferred-deleted)');
            tc.verifyEmpty(dir(fullfile(idir,'*.mat')), ...
                'M8: static .mat left behind after inline embed');
        end

        function sparseGradientLiteralScatter(tc)
            % structurally sparse gradient: embed modes emit a literal
            % linear-index scatter in the wrapper (ANALYSIS.md §2.1)
            writeLocalFixture('sgrad_fix', 'y = x(1)^2 + sin(x(3));');
            base = pwd;
            cdir = fullfile(base, 'sc_c');
            idir = fullfile(base, 'sc_i');
            adigatorGenDerFile_embedded('gradient', 'sgrad_fix', ...
                {adigatorCreateDerivInput([4 1],'x')}, ...
                struct('embed_mode','c','path',cdir,'echo',0));
            adigatorGenDerFile_embedded('gradient', 'sgrad_fix', ...
                {adigatorCreateDerivInput([4 1],'x')}, ...
                struct('embed_mode','i','path',idir,'echo',0));

            txtI = readlines(fullfile(idir, 'sgrad_fix_Grd.m'));
            % the gradient wrapper output is named 'Grd' (C-6, #84/R25), so the
            % literal linear-index scatter line is Grd([...])
            tc.verifyTrue(any(contains(txtI, 'Grd([')), ...
                'inline wrapper does not use a literal scatter index');

            xv = [0.7; -1.3; 0.4; 2.1];
            Gexp = [2*xv(1); 0; cos(xv(3)); 0];
            c1 = cdInto(cdir); clear('sgrad_fix_Grd'); rehash; %#ok<NASGU>
            [Gc, Fc] = sgrad_fix_Grd(xv);
            clear c1
            tc.verifySize(Gc, [4 1]);
            tc.verifyEqual(Gc, Gexp, 'AbsTol', 1e-12);

            c2 = cdInto(idir); clear('sgrad_fix_Grd'); rehash; %#ok<NASGU>
            try
                [Gi, Fi] = sgrad_fix_Grd(xv);
            catch e
                if strcmp(e.identifier, 'MATLAB:UndefinedFunction') && ...
                        contains(e.message, 'coder.')
                    tc.assumeFail("inline evaluation requires MATLAB Coder: " + e.message);
                end
                rethrow(e);
            end
            clear c2
            tc.verifyEqual(Gi, Gc, 'AbsTol', 0, 'inline vs classic sparse gradient');
            tc.verifyEqual(Fi, Fc, 'AbsTol', 0);
        end

        function sparseHessianLiteralScatter(tc)
            % structurally sparse Hessian: literal scatter in the Hes wrapper
            writeLocalFixture('shess_fix', 'y = x(1)*x(2) + x(3);');
            base = pwd;
            cdir = fullfile(base, 'sh_c');
            idir = fullfile(base, 'sh_i');
            adigatorGenDerFile_embedded('hessian', 'shess_fix', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','c','path',cdir,'echo',0));
            adigatorGenDerFile_embedded('hessian', 'shess_fix', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','i','path',idir,'echo',0));

            txtI = readlines(fullfile(idir, 'shess_fix_Hes.m'));
            tc.verifyTrue(any(contains(txtI, 'Hes([')), ...
                'inline Hessian wrapper does not use a literal scatter index');

            xv = [0.7; -1.3; 0.4];
            Hexp = [0 1 0; 1 0 0; 0 0 0];
            c1 = cdInto(cdir); clear('shess_fix_Hes'); rehash; %#ok<NASGU>
            [Hc, Gc, Fc] = shess_fix_Hes(xv);
            clear c1
            tc.verifyEqual(Hc, Hexp, 'AbsTol', 1e-12);
            tc.verifyEqual(Gc, [xv(2); xv(1); 1], 'AbsTol', 1e-12);

            c2 = cdInto(idir); clear('shess_fix_Hes'); rehash; %#ok<NASGU>
            try
                [Hi, Gi, Fi] = shess_fix_Hes(xv);
            catch e
                if strcmp(e.identifier, 'MATLAB:UndefinedFunction') && ...
                        contains(e.message, 'coder.')
                    tc.assumeFail("inline evaluation requires MATLAB Coder: " + e.message);
                end
                rethrow(e);
            end
            clear c2
            tc.verifyEqual(Hi, Hc, 'AbsTol', 0, 'inline vs classic sparse Hessian');
            tc.verifyEqual(Gi, Gc, 'AbsTol', 0);
            tc.verifyEqual(Fi, Fc, 'AbsTol', 0);
        end
    end
end

function cleanupObj = cdInto(d)
old = cd(d);
cleanupObj = onCleanup(@() cd(old));
end

function writeLocalFixture(name, body)
fid = fopen([name,'.m'],'w');
assert(fid > 0, 'could not create fixture %s', name);
fprintf(fid, 'function y = %s(x)\n%s\nend\n', name, body);
fclose(fid);
rehash;
end
