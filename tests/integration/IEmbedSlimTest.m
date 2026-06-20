classdef IEmbedSlimTest < matlab.unittest.TestCase
    % IEmbedSlimTest  Roadmap R7b/R7c end-to-end (issue #21): the slim_embed
    % option in the embedded pipeline. Generates a structurally sparse
    % Jacobian with and without slim_embed and checks that slimming (a) removes
    % the unread '_location' metadata from the generated derivative code (R7b
    % field-slice), (b) does not enlarge the pruned data, (c) leaves the numeric
    % result unchanged in coderload mode, and (d) leaves it unchanged in both
    % coderload and inline modes with the R7c union-copy peephole in the path.
    % The generation-time slice + closure gate + peephole + numeric round-trip
    % cross-check all run during the slim generation itself (in base MATLAB,
    % before the embed patching), so a successful slim generation already
    % exercises them; the runtime numeric checks below are an extra cross-check
    % (coder.* resolves in base MATLAB on most runners; it is assumption-skipped
    % where it does not).

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
        function slimRemovesUnreadMetadata(tc)
            writeFcn('es_fun', { ...
                'function y = es_fun(x)', ...
                'y = [x(1)^2; x(2)*x(3); sin(x(3))];', ...
                'end'});
            base = pwd;
            aDir = fullfile(base,'noslim');
            bDir = fullfile(base,'slim');

            adigatorGenDerFile_embedded('jacobian','es_fun', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','l','path',aDir,'echo',0));
            adigatorGenDerFile_embedded('jacobian','es_fun', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','l','path',bDir,'echo',0,'slim_embed',1));
            rehash;

            % (a) the slimmed derivative code drops the unread _location metadata
            txtA = readlines(fullfile(aDir,'es_fun_Jac.m'));
            txtB = readlines(fullfile(bDir,'es_fun_Jac.m'));
            tc.verifyTrue(any(contains(txtA,'_location')), ...
                'baseline derivative code should assign _location');
            tc.verifyFalse(any(contains(txtB,'_location')), ...
                'slim_embed must remove the unread _location assignment');

            % (b) the pruned data is no larger (drops the now-unreferenced index)
            nA = numGatorFields(fullfile(aDir,'es_fun_ADiGatorJac.mat'));
            nB = numGatorFields(fullfile(bDir,'es_fun_ADiGatorJac.mat'));
            tc.verifyLessThanOrEqual(nB, nA, ...
                'slimmed data should not be larger than the baseline');

            % (c) numeric result unchanged (coder.load resolves in base MATLAB;
            % assumption-skip where it does not)
            rng(11); xv = randn(3,1);
            [JA,FA] = evalJac(tc, aDir, xv);
            [JB,FB] = evalJac(tc, bDir, xv);
            tc.verifyEqual(full(JB), full(JA), 'AbsTol', 0, ...
                'slimmed Jacobian differs from baseline');
            tc.verifyEqual(FB, FA, 'AbsTol', 0, ...
                'slimmed function value differs from baseline');
        end

        function slimNumericallySafeAcrossModes(tc)
            % R7c wiring (issue #21): the union-copy peephole runs inside the
            % slim_embed driver, after the field-slice and under the same
            % numeric round-trip guard, in BOTH coderload and inline modes.
            % Whatever it collapses, the embedded derivative must stay
            % numerically identical to the unslimmed baseline. (The collapse
            % logic itself - which pairs are ordered-identity, hence safe - is
            % unit-tested deterministically in UPeepholeTest; this guards the
            % end-to-end wiring, including the inline path that has no
            % ADiGator_LoadData trailer in the final file.)
            writeFcn('es_fun', { ...
                'function y = es_fun(x)', ...
                'y = [x(1)^2; x(2)*x(3); sin(x(3))];', ...
                'end'});
            base = pwd;
            bDir = fullfile(base,'base');    % no slim, coderload (reference)
            lDir = fullfile(base,'slim_l');  % slim, coderload
            iDir = fullfile(base,'slim_i');  % slim, inline

            adigatorGenDerFile_embedded('jacobian','es_fun', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','l','path',bDir,'echo',0));
            adigatorGenDerFile_embedded('jacobian','es_fun', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','l','path',lDir,'echo',0,'slim_embed',1));
            adigatorGenDerFile_embedded('jacobian','es_fun', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','i','path',iDir,'echo',0,'slim_embed',1));
            rehash;

            rng(7); xv = randn(3,1);
            [J0,F0] = evalJac(tc, bDir, xv);
            [Jl,Fl] = evalJac(tc, lDir, xv);
            [Ji,Fi] = evalJac(tc, iDir, xv);
            tc.verifyEqual(full(Jl), full(J0), 'AbsTol', 0, ...
                'slimmed coderload Jacobian differs from baseline');
            tc.verifyEqual(full(Ji), full(J0), 'AbsTol', 0, ...
                'slimmed inline Jacobian differs from baseline');
            tc.verifyEqual(Fl, F0, 'AbsTol', 0, ...
                'slimmed coderload function value differs from baseline');
            tc.verifyEqual(Fi, F0, 'AbsTol', 0, ...
                'slimmed inline function value differs from baseline');
        end

        function peepholeRunsOnRealGeneratedArtifacts(tc)
            % R7c wiring (issue #21): exercise adigatorPeepholeUnionCopy against
            % REAL generated derivative code and the REAL Gator index tables,
            % loaded exactly as the driver's loadGatorData does. This guards the
            % data-layout integration (struct.<func>.Gator<D>Data) that the
            % synthetic UPeepholeTest fixtures cannot - a wrong layout would make
            % loadGatorData silently return [] and quietly disable the peephole.
            % Classic mode emits the vanilla, unpruned files, which mirror the
            % state the driver's peephole actually sees (it runs before the
            % prune, so the index tables are still present and double-typed).
            writeFcn('es_fun', { ...
                'function y = es_fun(x)', ...
                'y = [x(1)^2; x(2)*x(3); sin(x(3))];', ...
                'end'});
            gDir = fullfile(pwd,'real');
            adigatorGenDerFile_embedded('jacobian','es_fun', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','c','path',gDir,'echo',0));
            rehash;

            % load the data the way loadGatorData does (top field == dername)
            s  = load(fullfile(gDir,'es_fun_ADiGatorJac.mat'));
            tc.verifyTrue(isfield(s,'es_fun_ADiGatorJac'), ...
                'the .mat top field must be the derivative function name');
            gd = s.es_fun_ADiGatorJac;
            tc.verifyTrue(isfield(gd,'Gator1Data'), ...
                'real data must expose <func>.Gator1Data (loadGatorData layout)');

            mlines = readlines(fullfile(gDir,'es_fun_ADiGatorJac.m'));
            [out, pinfo] = adigatorPeepholeUnionCopy(mlines, gd);
            % resolves real index tables and parses real body without error
            tc.verifyGreaterThanOrEqual(pinfo.count, 0);
            tc.verifyEqual(pinfo.changed, pinfo.count > 0, ...
                'changed flag must agree with the collapse count');
            if pinfo.changed
                tc.verifyTrue(any(contains(out,'reshape(')), ...
                    'a collapsed union copy must emit a reshape(...)');
            end
        end

        function classicGenerationIsUnaffected(tc)
            % slim_embed in classic mode is a no-op (the loop never runs);
            % generation still succeeds and the wrapper is byte-for-byte the
            % same as without the option
            writeFcn('es_cl', { ...
                'function y = es_cl(x)', ...
                'y = x(1)^2 + sin(x(2));', ...
                'end'});
            base = pwd;
            cDir = fullfile(base,'c0'); sDir = fullfile(base,'c1');
            adigatorGenDerFile_embedded('jacobian','es_cl', ...
                {adigatorCreateDerivInput([2 1],'x')}, ...
                struct('embed_mode','c','path',cDir,'echo',0));
            adigatorGenDerFile_embedded('jacobian','es_cl', ...
                {adigatorCreateDerivInput([2 1],'x')}, ...
                struct('embed_mode','c','path',sDir,'echo',0,'slim_embed',1));
            tc.verifyEqual(readlines(fullfile(sDir,'es_cl_Jac.m')), ...
                readlines(fullfile(cDir,'es_cl_Jac.m')));
        end
    end
end

% ---------------------------- helpers ---------------------------------- %
function n = numGatorFields(matfile)
d = load(matfile);
fn = fieldnames(d);
g = d.(fn{1}).Gator1Data;
n = numel(fieldnames(g));
end

function [J,F] = evalJac(tc, dir, xv)
old = cd(dir);
restore = onCleanup(@() cd(old));
clear('es_fun_Jac'); clear('global','ADiGator_es_fun_ADiGatorJac'); rehash;
try
    [J,F] = es_fun_Jac(xv);
catch e
    if strcmp(e.identifier,'MATLAB:UndefinedFunction') && contains(e.message,'coder.')
        tc.assumeFail("coder.* namespace unavailable; skipping runtime check: " + e.message);
    end
    rethrow(e);
end
end

function writeFcn(name, lines)
fid = fopen([name '.m'], 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end
