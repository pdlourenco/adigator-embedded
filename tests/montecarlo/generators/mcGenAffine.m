function c = mcGenAffine(uid)
%MCGENAFFINE  Random affine map y = A*x + b with an exact Jacobian (ADR-0007).
%
% Known-derivative-by-construction generator: the Jacobian of y = A*x + b is
% exactly A, independent of x, so the value check is tolerance-free. Draws
% from the current RNG state (the campaign seeds it per iteration).
if nargin < 1, uid = 0; end

n = randi([2 6]);          % numel(x) >= 2 so the m x n Jacobian convention holds
m = randi([1 6]);
A = randi([-3 3], m, n);   % integer entries: also stresses the B1 down-cast path
b = randi([-3 3], m, 1);
x0 = randn(n, 1);

name = sprintf('mc_affine_%d', uid);
body = sprintf('y = %s*x + %s;', mat2str(A), mat2str(b));

c = mcCase('name', name, 'body', body, 'xsize', [n 1], ...
    'deriv', 'jacobian', 'x0', x0, ...
    'exactJac', @(x) A, ...
    'tags', struct('gen','affine','ops',{{'mtimes','plus'}}, ...
                   'inShape',[n 1],'outShape',[m 1], ...
                   'density','dense','order',1));
end
