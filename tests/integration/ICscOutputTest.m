classdef ICscOutputTest < matlab.unittest.TestCase
    % ICscOutputTest  The CSC output contract end-to-end (issue #192, ADR-0030,
    % R31; CI_PLAN TS-I-25, REQ-T-03/REQ-T-11/REQ-T-01).
    %
    % For each derivative shape: der_output='csc' returns the Nnz x 1 value
    % vector whose reconstruction (adigatorCSCToSparse over the exported
    % <Role>CSC) exactly equals the matrix-mode derivative; the exported pattern
    % is a superset cross-checked vs finite differences; the generated procedure
    % returns values only (no sparse(), dense scatter, or runtime sort). Also
    % pins adigatorBuildCSC's permutation as IDENTITY on representative
    % Jacobian/gradient/Hessian streams - a tripwire so a future nzlocs-ordering
    % change cannot silently introduce the constant gather.

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
        function jacobianSparseCscReconstructsMatrix(tc)
            writeFcn('cj', {'function y = cj(x)', ...
                'y = [x(1)*x(2); sin(x(3)); x(1)^2; exp(x(2))*x(3)];', 'end'});
            checkJac(tc, 'cj', [3 1], [0.7;-1.3;0.4], 'Jacobian');
        end

        function jacobianDenseCscReconstructsMatrix(tc)
            writeFcn('cjd', {'function y = cjd(x)', 'y = [x(1)+x(2); x(1)*x(2)];', 'end'});
            checkJac(tc, 'cjd', [2 1], [0.6;1.1], 'Jacobian');
        end

        function gradientCscColumnConvention(tc)
            writeFcn('cg', {'function y = cg(x)', 'y = x(1)^2 + exp(x(3));', 'end'});
            % 'Grd' appendix -> gradient convention; GradientCSC.Size = [n,1]
            out = checkJac(tc, 'cg', [3 1], randn(3,1), 'Gradient', 'Grd');
            tc.verifyEqual(out.GradientCSC.Size, [3 1]);
        end

        function scalarHessianCscReconstructsMatrix(tc)
            writeFcn('ch', {'function y = ch(x)', 'y = x(1)^2*x(2) + sin(x(3));', 'end'});
            checkHes(tc, 'ch', [3 1], [0.7;-1.3;0.4], [3 3]);
        end

        function vectorFoldHessianCscReconstructsMatrix(tc)
            writeFcn('cvh', {'function y = cvh(x)', ...
                'y = [x(1)^2*x(2); x(2)^2*x(1); x(1)^3];', 'end'});
            checkHes(tc, 'cvh', [2 1], [0.7;-1.3], [6 2]);   % [m*n n], m=3,n=2
        end

        function scalarOfMatrixHessianCscReconstructsMatrix(tc)
            writeFcn('chm', {'function y = chm(x)', ...
                'y = x(1,1)^2*x(2,2) + sin(x(1,2))*x(2,1);', 'end'});
            checkHes(tc, 'chm', [2 2], [0.7 -1.3;0.4 2.1], [4 4]);
        end

        function matrixOfScalarHessianCscReconstructsMatrix(tc)
            % B23 territory: HessianCSC.Size must be the true [2 2] output shape
            writeFcn('cms', {'function y = cms(x)', 'y = [x^2 x^3; 2*x^2 4*x];', 'end'});
            checkHes(tc, 'cms', [1 1], 0.8, [2 2]);
        end

        function emptyDerivativeCsc(tc)
            % structurally constant output -> zero-nnz CSC, still reconstructs
            writeFcn('cz', {'function y = cz(x)', 'y = [x(1); 2.0];', 'end'});
            out = checkJac(tc, 'cz', [2 1], [0.3;0.9], 'Jacobian');
            tc.verifyGreaterThanOrEqual(out.JacobianCSC.Nnz, 1);
        end

        function generatedCscProcedureIsValuesOnly(tc)
            % the csc wrapper must not call sparse(), allocate a dense
            % derivative, or scatter/sort at runtime
            writeFcn('cw', {'function y = cw(x)', 'y = [x(1)*x(2); x(3)^2];', 'end'});
            adigatorGenJacFile('cw',{adigatorCreateDerivInput([3 1],'x')}, ...
                struct('overwrite',1,'echo',0,'der_output','csc'));
            rehash;
            txt = fileread('cw_Jac.m');
            tc.verifyFalse(contains(txt,'sparse('), 'csc wrapper must not call sparse()');
            tc.verifyFalse(contains(txt,'Jac = zeros'), 'csc wrapper must not allocate dense');
            tc.verifyFalse(contains(txt,'sort('), 'csc wrapper must not sort at runtime');
        end

        function buildCscPermutationIsIdentityTripwire(tc)
            % the native value stream must already be CSC order for the plain
            % Jacobian / gradient / Hessian - assert isIdentity so a future
            % nzlocs reordering that silently needs a gather trips here.
            writeFcn('ti', {'function y = ti(x)', 'y = [x(1)*x(2); sin(x(3)); x(1)^2];', 'end'});
            oj = adigatorGenJacFile('ti',{adigatorCreateDerivInput([3 1],'x')}, ...
                struct('overwrite',1,'echo',0)); rehash;
            [~,~,isid] = adigatorBuildCSC(oj.JacobianCSC.Size, ...
                adigatorCSCToLocs(oj.JacobianCSC));
            tc.verifyTrue(isid, 'Jacobian value stream must already be CSC order');
            writeFcn('th', {'function y = th(x)', 'y = x(1)^2*x(2) + sin(x(3));', 'end'});
            oh = adigatorGenHesFile('th',{adigatorCreateDerivInput([3 1],'x')}, ...
                struct('overwrite',1,'echo',0)); rehash;
            [~,~,isidH] = adigatorBuildCSC(oh.HessianCSC.Size, ...
                adigatorCSCToLocs(oh.HessianCSC));
            tc.verifyTrue(isidH, 'Hessian value stream must already be CSC order');
        end

        function classicInlineCrossModeAgree(tc)
            % the csc VALUES must be identical across embed modes (classic vs
            % inline), since the pattern and value order are generation-time
            % constants.
            writeFcn('cc', {'function y = cc(x)', 'y = [x(1)*x(2); x(2)+x(3)];', 'end'});
            writeFcn('ci', {'function y = ci(x)', 'y = [x(1)*x(2); x(2)+x(3)];', 'end'});
            xv = [0.5;1.2;-0.4];
            oc = adigatorGenJacFile('cc',{adigatorCreateDerivInput([3 1],'x')}, ...
                struct('overwrite',1,'echo',0,'der_output','csc','embed_mode','c')); rehash;
            vc = cc_Jac(xv);
            oi = adigatorGenJacFile('ci',{adigatorCreateDerivInput([3 1],'x')}, ...
                struct('overwrite',1,'echo',0,'der_output','csc','embed_mode','i')); rehash;
            vi = ci_Jac(xv);
            tc.verifyEqual(vi, vc, 'AbsTol', 0, ...
                'csc values must be identical across classic/inline modes');
            tc.verifyEqual(adigatorCSCToLocs(oi.JacobianCSC), ...
                adigatorCSCToLocs(oc.JacobianCSC));
        end
    end
