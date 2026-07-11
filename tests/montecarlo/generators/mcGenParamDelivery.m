function c = mcGenParamDelivery(i)
%MCGENPARAMDELIVERY  R27 Phase 1 generator: parameter-delivery invariance case.
%
% Emits a bilinear function y = P.M*x + P.g*x (so the Jacobian is exactly
% M + g*I), with random size n and random parameter values M, g. The case body
% uses the inline-constant-struct delivery (a body-assigned constant struct --
% the B17 shape). oracleParamDeliveryInvariance re-emits the *same* math with
% the parameters delivered several other ways (aux struct, separate aux inputs,
% inline constant cell = the B22 shape) and asserts every delivery yields the
% identical Jacobian -- the tolerance-free invariant that would have caught the
% B17/B22 silent-broken-codegen class (issue #103, ROADMAP R27).
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public License v3.0.

n = randi([2, 5]);
M = randn(n);
g = randn;
name = sprintf('mcpd_%d', i);
body = { ...
    sprintf('P = struct(''M'', %s, ''g'', %s);', mat2str(M, 17), mat2str(g, 17)), ...
    'y = P.M*x + P.g*x;'};
c = mcCase('name', name, 'body', body, 'xsize', [n 1], 'deriv', 'jacobian', ...
    'x0', randn(n, 1), ...
    'tags', struct('gen', 'paramDelivery', 'n', n, 'M', M, 'g', g, ...
                   'ops', 'bilinear', 'order', 1, 'inShape', [n 1], 'outShape', [n 1]));
end
