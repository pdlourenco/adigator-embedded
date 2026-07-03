classdef ICondAuxParamTest < matlab.unittest.TestCase
    % ICondAuxParamTest  Conditional on auxiliary struct-parameter fields (B18).
    %
    % Regression guard for B18 (docs/ANALYSIS.md Sec 1.3c): an `if` whose
    % condition is arithmetic on auxiliary (non-differentiated) struct-parameter
    % fields, with a subfunction called in a branch, must transform correctly --
    % ADiGator traces both branches and emits a runtime conditional whose
    % derivative is correct whichever branch the parameters select. This shape
    % formerly aborted the transformation; it no longer reproduces (most likely
    % resolved by the R8 struct-input support), so this is a guard only.
    %
    % Fixture: y = (cond==0) ? P.M*x : (P.M + P.a*I)*x, with the else branch in
    % a subfunction. The Jacobian is exactly M (branch A) or M + a*I (branch B),
    % checked against finite differences for both parameter selections from one
    % generated file.

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
        function condOnAuxParamsBothBranches(tc)
            n = 3;
            writeCondFixture('condaux');
            gx   = adigatorCreateDerivInput([n 1],'x');
            gp.a = adigatorCreateAuxInput([1 1]);
            gp.b = adigatorCreateAuxInput([1 1]);
            gp.c = adigatorCreateAuxInput([1 1]);
            gp.M = adigatorCreateAuxInput([n n]);
            adigatorGenJacFile('condaux',{gx,gp},struct('echo',0));
            rehash;

            rng(0); x0 = randn(n,1); M = randn(n);

            % Branch A: cond == 0  ->  y = M*x,  J = M
            pA = struct('a',0,'b',0,'c',0,'M',M);
            JA = condaux_Jac(x0,pA);
            tc.verifyEqual(JA, M, 'AbsTol', 1e-12, 'branch A (cond==0): J = M');
            tc.verifyEqual(JA, fdjac(@(x) condaux(x,pA), x0), ...
                'RelTol', 1e-5, 'AbsTol', 1e-6, 'branch A vs finite differences');

            % Branch B: cond ~= 0  ->  y = (M + a*I)*x,  J = M + a*I
            pB = struct('a',1.5,'b',0,'c',0,'M',M);
            JB = condaux_Jac(x0,pB);
            tc.verifyEqual(JB, M + 1.5*eye(n), 'AbsTol', 1e-12, ...
                'branch B (cond~=0): J = M + a*I');
            tc.verifyEqual(JB, fdjac(@(x) condaux(x,pB), x0), ...
                'RelTol', 1e-5, 'AbsTol', 1e-6, 'branch B vs finite differences');
        end
    end
end

% ---- helpers ----

function writeCondFixture(name)
% y = (P.a+P.b+P.c==0) ? P.M*x : scale(x,P); else branch in a subfunction.
fid = fopen([name,'.m'],'w');
assert(fid > 0, 'could not create fixture %s', name);
fprintf(fid, 'function y = %s(x, p)\n', name);
fprintf(fid, 'if (p.a + p.b + p.c) == 0\n');
fprintf(fid, '    y = p.M * x;\n');
fprintf(fid, 'else\n');
fprintf(fid, '    y = %s_scale(x, p);\n', name);
fprintf(fid, 'end\n');
fprintf(fid, 'end\n');
fprintf(fid, 'function y = %s_scale(x, p)\n', name);
fprintf(fid, 'y = (p.M + p.a*eye(3)) * x;\n');
fprintf(fid, 'end\n');
fclose(fid);
rehash;
end

function J = fdjac(f, x)
h = 1e-6;
fx = f(x);
m = numel(fx);
n = numel(x);
J = zeros(m, n);
for j = 1:n
    e = zeros(size(x)); e(j) = h;
    J(:,j) = reshape(f(x+e) - f(x-e), [], 1)/(2*h);
end
end
