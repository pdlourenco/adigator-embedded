function y = structvecfun(in)
% Vector-valued function with struct inputs, used for the Jacobian case
% (issue #24, scope A):
%   in.x : variable of differentiation (n x 1)
%   in.A : matrix              (auxiliary, m x n)
%   in.b : offset              (auxiliary, m x 1)
% y = A*x + b, so the Jacobian of y w.r.t. x is exactly A.
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public License v3.0.
y = in.A*in.x + in.b;
end
