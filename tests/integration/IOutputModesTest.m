classdef IOutputModesTest < matlab.unittest.TestCase
    % IOutputModesTest  Roadmap R5 / #192 (ADR-0030) acceptance test: the
    % der_output='csc' wrapper mode - the structurally-possible-nonzero value
    % vector returned in compressed-sparse-column order, no per-call dense
    % projection, with the pattern exported once as output.<Role>CSC - and the
    % J'*v product file built on the R4 reverse engine. Also pins the removal of
    % the pre-release 'nonzeros' form and the jac_output alias (v2.0), and the
    % decision-b invariant (der_output selects the top-order output only; a
    % Hessian file's companion gradient is unaffected).

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
            tc.applyFixture(PathFixture(fullfile(root,'embedding')));  % adigatorGenHesFile -> updatestruct (#84 hessianNonzerosMode)
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function cscJacobianMode(tc)
            % structurally sparse Jacobian: der_output='csc' returns the value
            % vector in CSC order; reconstructing via JacobianCSC reproduces the
            % dense Jacobian exactly, and the pattern agrees with matrix mode.
            writeFcn('om_fun', { ...
                'function y = om_fun(x)', ...
                'y = [x(1)^2; x(2)*x(3); sin(x(3))];', ...
                'end'});
            writeFcn('om_fun2', { ...
                'function y = om_fun2(x)', ...
                'y = [x(1)^2; x(2)*x(3); sin(x(3))];', ...
                'end'});
            gx = @() adigatorCreateDerivInput([3 1],'x');
            outM = adigatorGenJacFile('om_fun',{gx()}, ...
                struct('overwrite',1,'echo',0));
            outN = adigatorGenJacFile('om_fun2',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_output','csc'));
            rehash;

            xv = randn(3,1);
            [JM,FM] = om_fun_Jac(xv);
            [vals,FN] = om_fun2_Jac(xv);
            tc.verifyEqual(FN, FM, 'AbsTol', 0);

            csc = outN.JacobianCSC;
            tc.verifySize(vals, [csc.Nnz 1]);
            JM = full(JM);
            % reconstructing the CSC value vector reproduces the full Jacobian
            tc.verifyEqual(full(adigatorCSCToSparse(csc, vals)), JM, 'AbsTol', 0);
            % the patterns agree between the two modes
            tc.verifyEqual(full(adigatorCSCToSparse(csc, ones(csc.Nnz,1))) ~= 0, ...
                full(adigatorCSCToSparse(outM.JacobianCSC, ones(outM.JacobianCSC.Nnz,1))) ~= 0);

            % the csc wrapper performs no dense projection
            wtxt = fileread('om_fun2_Jac.m');
            tc.verifyFalse(contains(wtxt,'Jac = zeros'), ...
                'csc wrapper must not allocate a dense Jacobian');
            tc.verifyFalse(contains(wtxt,'sparse('), ...
                'csc wrapper must not call sparse()');
        end

        function hessianCscMode(tc)
            % #192 (ADR-0030): der_output='csc' Hessian returns the value vector
            % in CSC order; reconstructing via HessianCSC reproduces the dense
            % Hessian, cross-checked vs FD (the Verified-by test).
            writeFcn('om_hfun',  {'function y = om_hfun(x)', ...
                    'y = x(1)^2 + x(2)*x(3) + sin(x(3));', 'end'});
            writeFcn('om_hfun2', {'function y = om_hfun2(x)', ...
                    'y = x(1)^2 + x(2)*x(3) + sin(x(3));', 'end'});
            gx = @() adigatorCreateDerivInput([3 1],'x');
            outM = adigatorGenHesFile('om_hfun', {gx()}, ...
                struct('overwrite',1,'echo',0));                       % dense
            outN = adigatorGenHesFile('om_hfun2',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_output','csc'));    % csc
            rehash;

            xv = randn(3,1);
            [HM,~,FM]   = om_hfun_Hes(xv);
            [vals,~,FN] = om_hfun2_Hes(xv);
            tc.verifyEqual(FN, FM, 'AbsTol', 0);

            csc = outN.HessianCSC;
            tc.verifySize(vals, [csc.Nnz 1]);
            HM = full(HM);
            HS = full(adigatorCSCToSparse(csc, vals));
            tc.verifyEqual(HS, HM, 'AbsTol', 0);
            % patterns agree between the two modes
            tc.verifyEqual(full(adigatorCSCToSparse(csc, ones(csc.Nnz,1))) ~= 0, ...
                full(adigatorCSCToSparse(outM.HessianCSC, ones(outM.HessianCSC.Nnz,1))) ~= 0);
            % Verified-by (R25): the reconstructed Hessian matches finite differences
            g   = @(v) [2*v(1); v(3); v(2)+cos(v(3))];   % analytic gradient of the body
            Hfd = zeros(3); e = 1e-6;
            for j = 1:3
                ej = zeros(3,1); ej(j) = e;
                Hfd(:,j) = (g(xv+ej) - g(xv-ej))/(2*e);
            end
            tc.verifyEqual(HS, Hfd, 'AbsTol', 1e-5);
            % the csc wrapper performs no dense projection
            tc.verifyFalse(contains(fileread('om_hfun2_Hes.m'),'Hes = zeros'), ...
                'csc Hessian wrapper must not allocate a dense Hessian');
        end

        function hessianCscVectorFunction(tc)
            % #192: the m>1 VECTOR-function Hessian [m*n x n] csc path (the
            % (x1-1)*m+y row layout, B7 territory) - HessianCSC must reconstruct
            % the dense Hessian exactly.
            writeFcn('om_vh',  {'function y = om_vh(x)', ...
                    'y = [x(1)^2 + x(2)*x(3); x(2)^2*x(3)];', 'end'});
            writeFcn('om_vh2', {'function y = om_vh2(x)', ...
                    'y = [x(1)^2 + x(2)*x(3); x(2)^2*x(3)];', 'end'});
            gx = @() adigatorCreateDerivInput([3 1],'x');
            outM = adigatorGenHesFile('om_vh', {gx()}, ...
                struct('overwrite',1,'echo',0));
            outN = adigatorGenHesFile('om_vh2',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_output','csc'));
            rehash;

            xv = randn(3,1);
            HM   = full(om_vh_Hes(xv));   % dense [m*n x n] = [6 x 3]
            vals = om_vh2_Hes(xv);        % csc value vector
            tc.verifySize(HM, [6 3]);
            csc = outN.HessianCSC;
            tc.verifyEqual(csc.Size, [6 3]);
            tc.verifyEqual(full(adigatorCSCToSparse(csc, vals)), HM, 'AbsTol', 0);
            tc.verifyEqual(full(adigatorCSCToSparse(csc, ones(csc.Nnz,1))) ~= 0, ...
                full(adigatorCSCToSparse(outM.HessianCSC, ones(outM.HessianCSC.Nnz,1))) ~= 0);
        end

        function hessianCscMatrixOfScalar(tc)
            % B23 (silent-wrong-output): a MATRIX function of a SCALAR variable
            % (remapcase 2 in adigatorGenHesFile). HessianCSC.Size must be the
            % true [r c] output shape ([2 2] here), not the mutated ysize - the
            % pre-B23 code produced a wrong-shape column pattern.
            writeFcn('om_ms',  {'function y = om_ms(x)',  'y = [x^2, x^3; 2*x^2, 4*x];', 'end'});
            writeFcn('om_ms2', {'function y = om_ms2(x)', 'y = [x^2, x^3; 2*x^2, 4*x];', 'end'});
            gx = @() adigatorCreateDerivInput([1 1],'x');
            outM = adigatorGenHesFile('om_ms', {gx()}, ...
                struct('overwrite',1,'echo',0));                        % dense
            outN = adigatorGenHesFile('om_ms2',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_output','csc'));     % csc
            rehash;

            xv = 0.7;
            HM   = full(om_ms_Hes(xv));   % dense Hessian, same [2 2] shape as y
            vals = om_ms2_Hes(xv);        % csc value vector
            tc.verifySize(HM, [2 2]);
            csc = outN.HessianCSC;
            tc.verifyEqual(csc.Size, [2 2], ...
                'HessianCSC.Size must be the true output shape, not the mutated ysize (B23)');
            tc.verifyTrue(all(double(csc.RowIdx(:)) <= size(HM,1)), ...
                'RowIdx must index the true output rows (B23)');
            tc.verifyEqual(full(adigatorCSCToSparse(csc, vals)), HM, 'AbsTol', 0);
            tc.verifyEqual(full(adigatorCSCToSparse(csc, ones(csc.Nnz,1))) ~= 0, ...
                full(adigatorCSCToSparse(outM.HessianCSC, ones(outM.HessianCSC.Nnz,1))) ~= 0);
            % analytic entrywise second derivative of [x^2 x^3; 2x^2 4x]
            tc.verifyEqual(HM, [2 6*xv; 4 0], 'AbsTol', 1e-10);
        end

        function derOutputSelectsTopOrderOnly(tc)
            % v2.0 (#192, ADR-0030 / ADR-0022 decision b): der_output selects the
            % TOP-order output form only. On a Hessian file der_output='csc'
            % flips the Hessian (no dense 'Hes = zeros') but the companion
            % gradient wrapper is UNAFFECTED (still projects dense). The removed
            % jac_output alias and der_output='nonzeros' spelling both error.
            % structurally SPARSE gradient (d/dx2 == 0) so the matrix-mode Grd
            % companion projects via `Grd = zeros(n,1); Grd(...) = ...` - a
            % visible marker that it stayed in matrix form.
            writeFcn('om_ls', {'function y = om_ls(x)', ...
                    'y = x(1)^2 + sin(x(3));', 'end'});
            gx = @() adigatorCreateDerivInput([3 1],'x');
            optD = adigatorOptions('overwrite',1,'echo',0,'der_output','csc');
            adigatorGenHesFile('om_ls',{gx()}, optD);
            rehash;
            tc.verifyFalse(contains(fileread('om_ls_Hes.m'),'Hes = zeros'), ...
                'der_output=csc must flip the top-order Hessian to the csc form');
            tc.verifyTrue(contains(fileread('om_ls_Grd.m'),'Grd = zeros'), ...
                'the companion gradient must be UNAFFECTED by der_output (decision b)');
            % the removed pre-release spellings error with an actionable message
            tc.verifyError(@() adigatorOptions('jac_output','csc'), ...
                'adigator:jacOutputRemoved');
            tc.verifyError(@() adigatorOptions('der_output','nonzeros'), ...
                'adigator:derOutput:nonzerosRemoved');
        end

        function cscGradientConvention(tc)
            % scalar function (Grd convention): der_output='csc' returns the
            % gradient value vector; GradientCSC has the returned [n,1] shape and
            % reconstructs the dense gradient.
            writeFcn('om_sca', { ...
                'function y = om_sca(x)', ...
                'y = x(1)^2 + exp(x(3));', ...
                'end'});
            writeFcn('om_sca2', { ...
                'function y = om_sca2(x)', ...
                'y = x(1)^2 + exp(x(3));', ...
                'end'});
            gx = @() adigatorCreateDerivInput([3 1],'x');
            % the 'Grd' name appendix selects the gradient convention
            adigatorGenJacFile('om_sca',{gx()}, ...
                struct('overwrite',1,'echo',0),'Grd');
            outN = adigatorGenJacFile('om_sca2',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_output','csc'),'Grd');
            rehash;

            xv = randn(3,1);
            [GM,~] = om_sca_Grd(xv);
            [vals,~] = om_sca2_Grd(xv);
            csc = outN.GradientCSC;                    % scalar-fn gradient role
            tc.verifyEqual(csc.Size, [3 1]);           % returned [n,1] (D7)
            tc.verifyEqual(full(adigatorCSCToSparse(csc, vals)), full(GM), ...
                'AbsTol', 1e-14, 'RelTol', 1e-14);
            % d/dx2 is structurally zero: rows 1 and 3 present
            tc.verifyEqual(sort(double(csc.RowIdx(:))), [1;3]);
        end

        function jtvMatchesForwardJacobian(tc)
            % one generated file serves every runtime v; J'*v agrees with
            % the forward-mode Jacobian to round-off
            writeFcn('om_jtv', { ...
                'function y = om_jtv(x,A,c)', ...
                'r = A*x;', ...
                'y = sin(r) + c.*x;', ...
                'end'});
            gx = adigatorCreateDerivInput([3 1],'x');
            gA = adigatorCreateAuxInput([3 3]);
            gc = adigatorCreateAuxInput([3 1]);
            adigatorGenJacFile('om_jtv',{gx,gA,gc}, ...
                struct('overwrite',1,'echo',0));
            outV = adigatorGenJtVFile('om_jtv', ...
                {adigatorCreateDerivInput([3 1],'x'), ...
                adigatorCreateAuxInput([3 3]),adigatorCreateAuxInput([3 1])}, ...
                struct('overwrite',1,'echo',0));
            tc.verifyEqual(outV.JtVName,'om_jtv_JtV');
            rehash;

            rng(7);
            A = randn(3); c = randn(3,1); xv = randn(3,1);
            [JM,~] = om_jtv_Jac(xv,A,c);
            JM = full(JM);
            vset = randn(3,3);
            for trial = 1:3
                v = vset(:,trial);
                [jtv,yv] = om_jtv_JtV(xv,A,c,v);   % C-6: [Jtv, Fun]
                tc.verifyEqual(yv, sin(A*xv)+c.*xv, ...
                    'AbsTol', 1e-12, 'RelTol', 1e-12);
                tc.verifyEqual(jtv, JM.'*v, 'AbsTol', 1e-12, 'RelTol', 1e-12);
            end
            % the seed is guarded at runtime
            tc.verifyError(@() om_jtv_JtV(xv,A,c,randn(2,1)), ?MException);
        end

        function hessianWrapperHeadersLabelledByRole(tc)
            % M4 (#121): the header loop used Gfuncstr for BOTH wrappers (Hfuncstr
            % was built but never used), so the generated `_Hes` file's help
            % header advertised the gradient signature and "Gradient wrapper
            % file" label. Each wrapper must carry its own role's signature and
            % "Gradient/Hessian wrapper file" label.
            writeFcn('om_hdr', {'function y = om_hdr(x)', ...
                    'y = x(1)^2 + x(2)*x(3);', 'end'});
            gx = adigatorCreateDerivInput([3 1],'x');
            adigatorGenHesFile('om_hdr', {gx}, struct('overwrite',1,'echo',0));
            rehash;
            hes = fileread('om_hdr_Hes.m');
            tc.verifyTrue(contains(hes,'Hessian wrapper file generated by ADiGator'), ...
                'the _Hes header must say "Hessian wrapper file" (M4)');
            tc.verifyFalse(contains(hes,'Gradient wrapper file generated by ADiGator'), ...
                'the _Hes header must not carry the gradient label (M4)');
            tc.verifyNotEmpty(regexp(hes,'function \[Hes[^\]]*\] = om_hdr_Hes','once'), ...
                'the _Hes header must show the Hessian signature (M4)');
            grd = fileread('om_hdr_Grd.m');
            tc.verifyTrue(contains(grd,'Gradient wrapper file generated by ADiGator'), ...
                'the _Grd header must say "Gradient wrapper file" (M4)');
            tc.verifyNotEmpty(regexp(grd,'function \[Grd,?Fun\] = om_hdr_Grd','once'), ...
                'the _Grd header must show the gradient signature (M4)');

            % #200: adigatorGenJacFile's wrappers were the asymmetry here - the
            % Hessian generator labelled both of its wrappers by role and this
            % one labelled neither, so a _Jac/_Grd file said only "generated by
            % ADiGator" while its Hessian sibling said which role it played.
            % Restored, and pinned so it is not dropped again in a header edit.
            adigatorGenJacFile('om_hdr', {gx}, struct('overwrite',1,'echo',0));
            rehash;
            jac = fileread('om_hdr_Jac.m');
            tc.verifyTrue(contains(jac,'Jacobian wrapper file generated by ADiGator'), ...
                'the _Jac header must say "Jacobian wrapper file" (#200)');
            tc.verifyFalse(contains(jac,'Gradient wrapper file generated by ADiGator'), ...
                'the _Jac header must not claim the gradient role');
        end

        function optionGuards(tc)
            tc.verifyError(@() adigatorOptions('der_output','junk'), ...
                'adigator:derOutput');
            tc.verifyError(@() adigatorGenJtVFile(42,{}), ...
                'adigator:jtv:inputs');
        end
    end
end

function writeFcn(name, lines)
% write a fixture function file into the (temporary) working folder
fid = fopen([name '.m'], 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end
