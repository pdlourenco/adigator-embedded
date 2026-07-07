classdef IRevEmbedTest < matlab.unittest.TestCase
    % IRevEmbedTest  Reverse-gradient embed-pipeline parity (roadmap R16b,
    % issue #73 item A). The 'gradient-reverse' DerType routes
    % adigatorGenRevGradFile's self-contained <fn>_RGrd.m (main == m) through the
    % same prune -> patch -> coderload/inline stages as the forward generators,
    % so a reverse gradient is a first-class embeddable, codegen-able mode.
    %
    % Mirrors IEmbedModesTest (TS-I-02) for the reverse path: generate one cost
    % through embed_mode 'c'/'l'/'i' and assert the C-4 embed invariants and
    % numeric equality of [Grd, Fun] across modes and vs the analytic gradient.
    %
    % Two regimes:
    %  - INDEXED: the adjoint references constant index tables, so the file
    %    carries data ('c' classic+.mat, 'l' coder.load+.mat, 'i' inlined).
    %  - DENSE: the adjoint is fully vectorized, so the file carries NO static
    %    data in ANY mode (no global/load/.mat) - the zero-ROM reverse gradient
    %    of ANALYSIS §3.5 (R16b: the generator omits the data boilerplate).
    %
    % 'l'/'i' evaluation in MATLAB needs the coder.* namespace; on runners
    % without MATLAB Coder the numeric cross-mode check is skipped via assumption
    % (generation + static checks always run), as in IEmbedModesTest.

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
        end
    end

    methods (Test)
        function indexedReverseGradientEquivalentAcrossModes(tc)
            % An adjoint that references index tables -> the file carries data.
            n = 5; xv = 0.3 + (1:n)'/10;
            ga = zeros(n,1); ga(1) = xv(2);
            for i = 2:n-1; ga(i) = xv(i-1)+xv(i+1); end
            ga(n) = xv(n-1);                       % d/dx sum(x_i x_{i+1})
            md = generateAllModes(tc, 'ridx', 'y = sum(x(1:end-1).*x(2:end));', n);

            % static invariants (C-4)
            txtL = readlines(fullfile(md.l,'ridx_RGrd.m'));
            tc.verifyTrue(any(contains(txtL,'persistent ADiGator_')),'l: persistent missing');
            tc.verifyTrue(any(contains(txtL,'coder.load(')),'l: coder.load missing');
            % M15 (REQ-T-04): no bare load( survives - contains('coder.load')
            % cannot catch a raw load( (substring of coder.load).
            tc.verifyFalse(any(~cellfun(@isempty, regexp(txtL,'(?<!coder\.)\<load\(','once'))), ...
                'l: a bare load( survives (only coder.load is permitted)');
            tc.verifyFalse(any(startsWith(strtrim(txtL),'global ')),'l: global left in');
            tc.verifyTrue(isfile(fullfile(md.l,'ridx_RGrd.mat')),'l: pruned .mat missing');
            txtI = readlines(fullfile(md.i,'ridx_RGrd.m'));
            tc.verifyTrue(any(contains(txtI,'coder.const(')),'i: coder.const missing');
            tc.verifyFalse(any(startsWith(strtrim(txtI),'global ')),'i: global left in');
            tc.verifyEmpty(dir(fullfile(md.i,'*.mat')),'i: .mat left behind');

            verifyNumericAcrossModes(tc, md, 'ridx_RGrd', xv, ga);
        end

        function denseReverseGradientHasZeroStaticData(tc)
            % A fully-vectorized adjoint -> NO static data in any mode (ANALYSIS
            % §3.5): no global, no coder.load, no .mat anywhere.
            n = 5; xv = 0.3 + (1:n)'/10;
            ga = exp(xv) + 2;                      % d/dx sum(exp(x)+2x)
            md = generateAllModes(tc, 'rden', 'y = sum(exp(x) + 2*x);', n);

            for mode = {'c','l','i'}
                m = mode{1};
                txt = readlines(fullfile(md.(m),'rden_RGrd.m'));
                tc.verifyFalse(any(startsWith(strtrim(txt),'global ')), ...
                    sprintf('%s: dense reverse gradient must carry no global',m));
                tc.verifyFalse(any(contains(txt,'coder.load(')), ...
                    sprintf('%s: dense reverse gradient must carry no coder.load',m));
                tc.verifyFalse(any(contains(txt,'ADiGator_LoadData')), ...
                    sprintf('%s: dense reverse gradient must carry no loader',m));
                tc.verifyEmpty(dir(fullfile(md.(m),'*.mat')), ...
                    sprintf('%s: dense reverse gradient must write no .mat',m));
            end
            % 'l'/'i' add only %#codegen
            tc.verifyTrue(any(contains(readlines(fullfile(md.i,'rden_RGrd.m')),'%#codegen')), ...
                'i: %#codegen missing');

            verifyNumericAcrossModes(tc, md, 'rden_RGrd', xv, ga);
        end
    end
end

% ---- local helpers -------------------------------------------------------- %

function md = generateAllModes(tc, fname, body, n)
% Write <fname>.m and generate its reverse gradient in c/l/i, each into its own
% folder. Returns a struct of per-mode directories.
fid = fopen([fname '.m'],'w');
fprintf(fid,'function y = %s(x)\n%s\nend\n',fname,body);
fclose(fid); rehash;
base = pwd; md = struct();
for mode = {'c','l','i'}
    m = mode{1};
    mdir = fullfile(base,['mode_',m]); md.(m) = mdir;
    opts = struct('embed_mode',m,'path',mdir,'echo',0);
    adigatorGenDerFile_embedded('gradient-reverse', fname, ...
        {adigatorCreateDerivInput([n 1],'x')}, opts);
    tc.assertTrue(isfile(fullfile(mdir,[fname '_RGrd.m'])), ...
        sprintf('mode %s: %s_RGrd.m not generated', m, fname));
end
end

function verifyNumericAcrossModes(tc, md, wrapper, xv, ga)
% Evaluate <wrapper>(xv) in each mode (cd into its folder), compare [Grd, Fun]
% to the analytic gradient and across modes. l/i need MATLAB Coder; skip-clean.
base = pwd; G = struct(); F = struct();
for mode = {'c','l','i'}
    m = mode{1};
    c = onCleanup(@() cd(base)); cd(md.(m));
    clear(wrapper); clear('global',['ADiGator_',wrapper]); rehash;
    try
        [G.(m),F.(m)] = feval(wrapper, xv);
    catch e
        if strcmp(m,'c'); rethrow(e); end
        if strcmp(e.identifier,'MATLAB:UndefinedFunction') && contains(e.message,'coder.')
            tc.assumeFail(sprintf(['mode %s needs the coder.* namespace ',...
                '(MATLAB Coder) to run in MATLAB; skipping numeric check: %s'],m,e.message));
        end
        rethrow(e);
    end
    clear c
end
for mode = {'c','l','i'}
    m = mode{1};
    tc.verifyEqual(G.(m)(:), ga, 'AbsTol',1e-12, sprintf('%s: gradient vs analytic',m));
end
tc.verifyEqual(G.l(:), G.c(:), 'AbsTol',0, 'coderload vs classic gradient');
tc.verifyEqual(G.i(:), G.c(:), 'AbsTol',0, 'inline vs classic gradient');
tc.verifyEqual(F.l, F.c, 'AbsTol',0, 'coderload vs classic value');
tc.verifyEqual(F.i, F.c, 'AbsTol',0, 'inline vs classic value');
end
