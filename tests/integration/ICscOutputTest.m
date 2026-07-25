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

        function partiallyConstantOutputCsc(tc)
            % a partially-constant output (row 2 is a literal) -> the CSC pattern
            % carries the structural zero (an empty column/row region) and still
            % reconstructs exactly.
            writeFcn('cz', {'function y = cz(x)', 'y = [x(1); 2.0];', 'end'});
            out = checkJac(tc, 'cz', [2 1], [0.3;0.9], 'Jacobian');
            tc.verifyEqual(out.JacobianCSC.Nnz, 1);   % only d(y1)/dx1 is structural
        end

        function singleRowJacobianCsc(tc)
            % 1 x n Jacobian (scalar function, Jacobian convention)
            writeFcn('csr', {'function y = csr(x)', 'y = x(1)^2 + sin(x(4));', 'end'});
            checkJac(tc, 'csr', [4 1], [0.7;-1.3;0.4;2.1], 'Jacobian');
        end

        function singleColumnJacobianCsc(tc)
            % m x 1 Jacobian (vector function of a scalar variable)
            writeFcn('csc1', {'function y = csc1(x)', 'y = [x^2; sin(x); 2];', 'end'});
            checkJac(tc, 'csc1', [1 1], 0.8, 'Jacobian');
        end

        function scalarOfScalarGradientRole(tc)
            % regression guard: a scalar-of-scalar function with the 'Grd'
            % appendix must export GradientCSC (not JacobianCSC), so consumers
            % that read out.GradientCSC unconditionally (e.g. mcGenClassic's
            % gradient arm) do not crash on the [1,1] shape.
            writeFcn('cs11', {'function y = cs11(x)', 'y = x^2 + sin(x);', 'end'});
            out = checkJac(tc, 'cs11', [1 1], 0.8, 'Gradient', 'Grd');
            tc.verifyEqual(out.GradientCSC.Size, [1 1]);
            tc.verifyFalse(isfield(out, 'JacobianCSC'), ...
                'scalar-of-scalar gradient must export GradientCSC, not JacobianCSC');
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
            % Jacobian / Hessian, so the generator emits the identity form
            % `<name> = <deriv>(:);` (NOT a constant gather `<deriv>([...])`).
            % This reads the GENERATED emission - the only place the native
            % nzlocs order is observable - so a future nzlocs reordering that
            % silently introduces the gather trips here. (The exported CSC struct
            % is already CSC-sorted, so it cannot witness the native order.)
            writeFcn('ti', {'function y = ti(x)', 'y = [x(1)*x(2); sin(x(3)); x(1)^2];', 'end'});
            adigatorGenJacFile('ti',{adigatorCreateDerivInput([3 1],'x')}, ...
                struct('overwrite',1,'echo',0,'der_output','csc')); rehash;
            jtxt = fileread('ti_Jac.m');
            tc.verifyNotEmpty(regexp(jtxt, 'Jac = \w+\.d\w+\(:\);', 'once'), ...
                'Jacobian csc emission must be the identity form <deriv>(:)');
            tc.verifyEmpty(regexp(jtxt, 'Jac = \w+\.d\w+\(\[', 'once'), ...
                'Jacobian value stream is no longer CSC order - a gather crept in');
            writeFcn('th', {'function y = th(x)', 'y = x(1)^2*x(2) + sin(x(3));', 'end'});
            adigatorGenHesFile('th',{adigatorCreateDerivInput([3 1],'x')}, ...
                struct('overwrite',1,'echo',0,'der_output','csc')); rehash;
            htxt = fileread('th_Hes.m');
            tc.verifyNotEmpty(regexp(htxt, 'Hes = \w+\.d\w+d\w+\(:\);', 'once'), ...
                'Hessian csc emission must be the identity form <deriv>(:)');
            tc.verifyEmpty(regexp(htxt, 'Hes = \w+\.d\w+d\w+\(\[', 'once'), ...
                'Hessian value stream is no longer CSC order - a gather crept in');
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

        function loopboundJacobianCscPaddedZeros(tc)
            % loopbound (#173): the file is generated at Nmax and evaluated for
            % n < Nmax; the CSC pattern keeps the Nmax shape with structural
            % zeros beyond n (padded-program semantics). csc reconstruction must
            % equal matrix mode at the SAME runtime n.
            writeFcn('clb', {'function y = clb(x, N)', 'y = zeros(3,1);', ...
                'for a = 1:N', '  y(a) = x(a)^2;', 'end', 'end'});
            Nmax = 3;
            gx = @() adigatorCreateDerivInput([Nmax 1],'x');
            % loopbound needs adigatorOptions (it normalizes the bound name to a
            % cellstr; a raw options struct would not).
            adigatorGenJacFile('clb', {gx(), Nmax}, ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N')); rehash;
            xv = [0.7; -1.3; 0.4]; nrun = 2;            % evaluate BELOW Nmax
            Jm = full(clb_Jac(xv, nrun));
            out = adigatorGenJacFile('clb', {gx(), Nmax}, ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N','der_output','csc'));
            rehash;
            v = clb_Jac(xv, nrun);
            tc.verifyEqual(out.JacobianCSC.Size, [3 3], ...
                'CSC pattern must keep the padded Nmax shape');
            tc.verifyEqual(full(adigatorCSCToSparse(out.JacobianCSC, v)), Jm, ...
                'AbsTol', 1e-12, ...
                'loopbound csc reconstruction must equal matrix mode at n<Nmax');
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
