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
    end
end

function writeFcn(name, lines)
% write a fixture function file into the (temporary) working folder
fid = fopen([name '.m'], 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end
