classdef IEmbedSlimRolledTest < matlab.unittest.TestCase
    % IEmbedSlimRolledTest  R10(a) end-to-end (issue #44 item 1): the slim_embed
    % driver must now slice a MULTI-SUBFUNCTION generated file that contains a
    % ROLLED for...end loop (unroll=0), which adigatorSlimDerivFile previously
    % bailed on. Generates a 3-subfunction Jacobian whose middle subfunction sums
    % via a rolled loop, with and without slim_embed, and asserts (a) the slice
    % actually fired across the rolled file - the unread _location metadata is
    % gone (proof the conservative bail is lifted), and (b) the slimmed
    % derivative is numerically identical to the unslimmed baseline and to the
    % analytic Jacobian. The generation-time slice + closure gate + numeric
    % round-trip all run during the slim generation; the runtime check is the
    % extra cross-check (coder.* resolves in base MATLAB on most runners; it is
    % assumption-skipped where it does not).

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
        function slimSlicesRolledMultiSubfunctionAndStaysExact(tc)
            % a multi-subfunction user function whose middle subfunction uses a
            % rolled for...end: y(i) = x(i)^2 (looped) + 3*x(i) -> diag(2x+3)
            writeMultiFcn('mfE', { ...
                'function y = mfE(x)', ...
                'a = sqloop(x);', ...
                'b = lin(x);', ...
                'y = a + b;', ...
                'end', ...
                'function s = sqloop(x)', ...
                's = zeros(3,1);', ...
                'for i = 1:3', ...
                '  s(i) = x(i)^2;', ...
                'end', ...
                'end', ...
                'function h = lin(x)', ...
                'h = 3*x;', ...
                'end'});
            base = pwd;
            aDir = fullfile(base,'noslim');
            bDir = fullfile(base,'slim');

            % baseline must opt OUT of slimming explicitly: the embedded
            % generator defaults slim_embed ON (ADR-0012), so slim_embed=0 is
            % what makes aDir the genuine unslimmed reference for the assertions
            adigatorGenDerFile_embedded('jacobian','mfE', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','l','path',aDir,'echo',0,'unroll',0,'slim_embed',0));
            adigatorGenDerFile_embedded('jacobian','mfE', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','l','path',bDir,'echo',0,'unroll',0,'slim_embed',1));
            rehash;

            % (a) the slice fired across the rolled multi-subfunction file: the
            %     baseline assigns the unread _location metadata, the slimmed
            %     file no longer does (it would still be present if the rolled
            %     multi-subfunction file had been conservatively bailed)
            txtA = readlines(fullfile(aDir,'mfE_Jac.m'));
            txtB = readlines(fullfile(bDir,'mfE_Jac.m'));
            tc.verifyTrue(any(contains(txtA,'_location')), ...
                'baseline derivative code should assign _location');
            tc.verifyFalse(any(contains(txtB,'_location')), ...
                'slim_embed must remove the unread _location from the rolled file');

            % (b) numeric result unchanged and equal to the analytic Jacobian
            rng(3); xv = randn(3,1);
            [JA,FA] = evalJac(tc, aDir, 'mfE_Jac', xv);
            [JB,FB] = evalJac(tc, bDir, 'mfE_Jac', xv);
            tc.verifyEqual(full(JB), full(JA), 'AbsTol', 0, ...
                'slimmed rolled-file Jacobian differs from baseline');
            tc.verifyEqual(FB, FA, 'AbsTol', 0, ...
                'slimmed rolled-file function value differs from baseline');
            tc.verifyEqual(full(JA), diag(2*xv + 3), 'AbsTol', 1e-12, ...
                'baseline Jacobian differs from analytic diag(2x+3)');
        end
    end
end

% ---------------------------- helpers ---------------------------------- %
function [J,F] = evalJac(tc, dir, fn, xv)
old = cd(dir);
restore = onCleanup(@() cd(old));
clear(fn); clear('global',['ADiGator_',fn(1:end-4),'_ADiGatorJac']); rehash;
try
    [J,F] = feval(fn, xv);
catch e
    if strcmp(e.identifier,'MATLAB:UndefinedFunction') && contains(e.message,'coder.')
        tc.assumeFail("coder.* namespace unavailable; skipping runtime check: " + e.message);
    end
    rethrow(e);
end
end

function writeMultiFcn(name, lines)
fid = fopen([name '.m'], 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end
