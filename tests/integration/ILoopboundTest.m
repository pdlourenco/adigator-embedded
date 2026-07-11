classdef ILoopboundTest < matlab.unittest.TestCase
    % ILoopboundTest  Roadmap R3 acceptance test (issue #6 Tier 1): the
    % 'loopbound' option - one derivative file generated at the maximum
    % trip count serves any runtime trip count n <= max, with exact
    % agreement on the executed prefix and exact structural zeros beyond
    % it; the assert guard, the padded-program semantics of unsafe
    % post-loop ops, nested runtime bounds (composed with R2's N-D
    % parameters), and the option guards.

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
        function runtimeBoundMatchesDirectGeneration(tc)
            % the Tier-1 contract: the Nmax file evaluated at n agrees
            % exactly with a file generated directly at n on the first-n
            % entries, and is structurally zero beyond them
            writeFcn('lb_fun', { ...
                'function [J,v] = lb_fun(x,p,N)', ...
                'v = zeros(N,1);', ...
                'J = 0;', ...
                'for a = 1:N', ...
                '  ua   = x(a);', ...
                '  v(a) = p(a,1)*ua^2 + p(a,2)*ua;', ...
                '  J    = J + v(a);', ...
                'end', ...
                'end'});
            Nmax = 6; n = 4;
            gx = adigatorCreateDerivInput([Nmax 1],'x');
            gp = adigatorCreateAuxInput([Nmax 2]);
            adigator('lb_fun',{gx,gp,Nmax},'lb_fun_dmax', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N'));
            gx = adigatorCreateDerivInput([n 1],'x');
            gp = adigatorCreateAuxInput([n 2]);
            adigator('lb_fun',{gx,gp,n},'lb_fun_dn', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            % the generated text really has a runtime bound and a guard
            gentext = fileread('lb_fun_dmax.m');
            tc.verifyTrue(contains(gentext,'= 1:N'), ...
                'generated loop header should use the runtime bound N');
            tc.verifyTrue(contains(gentext,'assert(N <= 6)'), ...
                'generated file should guard N <= Nmax');

            rng(1);
            p  = [0.5 + rand(Nmax,1), randn(Nmax,1)];
            xf = randn(Nmax,1); % entries n+1:Nmax are junk that must not leak
            x.f = xf; x.dx = ones(Nmax,1);
            [Jm,vm] = lb_fun_dmax(x,p,n);
            xn.f = xf(1:n); xn.dx = ones(n,1);
            [Jn,vn] = lb_fun_dn(xn,p(1:n,:),n);

            % values: exact agreement on the executed prefix; anything
            % beyond is structurally zero. v was allocated as zeros(N,1),
            % and generated code references the bound parameter BY NAME,
            % so its function part may come out runtime-sized (no padded
            % tail at all) rather than max-sized
            tc.verifyEqual(Jm.f, Jn.f, 'AbsTol', 0);
            tc.verifyEqual(vm.f(1:n), vn.f, 'AbsTol', 0);
            if numel(vm.f) == Nmax
                tc.verifyEqual(vm.f(n+1:Nmax), zeros(Nmax-n,1), 'AbsTol', 0);
            else
                tc.verifySize(vm.f, [n 1]);
            end

            % gradients of J via the location convention
            gm = zeros(Nmax,1); gm(Jm.dx_location(:,end)) = Jm.dx;
            gn = zeros(n,1);    gn(Jn.dx_location(:,end)) = Jn.dx;
            tc.verifyEqual(gm(1:n), gn, 'AbsTol', 0);
            tc.verifyEqual(gm(n+1:Nmax), zeros(Nmax-n,1), 'AbsTol', 0);
            tc.verifyEqual(gm(1:n), 2*p(1:n,1).*xf(1:n) + p(1:n,2), ...
                'AbsTol', 1e-12, 'RelTol', 1e-12);

            % Jacobian of v: first-n rows agree, padded rows all zero
            Jvm = full(sparse(vm.dx_location(:,1), vm.dx_location(:,2), ...
                vm.dx, Nmax, Nmax));
            Jvn = full(sparse(vn.dx_location(:,1), vn.dx_location(:,2), ...
                vn.dx, n, n));
            tc.verifyEqual(Jvm(1:n,1:n), Jvn, 'AbsTol', 0);
            Jvm(1:n,1:n) = 0;
            tc.verifyEqual(Jvm, zeros(Nmax), 'AbsTol', 0);

            % and at full trip count the file behaves like a fixed one
            [Jf,~] = lb_fun_dmax(x,p,Nmax);
            tc.verifyEqual(Jf.f, sum(p(:,1).*xf.^2 + p(:,2).*xf), ...
                'AbsTol', 1e-12, 'RelTol', 1e-12);
        end

        function assertRejectsOverMax(tc)
            writeFcn('lb_guard', { ...
                'function J = lb_guard(x,N)', ...
                'J = 0;', ...
                'for a = 1:N', ...
                '  J = J + a*x(a)^2;', ...
                'end', ...
                'end'});
            Nmax = 5;
            gx = adigatorCreateDerivInput([Nmax 1],'x');
            adigator('lb_guard',{gx,Nmax},'lb_guard_dx', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N'));
            rehash;
            x.f = randn(Nmax,1); x.dx = ones(Nmax,1);
            tc.verifyError(@() lb_guard_dx(x,Nmax+1), ?MException);
        end

        function paddingUnsafePostLoopOpPinned(tc)
            % the documented contract: a post-loop op that sees the padded
            % tail of a FIXED-size buffer (literal analyzed size, not
            % derived from the bound parameter) computes the Nmax-padded
            % value, NOT the true n-sized value
            writeFcn('lb_mean', { ...
                'function m = lb_mean(x,N)', ...
                'v = zeros(6,1);', ...
                'for a = 1:N', ...
                '  v(a) = x(a)^2;', ...
                'end', ...
                'm = sum(v)/length(v);', ...
                'end'});
            Nmax = 6; n = 3;
            gx = adigatorCreateDerivInput([Nmax 1],'x');
            adigator('lb_mean',{gx,Nmax},'lb_mean_dx', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N'));
            rehash;
            rng(2);
            xf = randn(Nmax,1);
            x.f = xf; x.dx = ones(Nmax,1);
            m = lb_mean_dx(x,n);
            % padded semantics: sum over the executed prefix, divided by Nmax
            tc.verifyEqual(m.f, sum(xf(1:n).^2)/Nmax, ...
                'AbsTol', 1e-12, 'RelTol', 1e-12);
            tc.verifyNotEqual(m.f, mean(xf(1:n).^2));
        end

        function nestedRuntimeBoundsWithNDParam(tc)
            % the headline composition (issues #6 + #11): N actuators x K
            % time steps, both free at runtime from one file, with the
            % effectiveness matrices in an R2 N-D declared parameter
            % sliced by both loop counters
            writeFcn('lb_nest', { ...
                'function y = lb_nest(x,B,N,K)', ...
                'y = zeros(3,1);', ...
                'for k = 1:K', ...
                '  for a = 1:N', ...
                '    y = y + B(:,:,a,k)*(x.^2)*(a + 2*k);', ...
                '  end', ...
                'end', ...
                'end'});
            Nmax = 3; Kmax = 4; nx = 2;
            gx = adigatorCreateDerivInput([nx 1],'x');
            gB = adigatorCreateAuxInput([3 nx Nmax Kmax]);
            adigator('lb_nest',{gx,gB,Nmax,Kmax},'lb_nest_dx', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound',{'N','K'}));
            rehash;

            rng(3);
            B = randn(3,nx,Nmax,Kmax);
            xf = randn(nx,1);
            x.f = xf; x.dx = ones(nx,1);
            for shape = [Nmax Kmax; 2 3; 1 2].'
                n = shape(1); kk = shape(2);
                y = lb_nest_dx(x,B,n,kk);
                yt = zeros(3,1); Jt = zeros(3,nx);
                for k = 1:kk
                    for a = 1:n
                        yt = yt + B(:,:,a,k)*(xf.^2)*(a + 2*k);
                        Jt = Jt + B(:,:,a,k)*diag(2*xf)*(a + 2*k);
                    end
                end
                tc.verifyEqual(y.f, yt, 'AbsTol', 1e-12, 'RelTol', 1e-12, ...
                    sprintf('values wrong for n=%d, k=%d', n, kk));
                J = full(sparse(y.dx_location(:,1), y.dx_location(:,2), ...
                    y.dx, 3, nx));
                tc.verifyEqual(J, Jt, 'AbsTol', 1e-12, 'RelTol', 1e-12, ...
                    sprintf('Jacobian wrong for n=%d, k=%d', n, kk));
            end
        end

        function optionGuards(tc)
            writeFcn('lb_opt', { ...
                'function J = lb_opt(x,N)', ...
                'J = 0;', ...
                'for a = 1:N', ...
                '  J = J + x(a)^2;', ...
                'end', ...
                'end'});
            gx = @() adigatorCreateDerivInput([4 1],'x');

            % loopbound + unroll is rejected
            tc.verifyError(@() adigator('lb_opt',{gx(),4},'lb_opt_d1', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N','unroll',1)), ...
                'adigator:loopbound:unroll');
            % the named input must exist
            tc.verifyError(@() adigator('lb_opt',{gx(),4},'lb_opt_d2', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','M')), ...
                'adigator:loopbound:name');
            % the named input must be a plain numeric integer scalar
            tc.verifyError(@() adigator('lb_opt', ...
                {gx(), adigatorCreateAuxInput([1 1])}, 'lb_opt_d3', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N')), ...
                'adigator:loopbound:value');
            % the option value must name inputs
            tc.verifyError(@() adigatorOptions('loopbound',42), ...
                'adigator:loopbound:option');
        end
    end

    methods (Test)
        % B27 (#162) regression guards - the exit-union fix for inner
        % runtime-bound loops (formerly a KnownIssue tripwire, now self-healed).
        function nestedRuntimeBoundInnerExitDerivative(tc)
            % B27 (#162): an INNER runtime-bound loop whose exit variable's
            % DERIVATIVE location depends on the trip count -- a gather by the
            % loop counter read after the loop -- used to be printed with the
            % final-iteration object (a baked `y.dx = y.dx(Nmax)` gather) rather
            % than the loop-overmap union, because the exit-union was applied to
            % OUTERMOST loops only. So the Nmax file run at n < Nmax gave the
            % correct VALUE but a silently ZEROED derivative. Fixed by computing
            % the inner loop's exit set in adigatorAssignOvermapScheme
            % (INNEREXITCOUNTS) and unioning it in adigatorForIterEnd. This is
            % now a hard regression guard, swept over truncation points (the
            % single (2,2) point never truncates the OUTER loop). Settles #120 as
            % a wrong-derivative bug (reading 2), not a doc drift.
            writeFcn('lb_inner_exit', { ...
                'function y = lb_inner_exit(x,N,K)', ...
                'y = 0;', ...
                'for k = 1:K', ...
                '  w = 0;', ...
                '  for a = 1:N', ...       % inner runtime-bound loop
                '    w = x(a)^2;', ...       % exit deriv location = column a = N
                '  end', ...
                '  y = y + w;', ...          % y = K*x(N)^2 -> dy/dx nonzero at col N
                'end', ...
                'end'});
            Nmax = 4; Kmax = 2;
            gx = adigatorCreateDerivInput([Nmax 1],'x');
            adigator('lb_inner_exit',{gx,Nmax,Kmax},'lb_inner_exit_dx', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound',{'N','K'}));
            rehash;
            rng(11); xf = randn(Nmax,1);

            % (N,K): no truncation, inner-only, both, outer-only
            for NK = [Nmax Kmax; 2 2; 2 1; 1 2].'
                N = NK(1); K = NK(2);
                x = struct('f',xf,'dx',ones(Nmax,1));
                y = lb_inner_exit_dx(x, N, K);
                tc.verifyEqual(y.f, K*xf(N)^2, 'AbsTol', 1e-12, 'RelTol', 1e-12, ...
                    sprintf('value at (N,K)=(%d,%d)', N, K));
                g = zeros(1, Nmax);
                if isfield(y,'dx_location') && ~isempty(y.dx_location)
                    g(y.dx_location(:,end)) = y.dx;
                end
                gExp = zeros(1, Nmax); gExp(N) = 2*K*xf(N);
                tc.verifyEqual(g, gExp, 'AbsTol', 1e-10, sprintf(['inner ', ...
                    'runtime-bound loop exit derivative must match the n-sized ', ...
                    'program at (N,K)=(%d,%d)'], N, K));
            end
        end

        function innerRuntimeBoundUnderFixedOuter(tc)
            % B27 (#162) hardening: a runtime-bound inner loop under a FIXED-bound
            % outer loop. The outer loop is not runtime-bound, so its own exit
            % union can't accidentally mask the inner exit-derivative bug -- this
            % isolates the inner exit-union the fix adds.
            writeFcn('lb_fixouter', { ...
                'function y = lb_fixouter(x,N)', ...
                'y = 0;', ...
                'for k = 1:3', ...          % FIXED outer
                '  w = 0;', ...
                '  for a = 1:N', ...        % runtime-bound inner
                '    w = x(a)^2;', ...
                '  end', ...
                '  y = y + w;', ...          % y = 3*x(N)^2
                'end', ...
                'end'});
            Nmax = 5;
            gx = adigatorCreateDerivInput([Nmax 1],'x');
            adigator('lb_fixouter',{gx,Nmax},'lb_fixouter_dx', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound',{'N'}));
            rehash;
            rng(7); xf = randn(Nmax,1);
            for N = [Nmax 3 1]
                x = struct('f',xf,'dx',ones(Nmax,1));
                y = lb_fixouter_dx(x, N);
                tc.verifyEqual(y.f, 3*xf(N)^2, 'AbsTol', 1e-12, 'RelTol', 1e-12, ...
                    sprintf('value N=%d', N));
                g = zeros(1, Nmax);
                if isfield(y,'dx_location') && ~isempty(y.dx_location)
                    g(y.dx_location(:,end)) = y.dx;
                end
                gExp = zeros(1, Nmax); gExp(N) = 2*3*xf(N);
                tc.verifyEqual(g, gExp, 'AbsTol', 1e-10, ...
                    sprintf('inner exit derivative under fixed outer, N=%d', N));
            end
        end

        function innerExitReadAfterEnclosingLoop(tc)
            % B27 (#162): an inner runtime-bound loop whose counter-indexed exit
            % variable is read AFTER the ENCLOSING loop, so it is also an
            % outermost save target (SaveLoc != 0). This exercises the
            % saved-object overwrite (effect 1) on the inner-loop path - the one
            % branch the other B27 cases (which consume the exit inside the outer
            % loop) do not reach - so DoRemapping reads the inner union, not the
            % final-iteration baked gather.
            writeFcn('lb_inner_after', { ...
                'function y = lb_inner_after(x,N,K)', ...
                'w = 0;', ...
                'for k = 1:K', ...
                '  for a = 1:N', ...
                '    w = x(a)^2;', ...
                '  end', ...
                'end', ...
                'y = w;', ...            % read after BOTH loops -> outermost save
                'end'});
            Nmax = 4; Kmax = 2;
            gx = adigatorCreateDerivInput([Nmax 1],'x');
            adigator('lb_inner_after',{gx,Nmax,Kmax},'lb_inner_after_dx', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound',{'N','K'}));
            rehash;
            rng(3); xf = randn(Nmax,1);
            for NK = [Nmax Kmax; 2 2; 2 1; 1 2].'
                N = NK(1); K = NK(2);
                x = struct('f',xf,'dx',ones(Nmax,1));
                y = lb_inner_after_dx(x, N, K);
                tc.verifyEqual(y.f, xf(N)^2, 'AbsTol', 1e-12, 'RelTol', 1e-12, ...
                    sprintf('value at (N,K)=(%d,%d)', N, K));
                g = zeros(1, Nmax);
                if isfield(y,'dx_location') && ~isempty(y.dx_location)
                    g(y.dx_location(:,end)) = y.dx;
                end
                gExp = zeros(1, Nmax); gExp(N) = 2*xf(N);
                tc.verifyEqual(g, gExp, 'AbsTol', 1e-10, sprintf(['inner exit ', ...
                    'read after the enclosing loop at (N,K)=(%d,%d)'], N, K));
            end
        end

        function tripleNestedRuntimeBoundInnerExit(tc)
            % B27 (#162) depth-3 coverage: a runtime-bound loop nested two deep.
            % The middle loop is both child and parent; INNEREXITCOUNTS is
            % computed uniformly for every non-outermost loop, so the exit-union
            % should generalize past two levels.
            writeFcn('lb_triple', { ...
                'function y = lb_triple(x,N,M,K)', ...
                'y = 0;', ...
                'for k = 1:K', ...
                '  for m = 1:M', ...
                '    w = 0;', ...
                '    for a = 1:N', ...
                '      w = x(a)^2;', ...
                '    end', ...
                '    y = y + w;', ...     % y = K*M*x(N)^2
                '  end', ...
                'end', ...
                'end'});
            Nmax = 4; Mmax = 3; Kmax = 2;
            gx = adigatorCreateDerivInput([Nmax 1],'x');
            adigator('lb_triple',{gx,Nmax,Mmax,Kmax},'lb_triple_dx', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound',{'N','M','K'}));
            rehash;
            rng(5); xf = randn(Nmax,1);
            for NMK = [Nmax Mmax Kmax; 2 2 2; 1 3 1].'
                N = NMK(1); M = NMK(2); K = NMK(3);
                x = struct('f',xf,'dx',ones(Nmax,1));
                y = lb_triple_dx(x, N, M, K);
                tc.verifyEqual(y.f, K*M*xf(N)^2, 'AbsTol', 1e-12, 'RelTol', 1e-12, ...
                    sprintf('value at (N,M,K)=(%d,%d,%d)', N, M, K));
                g = zeros(1, Nmax);
                if isfield(y,'dx_location') && ~isempty(y.dx_location)
                    g(y.dx_location(:,end)) = y.dx;
                end
                gExp = zeros(1, Nmax); gExp(N) = 2*K*M*xf(N);
                tc.verifyEqual(g, gExp, 'AbsTol', 1e-10, sprintf(['triple-nested ', ...
                    'inner exit at (N,M,K)=(%d,%d,%d)'], N, M, K));
            end
        end

        function slimKeepsLoopboundGuard(tc)
            % #173 PR A: the forward-tape slicer used to THROW
            % adigator:fwdtape:parse on the runtime-bound `assert(name <= max)`
            % guard (its '<=' mis-split at the '='), so both slim engines
            % fail-safe-BAILED and returned the file unslimmed. The guard is now
            % whitelisted keep-always: the slicer PROCESSES the body, keeps the
            % guard AND the demanded write, and still slices a genuinely dead
            % statement. (Unit-level on adigatorFieldSlice so the assertion
            % distinguishes "sliced" from the old "bailed unchanged" - an
            % end-to-end file check cannot, since a bail also leaves the guard in
            % place and the file byte-identical.)
            body = ["assert(N <= 8);"; "y.f = sum(x.f);"; "y.dead_size = numel(x.f);"];
            [S, keep] = adigatorFieldSlice(body, {'x','N'}, "y.f");
            kt = strtrim(string({S.text}));
            tc.verifyEqual(nnz(keep), 2, ...
                'exactly the guard + the demanded write survive the slice');
            tc.verifyTrue(any(startsWith(kt,'assert(N <=')), ...
                'the loopbound guard must be kept (not dropped)');
            tc.verifyTrue(any(startsWith(kt,'y.f')), ...
                'the demanded write must be kept');
            tc.verifyFalse(any(contains(kt,'dead_size')), ...
                'a genuinely dead statement must still be sliced out');
        end

        function slimEngineSlicesLoopboundJacobian(tc)
            % #173 PR A end-to-end: a REAL loopbound-generated derivative file
            % (a vector-output Jacobian, whose dead output-index metadata makes
            % the slice genuinely fire) now slices through the FULL slim engine
            % (adigatorSlimDerivFile) and stays numerically exact through the
            % inline embed pipeline. Before PR A the runtime-bound
            % `assert(name <= max)` guard threw adigator:fwdtape:parse, so the
            % engine fail-safe-BAILED (sliced=false) and returned the file
            % unslimmed. The unit-level slimKeepsLoopboundGuard proves the slice
            % DISTINGUISHES sliced-from-bailed at the adigatorFieldSlice layer;
            % this proves the same at the file/engine layer on a generated file
            % AND that the slimmed loopbound file computes correctly.
            writeFcn('vlb', { ...
                'function v = vlb(x,p,N)', ...
                'v = zeros(N,1);', ...
                'for a = 1:N', ...
                '  v(a) = p(a)*x(a)^2;', ...
                'end', ...
                'end'});
            Nmax = 6;
            gx = adigatorCreateDerivInput([Nmax 1],'x');
            gp = adigatorCreateAuxInput([Nmax 1]);

            % (a) engine level, deterministic (no Coder): classic embed mode runs
            %     the generator but skips embedding, leaving the raw _ADiGator
            %     file that carries the assert; feeding it to the full slicer must
            %     now report sliced=true and KEEP the runtime-bound guard.
            cDir = fullfile(pwd,'cls');
            adigatorGenDerFile_embedded('jacobian','vlb',{gx,gp,Nmax}, ...
                adigatorOptions('embed_mode','c','path',cDir,'echo',0,'loopbound','N'));
            adi = readlines(fullfile(cDir,'vlb_ADiGatorJac.m'));
            tc.assertTrue(any(contains(adi,'assert(N <=')), ...
                'the raw loopbound derivative file must carry the assert guard');
            [sl, slinfo] = adigatorSlimDerivFile(adi, {'f','dx'});
            tc.verifyTrue(slinfo.sliced, ['a loopbound derivative file must now ', ...
                'SLICE (not fail-safe-bail on the assert guard as before PR A)']);
            tc.verifyTrue(any(contains(string(sl),'assert(N <=')), ...
                'the slimmed loopbound file must keep its runtime n <= Nmax guard');

            % (b) numeric: inline embed with slim OFF vs ON must agree bit-exactly
            %     and match the analytic Jacobian at n < Nmax with a zero tail.
            %     (Runtime touches coder.*; assumption-skip where unavailable.)
            for sv = [0 1]
                adigatorGenDerFile_embedded('jacobian','vlb',{gx,gp,Nmax}, ...
                    adigatorOptions('embed_mode','i','path',fullfile(pwd,sprintf('i%d',sv)), ...
                    'echo',0,'loopbound','N','slim_embed',sv));
            end
            rehash;
            rng(4); n = 4; xf = randn(Nmax,1); pf = 0.5 + rand(Nmax,1);
            J0 = runJacIn(tc, fullfile(pwd,'i0'), 'vlb_Jac', xf, pf, n, Nmax);
            J1 = runJacIn(tc, fullfile(pwd,'i1'), 'vlb_Jac', xf, pf, n, Nmax);
            tc.verifyEqual(J1, J0, 'AbsTol', 0, ...
                'slim on/off must give the identical loopbound Jacobian');
            Jexp = diag(2*pf(1:n).*xf(1:n));
            tc.verifyEqual(J1(1:n,1:n), Jexp, 'AbsTol', 1e-12, 'RelTol', 1e-12, ...
                'slimmed loopbound Jacobian must match the analytic n-sized program');
            J1(1:n,1:n) = 0;
            tc.verifyEqual(J1, zeros(Nmax), 'AbsTol', 0, 'padded tail must be zero');
        end
    end

    methods (Test)
        % #173 PR B: second-order loopbound support. A loopbound Hessian
        % (DERNUMBER==2) now re-emits the runtime header + `assert(name<=max)`
        % at the second-derivative level (adigatorForInitialize outer + inner
        % blocks), the exit-union widens past DERNUMBER==1 (adigatorForIterEnd),
        % and the gradient file's source assert is dropped-and-regenerated
        % (adigatorPrintTempFiles). So the Nmax Hessian run at n<Nmax matches the
        % n-sized program exactly with a structurally-zero padded tail.
        function loopboundHessianMatchesNsizedProgram(tc)
            % scalar cost y = sum_a p(a) x(a)^3  ->  H = diag(6 p x). The Nmax
            % Hessian at n<Nmax must equal a Hessian generated directly at n and
            % the analytic value, with a zero padded tail. (Was the healed
            % loopboundHessianReDiffTripwire KnownIssue.)
            writeFcn('lbh_acc', {'function y = lbh_acc(x,p,N)','y = 0;', ...
                'for a = 1:N','  y = y + p(a)*x(a)^3;','end','end'});
            Nmax = 6;
            adigatorGenHesFile('lbh_acc',{adigatorCreateDerivInput([Nmax 1],'x'), ...
                adigatorCreateAuxInput([Nmax 1]),Nmax}, ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N','path',fullfile(pwd,'lb')));
            rehash;
            rng(9); xf = randn(Nmax,1); pf = 0.5 + rand(Nmax,1);
            for n = [Nmax 4 1]
                adigatorGenHesFile('lbh_acc',{adigatorCreateDerivInput([n 1],'x'), ...
                    adigatorCreateAuxInput([n 1]),n}, ...
                    adigatorOptions('overwrite',1,'echo',0,'path',fullfile(pwd,'ex')));
                Hm = runHesIn(fullfile(pwd,'lb'),'lbh_acc_Hes',{xf,pf,n});
                Hn = runHesIn(fullfile(pwd,'ex'),'lbh_acc_Hes',{xf(1:n),pf(1:n),n});
                Hexp = diag(6*pf(1:n).*xf(1:n));
                tc.verifyEqual(Hm(1:n,1:n), Hn, 'AbsTol', 1e-10, ...
                    sprintf('loopbound Hessian must match n-sized program at n=%d', n));
                tc.verifyEqual(Hm(1:n,1:n), Hexp, 'AbsTol', 1e-10, 'RelTol', 1e-10, ...
                    sprintf('loopbound Hessian must match analytic at n=%d', n));
                Hm(1:n,1:n) = 0;
                tc.verifyEqual(Hm, zeros(Nmax), 'AbsTol', 0, 'padded tail must be zero');
            end
        end

        function nestedLoopboundHessianInnerExit(tc)
            % the B27 inner-exit shape AT SECOND ORDER: y = K*x(N)^2, so
            % H(N,N) = 2K and every other entry is zero. Before PR B the inner
            % runtime-bound loop's second-derivative exit was silently zeroed at
            % n<Nmax (the inner header emitted a malformed 1:(1:N)); this pins the
            % fix over truncation points in both bounds.
            writeFcn('lbh_inr', {'function y = lbh_inr(x,N,K)','y = 0;', ...
                'for k = 1:K','  w = 0;','  for a = 1:N','    w = x(a)^2;','  end', ...
                '  y = y + w;','end','end'});
            Nmax = 5; Kmax = 3;
            adigatorGenHesFile('lbh_inr',{adigatorCreateDerivInput([Nmax 1],'x'),Nmax,Kmax}, ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound',{'N','K'},'path',fullfile(pwd,'in')));
            rehash;
            rng(7); xf = randn(Nmax,1);
            for NK = [Nmax Kmax; 3 2; 2 1; 1 3].'
                N = NK(1); K = NK(2);
                H = runHesIn(fullfile(pwd,'in'),'lbh_inr_Hes',{xf,N,K});
                Hexp = zeros(Nmax); Hexp(N,N) = 2*K;
                tc.verifyEqual(H, Hexp, 'AbsTol', 1e-10, ...
                    sprintf('inner-exit loopbound Hessian at (N,K)=(%d,%d)', N, K));
            end
        end

        function coupledLoopboundHessianOffDiagonal(tc)
            % a FULL off-diagonal Hessian via a post-loop square of a loop-
            % accumulated exit variable: y = (sum_a p(a) x(a))^2 -> H = 2 p p'.
            % Exercises the outer-loop exit-union (s used after the loop) at
            % second order with genuine cross terms, FD-checked (rules out any
            % diagonal-only artefact).
            writeFcn('lbh_cpl', {'function y = lbh_cpl(x,p,N)','s = 0;', ...
                'for a = 1:N','  s = s + p(a)*x(a);','end','y = s^2;','end'});
            Nmax = 6;
            adigatorGenHesFile('lbh_cpl',{adigatorCreateDerivInput([Nmax 1],'x'), ...
                adigatorCreateAuxInput([Nmax 1]),Nmax}, ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N','path',fullfile(pwd,'c')));
            rehash;
            rng(31); xf = randn(Nmax,1); pf = 0.5 + rand(Nmax,1);
            for n = [Nmax 4 2]
                H = runHesIn(fullfile(pwd,'c'),'lbh_cpl_Hes',{xf,pf,n});
                Hexp = 2*pf(1:n)*pf(1:n).';
                tc.verifyEqual(H(1:n,1:n), Hexp, 'AbsTol', 1e-10, 'RelTol', 1e-10, ...
                    sprintf('coupled loopbound Hessian off-diagonal at n=%d', n));
                Hfd = fdHessian(@(xx) sum(pf(1:n).*xx(1:n))^2, xf, n);
                tc.verifyEqual(H(1:n,1:n), Hfd, 'AbsTol', 1e-5, ...
                    sprintf('coupled loopbound Hessian must match FD at n=%d', n));
                Htail = H; Htail(1:n,1:n) = 0;
                tc.verifyEqual(Htail, zeros(Nmax), 'AbsTol', 0, 'padded tail must be zero');
            end
        end

        function tripleNestedLoopboundHessian(tc)
            % depth-3 at second order: y = K*M*x(N)^2 -> H(N,N) = 2*K*M. The
            % middle loop is both child and parent; the inner-header restructure
            % + level-agnostic exit-union must generalize past two levels for the
            % Hessian, not only the gradient (tripleNestedRuntimeBoundInnerExit).
            writeFcn('lbh_tri', {'function y = lbh_tri(x,N,M,K)','y = 0;', ...
                'for k = 1:K','  for m = 1:M','    w = 0;','    for a = 1:N', ...
                '      w = x(a)^2;','    end','    y = y + w;','  end','end','end'});
            Nmax = 5; Mmax = 3; Kmax = 2;
            adigatorGenHesFile('lbh_tri',{adigatorCreateDerivInput([Nmax 1],'x'),Nmax,Mmax,Kmax}, ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound',{'N','M','K'},'path',fullfile(pwd,'t')));
            rehash;
            rng(5); xf = randn(Nmax,1);
            for NMK = [Nmax Mmax Kmax; 4 2 2; 1 3 1].'
                N = NMK(1); M = NMK(2); K = NMK(3);
                H = runHesIn(fullfile(pwd,'t'),'lbh_tri_Hes',{xf,N,M,K});
                Hexp = zeros(Nmax); Hexp(N,N) = 2*K*M;
                tc.verifyEqual(H, Hexp, 'AbsTol', 1e-10, ...
                    sprintf('triple-nested loopbound Hessian at (N,M,K)=(%d,%d,%d)', N, M, K));
            end
        end

        function userAssertOfGuardShapeFailsLoud(tc)
            % #173 PR A behavior preserved under PR B: an `assert(name<=int)` in
            % the user's OWN source is not differentiable and fails loud with the
            % actionable adigator:loopbound:rediff, rather than the accidental
            % generic "Cannot process statement". The printer only DROPS the guard
            % on a RE-differentiation (DERNUMBER>=2) of a loopbound file; a
            % first-pass (DERNUMBER==1) guard-shaped assert is the user's own and
            % must NOT be silently dropped - so it stays fail-loud even when the
            % loopbound option is set and the name collides with a bound parameter.
            writeFcn('lb_ua', {'function y = lb_ua(x,k)','assert(k <= 5);', ...
                'y = sum(x.^2);','end'});
            gx = @() adigatorCreateDerivInput([3 1],'x');
            % (a) loopbound NOT set
            tc.verifyError(@() adigator('lb_ua',{gx(),3},'lb_ua_dx', ...
                adigatorOptions('overwrite',1,'echo',0)), 'adigator:loopbound:rediff');
            % (b) loopbound SET on the SAME name k (first pass, DERNUMBER==1):
            % still fail-loud, NOT a silent drop of the user's guard
            tc.verifyError(@() adigator('lb_ua',{gx(),3},'lb_ua_dx', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','k')), ...
                'adigator:loopbound:rediff');
        end

        function vectorOutputLoopboundHessianFailsLoud(tc)
            % #173 PR B / ADR-0028 interim principle-1 guard (issue #181):
            % second-order loopbound support is validated for SCALAR-cost
            % Hessians only. A VECTOR/matrix-output loopbound Hessian exercises
            % the un-swept second-order exit-union and is otherwise SILENTLY
            % reachable, so it must fail loud (adigator:loopbound:vectorhessian)
            % rather than emit a possibly-wrong second derivative - mirroring the
            % scalar case's fail-loud-then-validate path (PR A -> PR B).
            % DISTINCT anchor names for the fail case vs the control: the fail
            % case's FIRST pass generates a loopbound gradient (carrying the
            % assert) BEFORE the guard fires, so a shared generated-function name
            % (<fn>_ADiGatorGrd) would let the control's second pass resolve to
            % that stale assert-carrying file and mis-fire with rediff. Distinct
            % names keep the two independent in the shared working folder.
            Nmax = 4;
            writeFcn('lbhv_fail', {'function y = lbhv_fail(x,N)','y = zeros(2,1);', ...
                'for a = 1:N','  y = y + [x(a)^2; x(a)^3];','end','end'});
            tc.verifyError(@() adigatorGenHesFile('lbhv_fail', ...
                {adigatorCreateDerivInput([Nmax 1],'x'),Nmax}, ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N')), ...
                'adigator:loopbound:vectorhessian');
            % control: the guard is loopbound-specific - the SAME vector-output
            % Hessian WITHOUT loopbound still generates (so the guard does not
            % over-reach into a general vector-output rejection).
            writeFcn('lbhv_ok', {'function y = lbhv_ok(x,N)','y = zeros(2,1);', ...
                'for a = 1:N','  y = y + [x(a)^2; x(a)^3];','end','end'});
            out = adigatorGenHesFile('lbhv_ok', ...
                {adigatorCreateDerivInput([Nmax 1],'x'),Nmax}, ...
                adigatorOptions('overwrite',1,'echo',0));
            tc.verifyNotEmpty(out, ...
                'a vector-output Hessian without loopbound must still generate');
        end
    end
end

function H = runHesIn(mdir, fn, args)
% cd into mdir, run the Hessian wrapper <fn>(args{:}) and return the dense
% Hessian. Clears the wrapper, the _ADiGatorHes file AND its persistent global
% so a same-named file in a sibling dir cannot serve stale .mat data (the
% cross-directory staleness that a plain `clear(fn)` misses).
old = cd(mdir); cu = onCleanup(@() cd(old));
adi = strrep(fn,'_Hes','_ADiGatorHes');
clear(fn); clear(adi); clear('global',['ADiGator_',adi]); rehash;
H = full(feval(fn, args{:}));
end

function H = fdHessian(f, x, n)
% central second-difference Hessian of scalar f over the first n entries of x
H = zeros(n); h = 1e-4;
for i = 1:n
    for j = 1:n
        ei = zeros(numel(x),1); ei(i) = h;
        ej = zeros(numel(x),1); ej(j) = h;
        H(i,j) = (f(x+ei+ej) - f(x+ei-ej) - f(x-ei+ej) + f(x-ei-ej))/(4*h*h);
    end
end
end

function J = runJacIn(tc, mdir, fn, xf, pf, n, Nmax)
% cd into mdir, run the inline Jacobian wrapper <fn>(x,p,N) (raw user-input
% signature) and scatter its nonzeros into an Nmax-by-Nmax dense matrix.
% The inline embedded file touches the coder.* namespace; assumption-skip
% (not fail) where it is unavailable, as the sibling embed tests do.
old = cd(mdir); cu = onCleanup(@() cd(old));
clear(fn); clear('global',['ADiGator_',fn]); rehash;
try
    G = feval(fn, xf, pf, n);
catch e
    if strcmp(e.identifier,'MATLAB:UndefinedFunction') && contains(e.message,'coder.')
        tc.assumeFail("coder.* namespace unavailable; skipping runtime check: " + e.message);
    end
    rethrow(e);
end
if isstruct(G) && isfield(G,'dx_location') && ~isempty(G.dx_location)
    J = full(sparse(G.dx_location(:,1), G.dx_location(:,2), G.dx, Nmax, Nmax));
else
    J = full(G);
end
end

function writeFcn(name, lines)
% write a fixture function file into the (temporary) working folder
fid = fopen([name '.m'], 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end
