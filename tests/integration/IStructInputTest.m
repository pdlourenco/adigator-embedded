classdef IStructInputTest < matlab.unittest.TestCase
    % IStructInputTest  Struct inputs through the Jac/Hes wrappers (issue #24).
    %
    % Verifies scope A ("structs that carry inputs"): the derivative variable
    % may be carried as a field of a scalar struct input, with auxiliary
    % fields used internally. Exercises
    %   - adigatorGenJacFile           (vector function, deriv field in.x)
    %   - adigatorGenHesFile classic   (flat in.x and nested in.vars.x)
    %   - adigatorGenDerFile_embedded  across embed_mode 'c'/'l'/'i'
    % against closed-form references, and checks cross-mode equality.
    %
    % Uses the committed examples/jacobians/structinput fixtures (structobj,
    % structobj_nested, structvecfun).
    %
    % Note: evaluating 'l'/'i' outputs in MATLAB requires the coder.*
    % namespace (MATLAB Coder); on runners without it the numeric cross-mode
    % check is skipped via assumption (the Coder job runs it fully), while
    % generation always runs.

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
            tc.applyFixture(PathFixture(fullfile(root,'examples','jacobians','structinput')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function jacobianFlatStruct(tc)
            % adigatorGenJacFile with the derivative variable as a struct
            % field (in.x); structvecfun is y = A*x + b, so J = A.
            n = 4; m = 3;
            rng(0); A = randn(m,n); b = randn(m,1); xv = randn(n,1);
            gin.x = adigatorCreateDerivInput([n 1],'x');
            gin.A = adigatorCreateAuxInput([m n]);
            gin.b = adigatorCreateAuxInput([m 1]);
            mdir = fullfile(pwd,'jac');
            adigatorGenJacFile('structvecfun',{gin}, ...
                struct('embed_mode','c','path',mdir,'echo',0));
            cu = cdInto(mdir); %#ok<NASGU>
            clear('structvecfun_Jac'); rehash;
            [J,Y] = structvecfun_Jac(struct('x',xv,'A',A,'b',b));
            clear cu
            tc.verifyEqual(J, A, 'AbsTol', 1e-12, 'Jacobian wrt struct field in.x');
            tc.verifyEqual(Y, A*xv + b, 'AbsTol', 1e-12, 'function value');
        end

        function hessianFlatAndNested(tc)
            % adigatorGenHesFile classic, flat (in.x) and nested (in.vars.x);
            % structobj is 1/2 x'Qx + c'x, so grad = Qx + c, hess = Q.
            n = 4;
            rng(1); Q = randn(n); Q = Q + Q.'; c = randn(n,1); xv = randn(n,1);
            Gexp = Q*xv + c; Hexp = Q;

            % flat
            gin.x = adigatorCreateDerivInput([n 1],'x');
            gin.Q = adigatorCreateAuxInput([n n]);
            gin.c = adigatorCreateAuxInput([n 1]);
            fdir = fullfile(pwd,'hesflat');
            adigatorGenHesFile('structobj',{gin}, ...
                struct('embed_mode','c','path',fdir,'echo',0));
            cu = cdInto(fdir); %#ok<NASGU>
            clear('structobj_Hes'); rehash;
            [H,G] = structobj_Hes(struct('x',xv,'Q',Q,'c',c));
            clear cu
            tc.verifyEqual(G, Gexp, 'AbsTol', 1e-12, 'flat gradient');
            tc.verifyEqual(H, Hexp, 'AbsTol', 1e-12, 'flat Hessian');

            % nested
            gin2.vars.x = adigatorCreateDerivInput([n 1],'x');
            gin2.par.Q  = adigatorCreateAuxInput([n n]);
            gin2.par.c  = adigatorCreateAuxInput([n 1]);
            ndir = fullfile(pwd,'hesnest');
            adigatorGenHesFile('structobj_nested',{gin2}, ...
                struct('embed_mode','c','path',ndir,'echo',0));
            cu2 = cdInto(ndir); %#ok<NASGU>
            clear('structobj_nested_Hes'); rehash;
            innest.vars.x = xv; innest.par.Q = Q; innest.par.c = c;
            [Hn,Gn] = structobj_nested_Hes(innest);
            clear cu2
            tc.verifyEqual(Gn, Gexp, 'AbsTol', 1e-12, 'nested gradient');
            tc.verifyEqual(Hn, Hexp, 'AbsTol', 1e-12, 'nested Hessian');
        end

        function embedModesStructInput(tc)
            % adigatorGenDerFile_embedded Hessian of a struct-input objective
            % across 'c'/'l'/'i'; cross-mode equal and matches the analytic.
            n = 4;
            rng(2); Q = randn(n); Q = Q + Q.'; c = randn(n,1); xv = randn(n,1);
            Gexp = Q*xv + c; Hexp = Q;
            inv = struct('x',xv,'Q',Q,'c',c);

            modes = {'c','l','i'};
            base = pwd; modeDir = struct();
            for k = 1:numel(modes)
                mode = modes{k};
                mdir = fullfile(base,['mode_',mode]);
                modeDir.(mode) = mdir;
                gin = struct();
                gin.x = adigatorCreateDerivInput([n 1],'x');
                gin.Q = adigatorCreateAuxInput([n n]);
                gin.c = adigatorCreateAuxInput([n 1]);
                adigatorGenDerFile_embedded('hessian','structobj',{gin}, ...
                    struct('embed_mode',mode,'path',mdir,'echo',0));
                tc.assertTrue(isfile(fullfile(mdir,'structobj_Hes.m')), ...
                    sprintf('mode %s: wrapper not generated', mode));
            end

            H = struct(); G = struct();
            for k = 1:numel(modes)
                mode = modes{k};
                cu = cdInto(modeDir.(mode)); %#ok<NASGU>
                clear('structobj_Hes'); rehash;
                if strcmp(mode,'c')
                    clear('global','ADiGator_structobj_ADiGatorHes', ...
                        'ADiGator_structobj_ADiGatorGrd');
                end
                try
                    [H.(mode), G.(mode)] = structobj_Hes(inv);
                catch e
                    if strcmp(mode,'c'); rethrow(e); end
                    if strcmp(e.identifier,'MATLAB:UndefinedFunction') && ...
                            contains(e.message,'coder.')
                        tc.assumeFail(sprintf(['mode %s needs the coder.* ', ...
                            'namespace (MATLAB Coder) to run in MATLAB; ', ...
                            'skipping numeric cross-mode check: %s'], mode, e.message));
                    end
                    rethrow(e);
                end
                clear cu
            end

            for k = 1:numel(modes)
                mode = modes{k};
                tc.verifyEqual(G.(mode), Gexp, 'AbsTol', 1e-12, ...
                    sprintf('mode %s: gradient differs from analytic', mode));
                tc.verifyEqual(H.(mode), Hexp, 'AbsTol', 1e-12, ...
                    sprintf('mode %s: Hessian differs from analytic', mode));
            end
            tc.verifyEqual(G.l, G.c, 'AbsTol', 0, 'coderload vs classic gradient');
            tc.verifyEqual(G.i, G.c, 'AbsTol', 0, 'inline vs classic gradient');
            tc.verifyEqual(H.l, H.c, 'AbsTol', 0, 'coderload vs classic Hessian');
            tc.verifyEqual(H.i, H.c, 'AbsTol', 0, 'inline vs classic Hessian');
        end
    end
end

function cleanupObj = cdInto(d)
old = cd(d);
cleanupObj = onCleanup(@() cd(old));
end
