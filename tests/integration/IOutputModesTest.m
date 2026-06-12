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
            adigatorGenJacFile('om_sca',{gx()}, ...
                struct('overwrite',1,'echo',0));
            outN = adigatorGenJacFile('om_sca2',{gx()}, ...
                struct('overwrite',1,'echo',0,'jac_output','nonzeros'));
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
                [yv,jtv] = om_jtv_JtV(xv,A,c,v);
                tc.verifyEqual(yv, sin(A*xv)+c.*xv, ...
                    'AbsTol', 1e-12, 'RelTol', 1e-12);
                tc.verifyEqual(jtv, JM.'*v, 'AbsTol', 1e-12, 'RelTol', 1e-12);
            end
            % the seed is guarded at runtime
            tc.verifyError(@() om_jtv_JtV(xv,A,c,randn(2,1)), ?MException);
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
