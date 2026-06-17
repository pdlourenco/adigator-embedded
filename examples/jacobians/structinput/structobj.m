function f = structobj(in)
% Example user function whose inputs are carried as fields of a single
% struct (issue #24, scope A):
%   in.x : optimization variable, differentiated with respect to
%   in.Q : symmetric weight matrix (auxiliary, no derivatives)
%   in.c : linear term            (auxiliary, no derivatives)
%
% Scalar quadratic objective f(x) = 1/2 x'Q x + c'x, so that
%   grad_x f = Q x + c   and   hess_x f = Q,
% giving closed-form references for the example's checks.
%
% Copyright GMV. Distributed under the GNU General Public License v3.0.
f = 0.5*(in.x.'*(in.Q*in.x)) + in.c.'*in.x;
end
