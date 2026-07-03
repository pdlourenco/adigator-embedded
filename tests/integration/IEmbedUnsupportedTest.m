classdef IEmbedUnsupportedTest < matlab.unittest.TestCase
    % IEmbedUnsupportedTest  Embed-mode source-scan gate (ADR-0023).
    %
    % In embed modes ('l'/'i') the generated derivative must be dependency-free
    % and embeddable (DESIGN.md Contract C-4). A pre-transformation static scan
    % (adigatorScanEmbedUnsupported, wired into adigator.m) rejects cell arrays,
    % user `load`, and user `global` in the differentiated source with a clear
    % error -- resolving B21 (load) and B22-in-embed (cells) at generation time
    % instead of emitting non-embeddable code. Classic mode ('c') is permissive.

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

    properties (Constant)
        GateId = 'adigator:embed:unsupportedConstruct';
    end

    methods (Test)
        function cellRejectedInEmbed(tc)
            writeFn('u_cell', {'C = {[1 0 0;0 2 0;0 0 3], 2.5};', 'y = C{1}*x + C{2}*x;'});
            tc.verifyError(@() genEmbed('u_cell'), tc.GateId, 'cell must be rejected in embed');
        end

        function loadRejectedInEmbed(tc)
            A = eye(3); save('u_params.mat','A');
            writeFn('u_load', {'S = load(''u_params.mat'');', 'y = S.A*x;'});
            tc.verifyError(@() genEmbed('u_load'), tc.GateId, 'load must be rejected in embed');
        end

        function globalRejectedInEmbed(tc)
            writeFn('u_glob', {'global gg', 'y = x + 0*numel(gg);'});
            tc.verifyError(@() genEmbed('u_glob'), tc.GateId, 'global must be rejected in embed');
        end

        function cellInSubfunctionRejected(tc)
            % The scan covers every function ADiGator transforms, incl. local
            % subfunctions -- a cell hidden in a callee is still caught.
            writeRaw('u_sub', { ...
                'function y = u_sub(x)', ...
                'y = u_sub_helper(x);', ...
                'end', ...
                'function y = u_sub_helper(x)', ...
                'C = {2.5};', ...
                'y = C{1}*x;', ...
                'end'});
            tc.verifyError(@() genEmbed('u_sub'), tc.GateId, ...
                'cell in a subfunction must be rejected in embed');
        end

        function cellAllowedInClassic(tc)
            % Classic mode is permissive: the same cell generates (B22 fix) and
            % matches the analytic Jacobian M + g*I.
            writeFn('u_cc', {'C = {[1 0 0;0 2 0;0 0 3], 2.5};', 'y = C{1}*x + C{2}*x;'});
            ax = adigatorCreateDerivInput([3 1],'x');
            adigatorGenDerFile_embedded('jacobian','u_cc',{ax}, ...
                struct('embed_mode','c','echo',0,'overwrite',1,'path',pwd));
            rehash;
            [J,~] = u_cc_Jac((1:3).'/3 - 0.3);
            tc.verifyEqual(J, [1 0 0;0 2 0;0 0 3] + 2.5*eye(3), 'AbsTol', 1e-12);
        end

        function cleanEmbedGenerates(tc)
            % No false positives: braces in a comment / string do not trigger,
            % and a clean function generates in embed mode.
            writeRaw('u_clean', { ...
                'function y = u_clean(x)', ...
                '% a comment with { braces } and the word load here', ...
                's = ''a string { with } braces and global'';', ...
                'A = [1 0 0;0 2 0;0 0 3];', ...
                'y = A*x + numel(s)*0;', ...
                'end'});
            ax = adigatorCreateDerivInput([3 1],'x');
            tc.verifyWarningFree(@() adigatorGenDerFile_embedded('jacobian','u_clean',{ax}, ...
                struct('embed_mode','i','echo',0,'overwrite',1,'path',pwd)));
        end
    end
end

% ---- helpers ----

function genEmbed(name)
ax = adigatorCreateDerivInput([3 1],'x');
adigatorGenDerFile_embedded('jacobian',name,{ax}, ...
    struct('embed_mode','i','echo',0,'overwrite',1,'path',pwd));
end

function writeFn(name, bodyLines)
% function y = <name>(x) / body / end
raw = [{sprintf('function y = %s(x)', name)}, bodyLines(:).', {'end'}];
writeRaw(name, raw);
end

function writeRaw(name, lines)
fid = fopen([name,'.m'],'w');
assert(fid > 0, 'could not create fixture %s', name);
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end
