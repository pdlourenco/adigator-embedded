classdef IConstCellFieldTest < matlab.unittest.TestCase
    % IConstCellFieldTest  Constant-cell element references (B22).
    %
    % Regression guard for B22 (docs/ANALYSIS.md Sec 1.3c), the cell analog of
    % B17. A numeric element of a constant *cell* assigned in the function body
    % (or a struct nested in one) is a compile-time constant, but the container
    % is emitted verbatim; without the fix its element references print as an
    % unbacked `C{i}.f` and the generated derivative crashes at runtime
    % ("Dot indexing is not supported ...").
    %
    % Fixtures use y = C{1}*x + C{2}*x = (M + g*I)*x, so the Jacobian is exactly
    % M + g*eye(n) -- an analytic reference (as in IConstStructFieldTest).
    %
    % Scope note (empirically established with this fixture set): the bug is the
    % *verbatim-emitted* constant-container path -- flat cells and structs
    % nested in cells. Constant struct *arrays* take a different, lifting path
    % (each field emitted as `P(i).A.f = <value>`, so the `.f` is backed) and
    % are already correct; structArrayStaysCorrect pins that as a positive
    % guard, not a fixed bug.
    %
    % Jacobian-only by design: the spurious `.f` is a first-derivative printing
    % phenomenon (cadafuncname appends `.f` only in the DERNUMBER==1 branch).

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
        function flatCellClassic(tc)
            % Constant cell built inline: C{1}/C{2} must print bare, not `.f`.
            [~,~,n,Jexp] = refParams();
            writeFixture('cc_flat', { ...
                'C = {[1 0 0; 0 2 0; 0 0 3], 2.5};', ...
                'y = C{1}*x + C{2}*x;'});
            ax = adigatorCreateDerivInput([n 1],'x');
            adigatorGenJacFile('cc_flat',{ax},struct('echo',0));
            rehash;
            body = fileread('cc_flat_ADiGatorJac.m');
            tc.verifyEmpty(regexp(body,'C\{\d+\}\.f','once'), ...
                'constant-cell element referenced as `.f`');
            xv = (1:n).'/n - 0.3;
            [J,F] = cc_flat_Jac(xv);
            tc.verifyEqual(F, cc_flat(xv), 'AbsTol', 1e-14, 'function value');
            tc.verifyEqual(J, Jexp, 'AbsTol', 1e-12, 'Jacobian must equal M + g*I');
        end

        function structNestedInCellClassic(tc)
            % A struct nested inside a constant cell -- same structflag=1 path.
            [~,~,n,Jexp] = refParams();
            writeFixture('cc_nest', { ...
                'C = { struct(''A'',[1 0 0;0 2 0;0 0 3]), struct(''A'',2.5*eye(3)) };', ...
                'y = C{1}.A*x + C{2}.A*x;'});
            ax = adigatorCreateDerivInput([n 1],'x');
            adigatorGenJacFile('cc_nest',{ax},struct('echo',0));
            rehash;
            body = fileread('cc_nest_ADiGatorJac.m');
            tc.verifyEmpty(regexp(body,'C\{\d+\}\.A\.f','once'), ...
                'struct-in-cell field referenced as `.f`');
            xv = (1:n).'/n - 0.3;
            [J,~] = cc_nest_Jac(xv);
            tc.verifyEqual(J, Jexp, 'AbsTol', 1e-12, 'Jacobian must equal M + g*I');
        end

        function flatCellEmbedRejected(tc)
            % Embed modes ('l'/'i') reject cells up front (ADR-0023 gate), so a
            % constant cell that works in classic (above) is a clear generation
            % error here -- not the runtime `.f` crash it used to be, and not a
            % silently non-embeddable file. (The classic B22 fix and the embed
            % gate are complementary: correct in 'c', rejected in 'l'/'i'.)
            [~,~,n] = refParams();
            writeFixture('cc_i', { ...
                'C = {[1 0 0; 0 2 0; 0 0 3], 2.5};', ...
                'y = C{1}*x + C{2}*x;'});
            ax = adigatorCreateDerivInput([n 1],'x');
            tc.verifyError(@() adigatorGenDerFile_embedded('jacobian','cc_i',{ax}, ...
                struct('embed_mode','i','echo',0,'overwrite',1)), ...
                'adigator:embed:unsupportedConstruct', ...
                'embed mode must reject a user cell array');
        end

        function structArrayStaysCorrect(tc)
            % Positive guard: a constant struct ARRAY uses the lifting path
            % (P(i).A.f = <value>), so it is already correct -- not a B22 bug.
            % Pin that it keeps generating and matching the analytic Jacobian.
            [~,~,n,Jexp] = refParams();
            writeFixture('cc_sarr', { ...
                'P(1).A = [1 0 0; 0 2 0; 0 0 3];', ...
                'P(2).A = 2.5*eye(3);', ...
                'y = P(1).A*x + P(2).A*x;'});
            ax = adigatorCreateDerivInput([n 1],'x');
            adigatorGenJacFile('cc_sarr',{ax},struct('echo',0));
            rehash;
            xv = (1:n).'/n - 0.3;
            [J,~] = cc_sarr_Jac(xv);
            tc.verifyEqual(J, Jexp, 'AbsTol', 1e-12, ...
                'struct-array Jacobian must equal M + g*I');
        end
    end
end

% ---- helpers ----

function [M,g,n,Jexp] = refParams()
n = 3;
M = [1 0 0; 0 2 0; 0 0 3];
g = 2.5;
Jexp = M + g*eye(n);
end

function writeFixture(name, bodyLines)
% Write function y = <name>(x) with the given body into pwd.
fid = fopen([name,'.m'],'w');
assert(fid > 0, 'could not create fixture %s', name);
fprintf(fid, 'function y = %s(x)\n', name);
fprintf(fid, '%s\n', bodyLines{:});
fprintf(fid, 'end\n');
fclose(fid);
rehash;
end
