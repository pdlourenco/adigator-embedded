classdef IOutputModesTest < matlab.unittest.TestCase
    % IOutputModesTest  Roadmap R5 acceptance test (ANALYSIS.md 2.3): the
    % jac_output='nonzeros' wrapper mode - nonzero vector returned in the
    % exported constant pattern order, no per-call dense projection - and
    % the J'*v product file built on the R4 reverse engine.

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
        function nonzerosJacobianMode(tc)
            % structurally sparse Jacobian: the nonzeros wrapper returns
            % exactly the pattern values, in output.JacobianLocs order
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
                struct('overwrite',1,'echo',0,'jac_output','nonzeros'));
            rehash;

            xv = randn(3,1);
            [JM,FM] = om_fun_Jac(xv);
            [vals,FN] = om_fun2_Jac(xv);
            tc.verifyEqual(FN, FM, 'AbsTol', 0);

            locs = outN.JacobianLocs;
            tc.verifySize(vals, [size(locs,1) 1]);
            JM = full(JM);
            tc.verifyEqual(vals, ...
                JM(sub2ind(size(JM),locs(:,1),locs(:,2))), ...
                'AbsTol', 1e-14, 'RelTol', 1e-14);
            % the patterns agree between the two modes
            tc.verifyEqual(full(outN.JacobianStructure), ...
                full(outM.JacobianStructure));
            % and scattering the values reproduces the full Jacobian
            JS = zeros(size(JM));
            JS(sub2ind(size(JM),locs(:,1),locs(:,2))) = vals;
            tc.verifyEqual(JS, JM, 'AbsTol', 0);

            % the nonzeros wrapper performs no dense projection
            wtxt = fileread('om_fun2_Jac.m');
            tc.verifyFalse(contains(wtxt,'Jac = zeros'), ...
                'nonzeros wrapper must not allocate a dense Jacobian');
        end

        function hessianNonzerosMode(tc)
            % #84/R25 (ADR-0022): der_output='nonzeros' Hessian returns the
            % nonzero vector in output.HessianLocs order; scattering it via the
            % exported pattern reproduces the dense Hessian, cross-checked vs FD
            % (the Verified-by test).
            writeFcn('om_hfun',  {'function y = om_hfun(x)', ...
                    'y = x(1)^2 + x(2)*x(3) + sin(x(3));', 'end'});
            writeFcn('om_hfun2', {'function y = om_hfun2(x)', ...
                    'y = x(1)^2 + x(2)*x(3) + sin(x(3));', 'end'});
            gx = @() adigatorCreateDerivInput([3 1],'x');
            outM = adigatorGenHesFile('om_hfun', {gx()}, ...
                struct('overwrite',1,'echo',0));                       % dense
            outN = adigatorGenHesFile('om_hfun2',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_output','nonzeros'));% nonzeros
            rehash;

            xv = randn(3,1);
            [HM,~,FM]   = om_hfun_Hes(xv);
            [vals,~,FN] = om_hfun2_Hes(xv);
            tc.verifyEqual(FN, FM, 'AbsTol', 0);

            locs = outN.HessianLocs;
            tc.verifySize(vals, [size(locs,1) 1]);
            HM = full(HM);
            tc.verifyEqual(vals, HM(sub2ind(size(HM),locs(:,1),locs(:,2))), ...
                'AbsTol', 1e-13, 'RelTol', 1e-13);
            % patterns agree between the two modes
            tc.verifyEqual(full(outN.HessianStructure), full(outM.HessianStructure));
            % scattering the nonzeros via HessianLocs reproduces the dense Hessian
            HS = zeros(size(HM));
            HS(sub2ind(size(HM),locs(:,1),locs(:,2))) = vals;
            tc.verifyEqual(HS, HM, 'AbsTol', 0);
            % Verified-by (R25): the reconstructed Hessian matches finite differences
            g   = @(v) [2*v(1); v(3); v(2)+cos(v(3))];   % analytic gradient of the body
            Hfd = zeros(3); e = 1e-6;
            for j = 1:3
                ej = zeros(3,1); ej(j) = e;
                Hfd(:,j) = (g(xv+ej) - g(xv-ej))/(2*e);
            end
            tc.verifyEqual(HS, Hfd, 'AbsTol', 1e-5);
            % the nonzeros wrapper performs no dense projection
            tc.verifyFalse(contains(fileread('om_hfun2_Hes.m'),'Hes = zeros'), ...
                'nonzeros Hessian wrapper must not allocate a dense Hessian');
        end

        function hessianNonzerosVectorFunction(tc)
            % #84/R25: the m>1 VECTOR-function Hessian [m*n x n] nonzeros path
            % (the (x1-1)*m+y row layout, B7 territory) - HessianLocs must
            % reconstruct the dense Hessian exactly.
            writeFcn('om_vh',  {'function y = om_vh(x)', ...
                    'y = [x(1)^2 + x(2)*x(3); x(2)^2*x(3)];', 'end'});
            writeFcn('om_vh2', {'function y = om_vh2(x)', ...
                    'y = [x(1)^2 + x(2)*x(3); x(2)^2*x(3)];', 'end'});
            gx = @() adigatorCreateDerivInput([3 1],'x');
            outM = adigatorGenHesFile('om_vh', {gx()}, ...
                struct('overwrite',1,'echo',0));
            outN = adigatorGenHesFile('om_vh2',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_output','nonzeros'));
            rehash;

            xv = randn(3,1);
            HM   = full(om_vh_Hes(xv));   % dense [m*n x n] = [6 x 3]
            vals = om_vh2_Hes(xv);        % nonzero vector
            tc.verifySize(HM, [6 3]);
            locs = outN.HessianLocs;
            tc.verifyEqual(vals, HM(sub2ind(size(HM),locs(:,1),locs(:,2))), ...
                'AbsTol', 1e-13, 'RelTol', 1e-13);
            HS = zeros(size(HM));
            HS(sub2ind(size(HM),locs(:,1),locs(:,2))) = vals;
            tc.verifyEqual(HS, HM, 'AbsTol', 0);            % reconstruct dense
            tc.verifyEqual(full(outN.HessianStructure), full(outM.HessianStructure));
        end

        function hessianNonzerosMatrixOfScalar(tc)
            % B23 (silent-wrong-output): a MATRIX function of a SCALAR variable
            % (remapcase 2 in adigatorGenHesFile). The dense wrapper is correct
            % (built pre-mutation), but HessianStructure/HessianLocs were built
            % from the *mutated* ysize -- the r*c linear indices overflowed the
            % r-row column, so the exported pattern was a wrong-shape column
            % ([3 1] here) and der_output='nonzeros' reconstructed a silently
            % wrong Hessian (sub2ind even threw). HessianLocs must index the
            % true [r c] output shape.
            writeFcn('om_ms',  {'function y = om_ms(x)',  'y = [x^2, x^3; 2*x^2, 4*x];', 'end'});
            writeFcn('om_ms2', {'function y = om_ms2(x)', 'y = [x^2, x^3; 2*x^2, 4*x];', 'end'});
            gx = @() adigatorCreateDerivInput([1 1],'x');
            outM = adigatorGenHesFile('om_ms', {gx()}, ...
                struct('overwrite',1,'echo',0));                        % dense
            outN = adigatorGenHesFile('om_ms2',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_output','nonzeros'));% nonzeros
            rehash;

            xv = 0.7;
            HM   = full(om_ms_Hes(xv));   % dense Hessian, same [2 2] shape as y
            vals = om_ms2_Hes(xv);        % nonzero vector
            tc.verifySize(HM, [2 2]);
            locs = outN.HessianLocs;
            % pre-fix locs held (row 3, col 1) into a 2x2 -> out of range
            tc.verifyTrue(all(locs(:,1) <= size(HM,1) & locs(:,2) <= size(HM,2)), ...
                'HessianLocs must index the true output shape, not the mutated ysize (B23)');
            tc.verifyEqual(vals, HM(sub2ind(size(HM),locs(:,1),locs(:,2))), ...
                'AbsTol', 1e-13, 'RelTol', 1e-13);
            HS = zeros(size(HM));
            HS(sub2ind(size(HM),locs(:,1),locs(:,2))) = vals;
            tc.verifyEqual(HS, HM, 'AbsTol', 0);            % reconstruct dense
            tc.verifyEqual(full(outN.HessianStructure), full(outM.HessianStructure));
            % analytic entrywise second derivative of [x^2 x^3; 2x^2 4x]
            tc.verifyEqual(HM, [2 6*xv; 4 0], 'AbsTol', 1e-10);
        end

        function jacOutputDoesNotFlipHessian(tc)
            % #84/R25 (ADR-0022, decision b): jac_output is a level-1 alias and
            % must NOT flip the Hessian's form - even through adigatorOptions (the
            % primary API, whose cross-sync was removed). jac_output='nonzeros'
            % gives a nonzeros first derivative but a DENSE Hessian; only
            % der_output='nonzeros' flips the Hessian.
            writeFcn('om_ls', {'function y = om_ls(x)', ...
                    'y = x(1)^2 + x(2)*x(3);', 'end'});
            gx = @() adigatorCreateDerivInput([3 1],'x');
            optJ = adigatorOptions('overwrite',1,'echo',0,'jac_output','nonzeros');
            adigatorGenJacFile('om_ls',{gx()}, optJ);
            adigatorGenHesFile('om_ls',{gx()}, optJ);
            rehash;
            tc.verifyFalse(contains(fileread('om_ls_Jac.m'),'Jac = zeros'), ...
                'jac_output=nonzeros must give a nonzeros first derivative');
            tc.verifyTrue(contains(fileread('om_ls_Hes.m'),'Hes = zeros'), ...
                'jac_output (level-1 alias) must NOT flip the Hessian to nonzeros');
            % der_output DOES reach the Hessian
            optD = adigatorOptions('overwrite',1,'echo',0,'der_output','nonzeros');
            adigatorGenHesFile('om_ls',{gx()}, optD); rehash;
            tc.verifyFalse(contains(fileread('om_ls_Hes.m'),'Hes = zeros'), ...
                'der_output=nonzeros must flip the Hessian to the nonzeros form');
        end

        function nonzerosGradientConvention(tc)
            % scalar function (Grd convention): values match the gradient
            % nonzeros in pattern order
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
                struct('overwrite',1,'echo',0,'jac_output','nonzeros'),'Grd');
            rehash;

            xv = randn(3,1);
            [GM,~] = om_sca_Grd(xv);
            [vals,~] = om_sca2_Grd(xv);
            % scalar function: the variable index is the column entry
            locs = outN.JacobianLocs;
            tc.verifyEqual(vals, GM(locs(:,2)), ...
                'AbsTol', 1e-14, 'RelTol', 1e-14);
            tc.verifyEqual(sort(locs(:,2)), [1;3]); % d/dx2 structurally zero
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
        end

        function optionGuards(tc)
            tc.verifyError(@() adigatorOptions('jac_output','junk'), ...
                'adigator:jacOutput');
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
