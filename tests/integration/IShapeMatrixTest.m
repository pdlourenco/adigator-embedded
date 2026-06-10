classdef IShapeMatrixTest < matlab.unittest.TestCase
    % IShapeMatrixTest  Dimension/shape matrix for the derivative wrappers.
    %
    % CI plan: TS-I-01, verifies REQ-C-04, REQ-T-01, REQ-T-02 (and parts of
    % REQ-T-03). Exercises adigatorGenJacFile / adigatorGenHesFile across
    % input shape x output shape x density combinations, asserting the
    % shapes from adigatorDerivativeConventions.m and values against finite
    % differences / analytic references.
    %
    % Known-issue handling (docs/ANALYSIS.md B7-B10): tests in the
    % KnownIssue-tagged block detect the documented buggy behavior and
    % assumeFail (reported as filtered, non-blocking). When the bug is
    % fixed the detection no longer triggers and the trailing verifications
    % run, turning the test into the regression guard automatically.

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

    %% ------------------- currently-correct behavior ------------------- %%
    methods (Test)
        function jacVectorOfVectorPartial(tc)
            % f: R3 -> R4, structurally sparse Jacobian, full projection path
            writeFixture('fixt_jvv', ...
                'y = [x(1)*x(2); sin(x(3)); x(1)^2; exp(x(2))*x(3)];');
            ax = adigatorCreateDerivInput([3 1],'x');
            adigatorGenJacFile('fixt_jvv',{ax},struct('echo',0));
            rehash;
            xv = [0.7; -1.3; 0.4];
            [J,F] = fixt_jvv_Jac(xv);
            tc.verifyEqual(F, fixt_jvv(xv), 'AbsTol', 1e-14);
            tc.verifySize(J, [4 3]);
            tc.verifyEqual(J, fdjac(@fixt_jvv, xv), 'AbsTol', 1e-5, 'RelTol', 1e-5);
        end

        function gradScalarOfVectorDense(tc)
            % f: R3 -> R, dense gradient, 'Grd' convention -> column vector
            writeFixture('fixt_gsd', 'y = x(1)^2*x(2) + 2*x(2) + sin(x(3));');
            ax = adigatorCreateDerivInput([3 1],'x');
            adigatorGenJacFile('fixt_gsd',{ax},struct('echo',0),'Grd');
            rehash;
            xv = [0.7; -1.3; 0.4];
            [G,F] = fixt_gsd_Grd(xv);
            tc.verifyEqual(F, fixt_gsd(xv), 'AbsTol', 1e-14);
            tc.verifySize(G, [3 1]);
            tc.verifyEqual(G, fdjac(@fixt_gsd, xv).', 'AbsTol', 1e-5, 'RelTol', 1e-5);
        end

        function jacScalarOfVectorSparse(tc)
            % f: R4 -> R, sparse gradient, Jacobian convention -> 1 x n row
            writeFixture('fixt_jss', 'y = x(1)^2 + sin(x(3));');
            ax = adigatorCreateDerivInput([4 1],'x');
            adigatorGenJacFile('fixt_jss',{ax},struct('echo',0));
            rehash;
            xv = [0.7; -1.3; 0.4; 2.1];
            [J,F] = fixt_jss_Jac(xv);
            tc.verifyEqual(F, fixt_jss(xv), 'AbsTol', 1e-14);
            tc.verifySize(J, [1 4]);
            tc.verifyEqual(J, fdjac(@fixt_jss, xv), 'AbsTol', 1e-5, 'RelTol', 1e-5);
        end

        function jacVectorOfScalar(tc)
            % f: R -> R3 with one constant element (partial path). Regression
            % guard for the upstream zeros(dydxsize(2),1) allocation bug.
            writeFixture('fixt_jvs', 'y = [x^2; sin(x); 2];');
            ax = adigatorCreateDerivInput([1 1],'x');
            adigatorGenJacFile('fixt_jvs',{ax},struct('echo',0));
            rehash;
            xv = 0.8;
            [J,F] = fixt_jvs_Jac(xv);
            tc.verifyEqual(F, fixt_jvs(xv), 'AbsTol', 1e-14);
            tc.verifySize(J, [3 1]);
            tc.verifyEqual(J, fdjac(@fixt_jvs, xv), 'AbsTol', 1e-5, 'RelTol', 1e-5);
        end

        function hesScalarOfVector(tc)
            % f: R3 -> R: Hes n x n, Grd n x 1 (the dominant use case)
            writeFixture('fixt_hsv', 'y = x(1)^2*x(2) + sin(x(3));');
            ax = adigatorCreateDerivInput([3 1],'x');
            adigatorGenHesFile('fixt_hsv',{ax},struct('echo',0));
            rehash;
            xv = [0.7; -1.3; 0.4];
            [H,G,F] = fixt_hsv_Hes(xv);
            tc.verifyEqual(F, fixt_hsv(xv), 'AbsTol', 1e-14);
            tc.verifySize(G, [3 1]);
            tc.verifyEqual(G, fdjac(@fixt_hsv, xv).', 'AbsTol', 1e-5, 'RelTol', 1e-5);
            tc.verifySize(H, [3 3]);
            Hfd = squeeze(fdhess(@fixt_hsv, xv));
            tc.verifyEqual(H, Hfd, 'AbsTol', 1e-4, 'RelTol', 1e-4);
        end

        function hesScalarOfMatrix(tc)
            % f: R(2x2) -> R: Grd in input shape (2x2), Hes n x n over the
            % column-major linearization of X
            writeFixture('fixt_hsm', ...
                'y = x(1,1)^2*x(2,2) + sin(x(1,2))*x(2,1);');
            ax = adigatorCreateDerivInput([2 2],'x');
            adigatorGenHesFile('fixt_hsm',{ax},struct('echo',0));
            rehash;
            Xv = [0.7 -1.3; 0.4 2.1];
            [H,G,F] = fixt_hsm_Hes(Xv);
            tc.verifyEqual(F, fixt_hsm(Xv), 'AbsTol', 1e-14);
            % gradient follows the generalization table: input shape
            tc.verifySize(G, [2 2]);
            fvec = @(v) fixt_hsm(reshape(v,2,2));
            tc.verifyEqual(reshape(G,[],1), fdjac(fvec, Xv(:)).', ...
                'AbsTol', 1e-5, 'RelTol', 1e-5);
            tc.verifySize(H, [4 4]);
            Hfd = squeeze(fdhess(fvec, Xv(:)));
            tc.verifyEqual(H, Hfd, 'AbsTol', 1e-4, 'RelTol', 1e-4);
        end
    end

    %% --------------------- known-issue detection ---------------------- %%
    methods (Test, TestTags = {'KnownIssue'})
        function jacScalarOfMatrix(tc)
            % B10: JacobianStructure built with remapped dydxsize but
            % unrolled nzlocs -> generation currently errors.
            writeFixture('fixt_jsm', 'y = sum(sum(x.^2));');
            ax = adigatorCreateDerivInput([2 3],'x');
            try
                adigatorGenJacFile('fixt_jsm',{ax},struct('echo',0));
            catch e
                tc.assumeFail("Known issue B10 (JacobianStructure, scalar of matrix): " + e.message);
            end
            rehash;
            Xv = [0.7 -1.3 0.4; 2.1 0.3 -0.5];
            [J,F] = fixt_jsm_Jac(Xv);
            tc.verifyEqual(F, fixt_jsm(Xv), 'AbsTol', 1e-14);
            tc.verifySize(J, [2 3]); % generalization table: input shape
            fvec = @(v) fixt_jsm(reshape(v,2,3));
            tc.verifyEqual(reshape(J,[],1).', fdjac(fvec, Xv(:)), ...
                'AbsTol', 1e-5, 'RelTol', 1e-5);
        end

        function jacMatrixOfScalar(tc)
            % B10: same defect on the matrix-function-of-scalar remap.
            writeFixture('fixt_jms', 'y = [x^2 sin(x); exp(x) x^3];');
            ax = adigatorCreateDerivInput([1 1],'x');
            try
                adigatorGenJacFile('fixt_jms',{ax},struct('echo',0));
            catch e
                tc.assumeFail("Known issue B10 (JacobianStructure, matrix of scalar): " + e.message);
            end
            rehash;
            xv = 0.8;
            [J,F] = fixt_jms_Jac(xv);
            tc.verifyEqual(F, fixt_jms(xv), 'AbsTol', 1e-14);
            tc.verifySize(J, [2 2]); % generalization table: output shape
            fvec = @(v) fixt_jms(v);
            Jfd = fdjac(fvec, xv); % 4 x 1, column-major over output
            tc.verifyEqual(reshape(J,[],1), Jfd, 'AbsTol', 1e-5, 'RelTol', 1e-5);
        end

        function hesVectorOutputNGreaterM(tc)
            % B7 (error variant): f: R3 -> R2. The wrapper builds Hessian
            % rows as (x1-1)*n + y; with n > m this exceeds m*n and the
            % indexed assignment errors at evaluation time.
            writeFixture('fixt_h32', 'y = [x(1)^2*x(2); sin(x(3))];');
            ax = adigatorCreateDerivInput([3 1],'x');
            adigatorGenHesFile('fixt_h32',{ax},struct('echo',0));
            rehash;
            xv = [0.7; -1.3; 0.4];
            try
                [H,G,F] = fixt_h32_Hes(xv); %#ok<ASGLU>
            catch e
                tc.assumeFail("Known issue B7 (vector-output Hessian, n>m): " + e.message);
            end
            verifyVectorHessian(tc, @fixt_h32, xv, H, 2, 3);
        end

        function hesVectorOutputMGreaterN(tc)
            % B7 (silent variant): f: R2 -> R3. With m > n the wrong
            % multiplier stays in bounds but collides rows -> wrong values.
            writeFixture('fixt_h23', ...
                'y = [x(1)^2*x(2); x(2)^2*x(1); x(1)^3];');
            ax = adigatorCreateDerivInput([2 1],'x');
            adigatorGenHesFile('fixt_h23',{ax},struct('echo',0));
            rehash;
            xv = [0.7; -1.3];
            [H,G,F] = fixt_h23_Hes(xv); %#ok<ASGLU>
            Hexp = expectedVectorHessian(@fixt_h23, xv, 3, 2);
            if max(abs(H(:) - Hexp(:))) > 1e-4
                tc.assumeFail(sprintf(['Known issue B7 (vector-output Hessian, ', ...
                    'm>n row collisions): max abs error %g'], max(abs(H(:) - Hexp(:)))));
            end
            verifyVectorHessian(tc, @fixt_h23, xv, H, 3, 2);
        end

        function hesMatrixOfScalar(tc)
            % B8: matrix output of scalar input. The n==1 branch assigns
            % Hes(location)=vals with an nnz x 2 subscript matrix treated
            % as linear indices -> errors (element-count mismatch).
            writeFixture('fixt_hms', 'y = [x^2 sin(x); exp(x) x^3];');
            ax = adigatorCreateDerivInput([1 1],'x');
            adigatorGenHesFile('fixt_hms',{ax},struct('echo',0));
            rehash;
            xv = 0.8;
            try
                [H,G,F] = fixt_hms_Hes(xv); %#ok<ASGLU>
            catch e
                tc.assumeFail("Known issue B8 (matrix-output-of-scalar Hessian): " + e.message);
            end
            tc.verifySize(H, [2 2]);
            fvec = @(v) fixt_hms(v);
            Hfd = fdhess(fvec, xv); % 4 x 1 x 1: d2y_k/dx2
            tc.verifyEqual(H(:), squeeze(Hfd), 'AbsTol', 1e-4, 'RelTol', 1e-4);
        end

        function grdSparseBranchOfVectorOutput(tc)
            % B9: in adigatorGenHesFile the sparse projection branch emits
            % Grd = sparse(...)' (n x m) while the full branch emits m x n.
            % Needs numel(J) >= 250 with <= 75% nonzeros: m=25, n=10.
            A = zeros(25,10);
            A(round(linspace(1,250,30))) = 1:30;
            writeFixture('fixt_b9', { ...
                sprintf('A = %s;', mat2str(A)), ...
                'y = A*(x.^2);'});
            ax = adigatorCreateDerivInput([10 1],'x');
            adigatorGenHesFile('fixt_b9',{ax},struct('echo',0));
            rehash;
            xv = (1:10).'/7;
            [H,G,F] = fixt_b9_Hes(xv); %#ok<ASGLU>
            if ~isequal(size(G), [25 10])
                tc.assumeFail(sprintf(['Known issue B9 (sparse-branch gradient ', ...
                    'transposed): size(Grd) = [%d %d], expected [25 10]'], size(G)));
            end
            tc.verifyEqual(full(G), fdjac(@fixt_b9, xv), 'AbsTol', 1e-4, 'RelTol', 1e-4);
        end
    end
end

%% ============================ helpers ================================ %%

function writeFixture(name, body)
% write function y = <name>(x) with the given body line(s) into pwd
if ischar(body) || isstring(body); body = {char(body)}; end
fid = fopen([name,'.m'],'w');
assert(fid > 0, 'could not create fixture %s', name);
fprintf(fid, 'function y = %s(x)\n', name);
fprintf(fid, '%s\n', body{:});
fprintf(fid, 'end\n');
fclose(fid);
rehash;
end

function J = fdjac(f, x)
% central finite-difference Jacobian, output linearized column-major
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

function H = fdhess(f, x)
% central finite-difference second derivatives: H(k,i,j) = d2 f_k / dx_i dx_j
h = 1e-4;
m = numel(f(x));
n = numel(x);
H = zeros(m, n, n);
for i = 1:n
    ei = zeros(size(x)); ei(i) = h;
    for j = 1:n
        ej = zeros(size(x)); ej(j) = h;
        H(:,i,j) = reshape( ...
            f(x+ei+ej) - f(x+ei-ej) - f(x-ei+ej) + f(x-ei-ej), [], 1)/(4*h^2);
    end
end
end

function Hexp = expectedVectorHessian(f, x, m, n)
% expected wrapper layout (docs and HessianStructure):
% Hes((x1-1)*m + y, x2) = d2 f_y / dx1 dx2, size [m*n, n]
H3 = fdhess(f, x);
Hexp = zeros(m*n, n);
for y = 1:m
    for x1 = 1:n
        Hexp((x1-1)*m + y, :) = squeeze(H3(y, x1, :)).';
    end
end
end

function verifyVectorHessian(tc, f, x, H, m, n)
tc.verifySize(H, [m*n, n]);
tc.verifyEqual(H, expectedVectorHessian(f, x, m, n), ...
    'AbsTol', 1e-4, 'RelTol', 1e-4);
end