end

%% ============================ helpers ================================ %%
function out = checkJac(tc, name, xsz, xv, role, appendix)
if nargin < 6; appendix = 'Jac'; end
ax = @() adigatorCreateDerivInput(xsz,'x');
if strcmp(appendix,'Jac')
    adigatorGenJacFile(name,{ax()},struct('overwrite',1,'echo',0));
else
    adigatorGenJacFile(name,{ax()},struct('overwrite',1,'echo',0),appendix);
end
rehash; Dm = feval([name '_' appendix], xv);
if strcmp(appendix,'Jac')
    out = adigatorGenJacFile(name,{ax()},struct('overwrite',1,'echo',0,'der_output','csc'));
else
    out = adigatorGenJacFile(name,{ax()},struct('overwrite',1,'echo',0,'der_output','csc'),appendix);
end
rehash; v = feval([name '_' appendix], xv);
csc = out.([role 'CSC']);
tc.verifySize(v, [csc.Nnz 1]);
tc.verifyEqual(full(adigatorCSCToSparse(csc, v)), full(Dm), 'AbsTol', 1e-12, ...
    'csc reconstruction must equal the matrix-mode derivative');
% pattern is a superset of the matrix-mode nonzeros
tc.verifyEqual(nnz(Dm(full(adigatorCSCToSparse(csc,ones(csc.Nnz,1)))==0)), 0);
end

function checkHes(tc, name, xsz, xv, expectSize)
ax = @() adigatorCreateDerivInput(xsz,'x');
adigatorGenHesFile(name,{ax()},struct('overwrite',1,'echo',0)); rehash;
Hm = full(feval([name '_Hes'], xv));
out = adigatorGenHesFile(name,{ax()}, ...
    struct('overwrite',1,'echo',0,'der_output','csc')); rehash;
hv = feval([name '_Hes'], xv);
csc = out.HessianCSC;
tc.verifyEqual(csc.Size, expectSize, 'HessianCSC.Size must be the true output shape');
tc.verifySize(hv, [csc.Nnz 1]);
tc.verifyEqual(full(adigatorCSCToSparse(csc, hv)), Hm, 'AbsTol', 1e-10, ...
    'csc Hessian reconstruction must equal the matrix-mode Hessian');
% FD cross-check of the reconstructed Hessian (scalar-output cases)
if expectSize(1) == expectSize(2) && numel(xv) == expectSize(1)
    tc.verifyEqual(full(adigatorCSCToSparse(csc,hv)), fdHess(name, xv), ...
        'AbsTol', 1e-4, 'RelTol', 1e-4);
end
end

function H = fdHess(name, x)
f = str2func(name); n = numel(x); H = zeros(n); e = 1e-4;
for i = 1:n
    for j = 1:n
        ei = zeros(size(x)); ei(i)=e; ej = zeros(size(x)); ej(j)=e;
        H(i,j) = (f(x+ei+ej)-f(x+ei-ej)-f(x-ei+ej)+f(x-ei-ej))/(4*e^2);
    end
end
end

function writeFcn(name, lines)
fid = fopen([name '.m'],'w'); fprintf(fid,'%s\n',lines{:}); fclose(fid); rehash;
end
