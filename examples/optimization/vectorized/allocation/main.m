% Allocation-over-time example (roadmap R1; issues #6 Tier 0, #11 options 1-2)
%
% Optimal allocation with N actuators over K time steps:
%   min_u  sum_{a,k} phi(u_{a,k})    s.t.  B*h(u_k) = tau_k  for each k
%
% Both N and K stay FREE at runtime: per-pair terms are differentiated once
% in vectorized mode over the product index i = (k-1)*N + a, and the
% reductions (sum over pairs; moments over actuators per time step) are
% assembled by alloc_assemble.m with plain linear algebra. One generated
% derivative file serves every (N, K) below.
%
% See README.md in this folder for the pattern catalog (product fold,
% assembly wrappers, folded-2D parameters, cell arrays).
fprintf('AdiGator example: %s\n', mfilename('fullpath'));
rng(0);

% ----- generate ONE vectorized derivative file (free product dimension) -----
tic
gU = adigatorCreateDerivInput([Inf 1], ...
    struct('vodname','U','vodsize',[Inf 1],'nzlocs',[1 1]));
gP = adigatorCreateAuxInput([Inf 3]);
adigator('alloc_terms',{gU,gP},'alloc_terms_dU',adigatorOptions('overwrite',1));
gentime = toc;

% ----- evaluate and assemble for several (N, K) pairs ----------------------
m = 3; % number of moments
sizes = [4 5; 6 3; 8 10];
for s = 1:size(sizes,1)
    N = sizes(s,1); K = sizes(s,2); NK = N*K;
    B   = randn(m,N);
    tau = randn(m,K);
    p   = [0.5 + rand(NK,1), randn(NK,1), 0.1*rand(NK,1)];
    u   = randn(NK,1);

    [Jcost,gJ,G,JG] = alloc_assemble(u,p,B,tau); %#ok<ASGLU>

    % central finite differences on the assembled quantities
    costfun = @(uu) sum(0.5*p(:,1).*uu.^2 + p(:,2).*uu);
    confun  = @(uu) reshape(B*reshape(uu + p(:,3).*uu.^3, N, K) - tau, [], 1);
    ee = 1e-6;
    gfd  = zeros(NK,1);
    Jgfd = zeros(m*K,NK);
    for i = 1:NK
        e = zeros(NK,1); e(i) = ee;
        gfd(i)    = (costfun(u+e) - costfun(u-e))/(2*ee);
        Jgfd(:,i) = (confun(u+e)  - confun(u-e))/(2*ee);
    end
    graderr = max(abs(gJ - gfd));
    jacerr  = max(max(abs(full(JG) - Jgfd)));
    fprintf(['N = %2d, K = %2d (same generated file): ', ...
        'max grad err %8.3g, max Jacobian err %8.3g\n'], N, K, graderr, jacerr);
end
fprintf('Vectorized derivative file generation time (once, for all sizes): %.3g s\n', gentime);
