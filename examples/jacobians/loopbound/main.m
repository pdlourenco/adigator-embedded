% Runtime loop bound example (roadmap R3; issue #6 Tier 1)
%
% The 'loopbound' option names an input of the differentiated function
% (here N) that acts as a runtime trip count. The analysis runs at the
% maximum value passed to adigator (Nmax); the generated file prints
% 'assert(N <= Nmax); for ... = 1:N' instead of a fixed literal, and the
% loop's exit variables take the union over all iterations. One generated
% file then serves any number of active actuators n <= Nmax - the
% reconfiguration use case - with exact structural zeros beyond n.
%
% Padded-program semantics: post-loop code must be padding-benign (sums,
% dot products, gathers over loop-written entries). See adigatorOptions.
fprintf('AdiGator example: %s\n', mfilename('fullpath'));
rng(0);
Nmax = 8;

gx = adigatorCreateDerivInput([Nmax 1],'x');
gp = adigatorCreateAuxInput([Nmax 2]);
adigator('lb_alloc',{gx,gp,Nmax},'lb_alloc_dx', ...
    adigatorOptions('overwrite',1,'loopbound','N','path','generated'));
addpath(fullfile(pwd,'generated'));

p = [0.5 + rand(Nmax,1), randn(Nmax,1)];
for n = [Nmax 5 3]
    x.f  = randn(Nmax,1); % entries beyond n are arbitrary - they must not leak
    x.dx = ones(Nmax,1);
    [J,v] = lb_alloc_dx(x,p,n);
    % scalar J: the last dx_location column holds the variable index
    gJ = zeros(Nmax,1);
    gJ(J.dx_location(:,end)) = J.dx;

    % direct computation on the n-sized problem
    Jn  = sum(p(1:n,1).*x.f(1:n).^2 + p(1:n,2).*x.f(1:n));
    gn  = 2*p(1:n,1).*x.f(1:n) + p(1:n,2);
    fprintf(['n = %d: |J - Jn| = %8.3g, max grad err (1:n) = %8.3g, ', ...
        'max |grad(n+1:end)| = %8.3g, max |v tail (if padded)| = %8.3g\n'], ...
        n, abs(J.f - Jn), max(abs(gJ(1:n) - gn)), ...
        max([abs(gJ(n+1:end)); 0]), max([abs(v.f(n+1:end)); 0]));
end
rmpath(fullfile(pwd,'generated'));
