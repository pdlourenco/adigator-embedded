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
end

function writeFcn(name, lines)
% write a fixture function file into the (temporary) working folder
fid = fopen([name '.m'], 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end
