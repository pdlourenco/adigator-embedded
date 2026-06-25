% Reverse-mode gradient example (roadmap R4; docs/ANALYSIS.md section 3)
%
% adigatorGenRevGradFile transforms the forward derivative file printed by
% adigator() - a static tape of fixed-size statements with constant index
% maps - into a self-contained adjoint program lse_cost_RGrd.m that
% returns the value and the full gradient from ONE forward and ONE
% reverse sweep, independent of the number of variables. The derivative
% input is passed as a plain numeric array (no seed structure).
fprintf('AdiGator example: %s\n', mfilename('fullpath'));
rng(0);
n = 50;

gx = adigatorCreateDerivInput([n 1],'x');
gw = adigatorCreateAuxInput([n 1]);
adigatorGenRevGradFile('lse_cost',{gx,gw}, ...
    adigatorOptions('overwrite',1,'path','generated'));
addpath(fullfile(pwd,'generated'));   % generated files land in ./generated

x = randn(n,1);
w = 0.5 + rand(n,1);
[y,g] = lse_cost_RGrd(x,w);

% analytic gradient and central differences
ga = w.*exp(w.*x)/sum(exp(w.*x));
ee = 1e-6;
gfd = zeros(n,1);
for i = 1:n
    e = zeros(n,1); e(i) = ee;
    gfd(i) = (lse_cost(x+e,w) - lse_cost(x-e,w))/(2*ee);
end
fprintf('value error                 : %8.3g\n', abs(y - lse_cost(x,w)));
fprintf('max |g - g_analytic|        : %8.3g\n', max(abs(g - ga)));
fprintf('max |g - g_finite_diff|     : %8.3g\n', max(abs(g - gfd)));
rmpath(fullfile(pwd,'generated'));
