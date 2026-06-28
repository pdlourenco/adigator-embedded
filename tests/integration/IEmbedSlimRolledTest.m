classdef IEmbedSlimRolledTest < matlab.unittest.TestCase
    % IEmbedSlimRolledTest  R10(a) end-to-end (issue #44 item 1): a
    % MULTI-SUBFUNCTION generated file containing a ROLLED for...end loop
    % (unroll=0) must generate and compute correctly through the full embedded
    % pipeline. Generates a 3-subfunction Jacobian whose middle subfunction sums
    % via a rolled loop, with and without slim_embed, and asserts (a) the dead
    % output-index metadata is gone regardless of slim_embed (since #80 Gap A the
    % embed pipeline strips it unconditionally), and (b) the result is
    % numerically identical with/without slim and equal to the analytic Jacobian.
    %
    % NB: that unconditional strip subsumes the only end-to-end signal this test
    % used to read (slim removing _location), so slim_embed 0 vs 1 now produce
    % byte-identical output here. The R10a "rolled multi-subfunction slice fires,
    % no conservative bail" coverage therefore lives where the strip cannot mask
    % it - USlimDerivFileTest/slicesRolledLoopReadingCalleeResult drives
    % adigatorSlimDerivFile directly. This test guards the end-to-end path
    % (generation + ERT-clean output + numeric exactness; coder.* resolves in
    % base MATLAB on most runners, assumption-skipped where it does not).

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

            % (a) the unread _location metadata is gone from the rolled
            %     multi-subfunction file regardless of slim_embed: since #80
            %     (Gap A) the embed pipeline strips the dead, ERT-breaking
            %     output-index metadata UNCONDITIONALLY. That strip subsumes the
            %     only end-to-end signal this test used to read - so slim_embed=0
            %     and slim_embed=1 now produce byte-identical output here, and
            %     this integration test no longer distinguishes them. The R10a
            %     "rolled multi-subfunction slice fires (no conservative bail)"
            %     coverage lives where it is actually observable, isolated from
            %     the embed strip:
            %     USlimDerivFileTest/slicesRolledLoopReadingCalleeResult drives
            %     adigatorSlimDerivFile directly. What this test still
            %     guards is the END-TO-END path: the rolled file generates
            %     through the full embed pipeline, is ERT-clean, and is exact.
            txtA = readlines(fullfile(aDir,'mfE_Jac.m'));
            txtB = readlines(fullfile(bDir,'mfE_Jac.m'));
            tc.verifyFalse(any(contains(txtA,'_location')), ...
                'dead _location metadata must be stripped even without slim_embed (#80)');
            tc.verifyFalse(any(contains(txtB,'_location')), ...
                'dead _location metadata must be stripped from the slimmed rolled file');

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
