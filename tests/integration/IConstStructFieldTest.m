classdef IConstStructFieldTest < matlab.unittest.TestCase
    % IConstStructFieldTest  Constant-struct field references (B17).
    %
    % Regression guard for B17 (docs/ANALYSIS.md Sec 1.3c): a numeric field of a
    % constant struct assigned in the function body -- inline (P = struct(...))
    % or from a load (S = load(...); P = S.field) -- must print as a bare
    % `P.field` reference, not a spurious `P.field.f`. The struct assignment is
    % emitted verbatim (a plain struct with no `.f`), so an `.f` reference would
    % make the generated derivative error at runtime ("Reference to non-existent
    % field 'f'").
    %
    % The fixture exercises the reported trigger shapes: a constant-struct field
    % used as an mtimes operand and a constant-struct field passed into a
    % subfunction. y = P.M*x + scaleit(P.g, x) = (M + g*I)*x, so the Jacobian is
    % exactly M + g*eye(n) -- an analytic reference.
    %
    % Jacobian-only by design: the spurious `.f` is a first-derivative printing
    % phenomenon (cadafuncname appends `.f` only in the DERNUMBER==1 branch), so
    % the Jacobian path is sufficient to pin B17.
    %
    % Note: evaluating 'i' (inline) output in MATLAB needs the coder.* namespace
    % (MATLAB Coder); without it the numeric run is skipped via assumption while
    % the generation + no-spurious-`.f` text assertion always runs.

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
        function inlineConstStructClassic(tc)
            % Constant struct built inline, classic mode: generates, runs, and
            % the derivative file carries no spurious `.f` on P.M / P.g.
            [M,g,n] = refParams();
            writeInlineFixture('cstruct_ci');
            ax = adigatorCreateDerivInput([n 1],'x');
            adigatorGenJacFile('cstruct_ci',{ax},struct('echo',0));
            rehash;

            body = fileread('cstruct_ci_ADiGatorJac.m');
            tc.verifyFalse(hasFieldDotF(body), ...
                'generated derivative references a constant-struct field as `.f`');

            xv = (1:n).'/n - 0.3;
            [J,F] = cstruct_ci_Jac(xv);
            tc.verifyEqual(F, cstruct_ci(xv), 'AbsTol', 1e-14, 'function value');
            tc.verifyEqual(J, M + g*eye(n), 'AbsTol', 1e-12, ...
                'Jacobian must equal the analytic M + g*I');
        end

        function loadConstStructClassic(tc)
            % Same, but the struct comes from a .mat load (the reported
            % provenance). Bare-ref must still resolve: the struct is
            % materialized in the body (S = load(...); P = S.P).
            [M,g,n] = refParams();
            P = struct('g',g,'M',M);
            save('cstruct_params.mat','P');
            writeLoadFixture('cstruct_cl');
            ax = adigatorCreateDerivInput([n 1],'x');
            adigatorGenJacFile('cstruct_cl',{ax},struct('echo',0));
            rehash;

            body = fileread('cstruct_cl_ADiGatorJac.m');
            tc.verifyFalse(hasFieldDotF(body), ...
                'load-sourced constant-struct field referenced as `.f`');

            xv = (1:n).'/n - 0.3;
            [J,~] = cstruct_cl_Jac(xv);
            tc.verifyEqual(J, M + g*eye(n), 'AbsTol', 1e-12, ...
                'Jacobian must equal the analytic M + g*I (load provenance)');
        end

        function inlineConstStructEmbedInline(tc)
            % Inline ('i') embedded pipeline: generation succeeds and the
            % emitted file has no spurious `.f`. Numeric run needs coder.*.
            [M,g,n] = refParams();
            writeInlineFixture('cstruct_ii');
            ax = adigatorCreateDerivInput([n 1],'x');
            adigatorGenDerFile_embedded('jacobian','cstruct_ii',{ax}, ...
                struct('embed_mode','i','echo',0,'overwrite',1));
            rehash;

            body = fileread('cstruct_ii_Jac.m');
            tc.verifyFalse(hasFieldDotF(body), ...
                'inline-mode file references a constant-struct field as `.f`');

            try
                xv = (1:n).'/n - 0.3;
                [J,~] = cstruct_ii_Jac(xv);
            catch e
                if strcmp(e.identifier,'MATLAB:UndefinedFunction') && ...
                        contains(e.message,'coder.')
                    tc.assumeFail(['inline mode needs the coder.* namespace ', ...
                        'to run in MATLAB; text assertion already ran: ', e.message]);
                end
                rethrow(e);
            end
            tc.verifyEqual(J, M + g*eye(n), 'AbsTol', 1e-12, ...
                'inline-mode Jacobian must equal the analytic M + g*I');
        end
    end
end

% ---- helpers ----

function [M,g,n] = refParams()
n = 3;
M = [1 0 0; 0 2 0; 0 0 3];
g = 2.5;
end

function writeInlineFixture(name)
% y = P.M*x + scaleit(P.g,x) with P a constant struct built inline.
writeFixtureBody(name, { ...
    'P = struct(''g'', 2.5, ''M'', [1 0 0; 0 2 0; 0 0 3]);', ...
    'v = P.M * x;', ...
    'w = scaleit(P.g, x);', ...
    'y = v + w;'});
end

function writeLoadFixture(name)
% Same, but P is loaded from cstruct_params.mat (present in pwd).
writeFixtureBody(name, { ...
    'S = load(''cstruct_params.mat'');', ...
    'P = S.P;', ...
    'v = P.M * x;', ...
    'w = scaleit(P.g, x);', ...
    'y = v + w;'});
end

function writeFixtureBody(name, bodyLines)
% Write function y = <name>(x) with a shared scaleit subfunction into pwd.
fid = fopen([name,'.m'],'w');
assert(fid > 0, 'could not create fixture %s', name);
fprintf(fid, 'function y = %s(x)\n', name);
fprintf(fid, '%s\n', bodyLines{:});
fprintf(fid, 'end\n');
fprintf(fid, 'function w = scaleit(g, x)\n');
fprintf(fid, 'w = g * x;\n');
fprintf(fid, 'end\n');
fclose(fid);
rehash;
end

function tf = hasFieldDotF(body)
% True if the generated text references a constant-struct field as `.f`,
% e.g. P.M.f / P.g.f / S.P... .f (the B17 signature).
tf = ~isempty(regexp(body, '\<P\.(M|g)\.f\>', 'once'));
end
