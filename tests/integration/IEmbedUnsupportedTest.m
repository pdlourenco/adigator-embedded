classdef IEmbedUnsupportedTest < matlab.unittest.TestCase
    % IEmbedUnsupportedTest  Embed-mode source-scan gate (ADR-0023, rev 2026-07-04).
    %
    % Embed modes ('l'/'i') aim for dependency-free, embeddable output (DESIGN.md
    % Contract C-4), but embed is *no more restrictive than classic*. A cell
    % array, user `load`, or user `global` in the differentiated source is
    % emitted verbatim (exactly as classic) and only produces a WARNING
    % (adigator:embed:unsupportedConstruct) that the generated file is not
    % self-contained and may not code-generate until the construct is removed --
    % it does NOT stop differentiation (the pre-#106 behavior + a warning). This
    % reclassifies B21 to warn-and-allow and lets B22-in-embed cells generate.
    %
    % Because the construct is emitted verbatim, the embed derivative is now
    % numerically identical to the classic one (AbsTol 0) -- a stronger pin than
    % warn-fired alone -- so each construct is checked cross-mode. Constructs
    % classic itself rejects still error from the core, unchanged (not exercised
    % here: this scan adds no gate beyond classic's). Classic mode ('c') never
    % calls the scan and stays silent.

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
        Xval   = (1:3).'/3 - 0.3;   % arbitrary interior point
    end

    methods (Test)
        function cellWarnsButGeneratesInEmbed(tc)
            % B22-in-embed: a constant cell warns, is emitted verbatim, and the
            % embed Jacobian matches the classic one bit-for-bit (and analytic).
            body = {'C = {[1 0 0;0 2 0;0 0 3], 2.5};', 'y = C{1}*x + C{2}*x;'};
            writeFn('u_cell', body);
            Ji = tc.genEmbedExpectWarn('u_cell');
            tc.verifyTrue(genFilesContain('u_cell', 'C{'), ...
                'cell must be emitted verbatim into the generated file');
            writeFn('u_cell_c', body);
            Jc = genClassic('u_cell_c');
            tc.verifyEqual(Ji, Jc, 'AbsTol', 0, 'embed cell must equal classic bit-for-bit');
            tc.verifyEqual(Ji, [1 0 0;0 2 0;0 0 3] + 2.5*eye(3), 'AbsTol', 1e-12);
        end

        function loadWarnsButGeneratesInEmbed(tc)
            % B21: a user `S = load(...)` warns (not self-contained), is emitted
            % verbatim, and -- with the .mat present -- still matches classic.
            A = eye(3); save('u_params.mat','A');
            body = {'S = load(''u_params.mat'');', 'y = S.A*x;'};
            writeFn('u_load', body);
            Ji = tc.genEmbedExpectWarn('u_load');
            tc.verifyTrue(genFilesContain('u_load', 'load(''u_params.mat'')'), ...
                'load must be emitted verbatim into the generated file');
            writeFn('u_load_c', body);
            Jc = genClassic('u_load_c');
            tc.verifyEqual(Ji, Jc, 'AbsTol', 0, 'embed load must equal classic bit-for-bit');
            tc.verifyEqual(Ji, eye(3), 'AbsTol', 1e-12);
        end

        function globalWarnsButGeneratesInEmbed(tc)
            % A user `global` warns, is emitted verbatim, and matches classic.
            clear global gg
            global gg %#ok<GVMIS>
            gg = [1 0 0;0 2 0;0 0 3];
            body = {'global gg', 'y = gg*x;'};
            writeFn('u_glob', body);
            Ji = tc.genEmbedExpectWarn('u_glob');
            tc.verifyTrue(genFilesContain('u_glob', 'global gg'), ...
                'global must be emitted verbatim into the generated file');
            writeFn('u_glob_c', body);
            Jc = genClassic('u_glob_c');
            tc.verifyEqual(Ji, Jc, 'AbsTol', 0, 'embed global must equal classic bit-for-bit');
            tc.verifyEqual(Ji, gg, 'AbsTol', 1e-12);
        end

        function cellInSubfunctionWarns(tc)
            % The scan covers every function ADiGator transforms, incl. local
            % subfunctions -- a cell hidden in a callee still warns, and the file
            % still generates.
            writeRaw('u_sub', { ...
                'function y = u_sub(x)', ...
                'y = u_sub_helper(x);', ...
                'end', ...
                'function y = u_sub_helper(x)', ...
                'C = {2.5};', ...
                'y = C{1}*x;', ...
                'end'});
            Ji = tc.genEmbedExpectWarn('u_sub');
            tc.verifyEqual(Ji, 2.5*eye(3), 'AbsTol', 1e-12, ...
                'cell in a subfunction must still generate a correct derivative');
        end

        function classicIsSilentAndCorrect(tc)
            % Classic mode is permissive AND never fires the gate: the same cell
            % generates warning-free and matches the analytic Jacobian M + g*I.
            writeFn('u_cc', {'C = {[1 0 0;0 2 0;0 0 3], 2.5};', 'y = C{1}*x + C{2}*x;'});
            tc.verifyWarningFree(@() genClassic('u_cc'), ...
                'classic mode must not fire the embed source-scan warning');
            J = u_cc_Jac(tc.Xval);
            tc.verifyEqual(J, [1 0 0;0 2 0;0 0 3] + 2.5*eye(3), 'AbsTol', 1e-12);
        end

        function cleanEmbedGeneratesWarningFree(tc)
            % No false positives: braces in a comment / string, and the words
            % load / global there, do not trigger; a clean function generates in
            % embed mode with no warning.
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

    methods
        function J = genEmbedExpectWarn(tc, name)
            % Generate in embed 'i', asserting the gate warning fires, then
            % evaluate the generated Jacobian wrapper.
            ax = adigatorCreateDerivInput([3 1],'x');
            tc.verifyWarning(@() adigatorGenDerFile_embedded('jacobian',name,{ax}, ...
                struct('embed_mode','i','echo',0,'overwrite',1,'path',pwd)), ...
                tc.GateId, sprintf('%s must warn in embed, not error', name));
            rehash;
            jacFn = str2func([name '_Jac']);
            J = jacFn(tc.Xval);
        end
    end
end

% ---- helpers ----

function J = genClassic(name)
ax = adigatorCreateDerivInput([3 1],'x');
adigatorGenDerFile_embedded('jacobian',name,{ax}, ...
    struct('embed_mode','c','echo',0,'overwrite',1,'path',pwd));
rehash;
jacFn = str2func([name '_Jac']);
J = jacFn((1:3).'/3 - 0.3);
end

function tf = genFilesContain(name, token)
% True if any generated <name>*.m file contains TOKEN verbatim. Used to assert
% the construct is emitted into the derivative file exactly as classic does.
tf = false;
files = dir([name '*.m']);
for k = 1:numel(files)
    txt = fileread(fullfile(files(k).folder, files(k).name));
    if contains(txt, token)
        tf = true; return
    end
end
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
