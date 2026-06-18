classdef IAllocationTest < matlab.unittest.TestCase
    % IAllocationTest  Roadmap R1 acceptance test (issues #6 Tier 0, #11
    % options 1-2): the allocation-over-time example's product fold —
    % ONE vectorized derivative file, generated once, serves multiple
    % (N actuators, K time steps) shapes; the assembled gradient and
    % moment Jacobian match analytic values and central differences.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
            tc.applyFixture(PathFixture(fullfile(root, ...
                'examples','optimization','vectorized','allocation')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function oneFileServesMultipleShapes(tc)
            % generate ONCE with a free (vectorized) product dimension
            gU = adigatorCreateDerivInput([Inf 1], ...
                struct('vodname','U','vodsize',[Inf 1],'nzlocs',[1 1]));
            gP = adigatorCreateAuxInput([Inf 3]);
            adigator('alloc_terms',{gU,gP},'alloc_terms_dU', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            m = 3;
            shapes = [4 5; 7 3]; % deliberately different N and K
            for s = 1:size(shapes,1)
                N = shapes(s,1); K = shapes(s,2); NK = N*K;
                rng(s); % deterministic, distinct per shape
                B   = randn(m,N);
                tau = randn(m,K);
                w   = 0.5 + rand(NK,1);
                q   = randn(NK,1);
                alf = 0.1*rand(NK,1);
                p   = [w q alf];
                u   = randn(NK,1);

                [Jcost,gJ,G,JG] = alloc_assemble(u,p,B,tau);

                % values against direct computation
                tc.verifyEqual(Jcost, sum(0.5*w.*u.^2 + q.*u), ...
                    'AbsTol', 1e-12, 'RelTol', 1e-12);
                h = u + alf.*u.^3;
                tc.verifyEqual(G, reshape(B*reshape(h,N,K) - tau, [], 1), ...
                    'AbsTol', 1e-12, 'RelTol', 1e-12);

                % derivatives against analytic forms
                tc.verifySize(gJ, [NK 1]);
                tc.verifyEqual(gJ, w.*u + q, 'AbsTol', 1e-12, 'RelTol', 1e-12, ...
                    sprintf('shape %d: assembled gradient wrong', s));
                tc.verifySize(JG, [m*K, NK]);
                hp = 1 + 3*alf.*u.^2;
                for i = [1, NK] % spot columns: first and last pair
                    a = mod(i-1, N) + 1;
                    k = floor((i-1)/N) + 1;
                    coltrue = zeros(m*K,1);
                    coltrue((k-1)*m + (1:m)) = B(:,a)*hp(i);
                    tc.verifyEqual(full(JG(:,i)), coltrue, ...
                        'AbsTol', 1e-12, 'RelTol', 1e-12);
                end

                % and against central finite differences (full matrices)
                costfun = @(uu) sum(0.5*w.*uu.^2 + q.*uu);
                confun  = @(uu) reshape(B*reshape(uu + alf.*uu.^3, N, K) - tau, [], 1);
                ee = 1e-6;
                gfd  = zeros(NK,1);
                Jgfd = zeros(m*K,NK);
                for i = 1:NK
                    e = zeros(NK,1); e(i) = ee;
                    gfd(i)    = (costfun(u+e) - costfun(u-e))/(2*ee);
                    Jgfd(:,i) = (confun(u+e)  - confun(u-e))/(2*ee);
                end
                tc.verifyEqual(gJ, gfd, 'AbsTol', 1e-5, 'RelTol', 1e-5);
                tc.verifyEqual(full(JG), Jgfd, 'AbsTol', 1e-5, 'RelTol', 1e-5);
            end
        end

        function maskedActuatorIsExactZero(tc)
            % failure masking with the product fold: zeroing the failed
            % actuator's cost weights and B column removes it exactly
            % (interim answer until roadmap R3 / issue #6 Tier 1)
            gU = adigatorCreateDerivInput([Inf 1], ...
                struct('vodname','U','vodsize',[Inf 1],'nzlocs',[1 1]));
            gP = adigatorCreateAuxInput([Inf 3]);
            adigator('alloc_terms',{gU,gP},'alloc_terms_dU', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            m = 2; N = 4; K = 3; NK = N*K;
            rng(0);
            B = randn(m,N); tau = randn(m,K);
            p = [0.5+rand(NK,1), randn(NK,1), 0.1*rand(NK,1)];
            u = randn(NK,1);

            failed = 2; % actuator index to mask
            mask = mod((1:NK).'-1, N) + 1 == failed;
            Bm = B;  Bm(:,failed) = 0;
            pm = p;  pm(mask,1:2) = 0;

            [Jm,gm,~,JGm] = alloc_assemble(u,pm,Bm,tau);
            % masked pairs contribute nothing to cost or moments
            tc.verifyEqual(gm(mask), zeros(nnz(mask),1), 'AbsTol', 0);
            tc.verifyEqual(full(JGm(:,mask)), zeros(m*K,nnz(mask)), 'AbsTol', 0);
            % and the rest agrees with an (N-1)-actuator problem
            keep = ~mask;
            Bk = B(:, setdiff(1:N,failed));
            [Jk,gk,~,JGk] = alloc_assemble(u(keep), p(keep,:), Bk, tau);
            tc.verifyEqual(Jm, Jk, 'AbsTol', 1e-12, 'RelTol', 1e-12);
            tc.verifyEqual(gm(keep), gk, 'AbsTol', 1e-12);
            tc.verifyEqual(full(JGm(:,keep)), full(JGk), 'AbsTol', 1e-12);
        end
    end
end
