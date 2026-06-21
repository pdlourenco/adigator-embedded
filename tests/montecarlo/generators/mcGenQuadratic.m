function c = mcGenQuadratic(uid)
%MCGENQUADRATIC  Random quadratic f = 0.5 x'Qx + c'x, exact gradient/Hessian.
%
% Known-derivative-by-construction generator (ADR-0007): for a symmetric Q
% the gradient is Q*x + c and the Hessian is exactly Q, both checkable
% tolerance-free. Emits a Hessian case (the wrapper also returns the
% gradient, which the known-derivative oracle checks via exactJac).
if nargin < 1, uid = 0; end

n = randi([2 5]);
M = randi([-2 2], n, n);
Q = M + M.';               % symmetric, integer entries
cc = randi([-2 2], n, 1);
x0 = randn(n, 1);

name = sprintf('mc_quad_%d', uid);
body = sprintf('y = 0.5*x.''*%s*x + %s.''*x;', mat2str(Q), mat2str(cc));

c = mcCase('name', name, 'body', body, 'xsize', [n 1], ...
    'deriv', 'hessian', 'x0', x0, ...
    'exactJac',  @(x) Q*x + cc, ...   % gradient of the scalar objective (n x 1)
    'exactHess', @(x) Q, ...
    'tags', struct('gen','quadratic','ops',{{'mtimes','transpose','plus'}}, ...
                   'inShape',[n 1],'outShape',[1 1], ...
                   'density','dense','order',2));
end
