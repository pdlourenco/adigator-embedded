function [D, F] = fdDeriv(fn, x, kind, h)
%#codegen
% FDDERIV  Central-difference derivative of a function handle - the R17 showcase
% FINITE-DIFFERENCE method (issue #73). Computes the derivative of `fn` at `x`
% purely by repeatedly evaluating `fn`, so it is the "cheap to write, inexact,
% O(n) evals" baseline the AD methods are measured against (the only method here
% with truncation error - its error-vs-analytic column is the informative one).
%
% It is written Coder-compatible (fixed-size preallocation, no unsupported
% constructs) and takes the anchor as a function handle, so a per-anchor codegen
% entry wrapper (bench/showcase/fd/<fn>_<der>_fd.m) that calls it with a literal
% `@anchor` flows through BOTH the interpreted harness (derivShowcase) and the
% Coder->lib/MEX harness (derivShowcaseC) exactly like the AD/analytic cells.
%
%   [D, F] = fdDeriv(fn, x, kind[, h])
%     fn    - function handle of the scalar/vector cost, y = fn(x)
%     x     - column evaluation point (n x 1)
%     kind  - 'grad' (scalar cost -> n x 1), 'jac' (vector out -> m x n),
%             or 'hess' (scalar cost -> n x n)
%     h     - optional per-element step override (scalar or n x 1); by default
%             h = eps^(1/3)*max(1,|x|) for first derivatives (central diff
%             truncation-vs-roundoff optimum) and eps^(1/4)*max(1,|x|) for the
%             second-difference Hessian.
%     D     - the derivative in the C-1 shape for `kind`
%     F     - fn(x), the function value (so callers get [D, F] like the refs)
%
% Copyright Pedro Lourenço and GMV.  2026-07  (roadmap R17, issue #73 - FD method)
% Distributed under the GNU General Public License version 3.0
n = numel(x);
F = fn(x);
if nargin < 4 || isempty(h)
    if strcmp(kind,'hess'); p = 4; else; p = 3; end
    hs = eps^(1/p) * max(1, abs(x(:)));
elseif isscalar(h)
    hs = h * ones(n,1);
else
    hs = h(:);
end

switch kind
    case {'grad','jac'}
        m = numel(F);
        J = zeros(m, n);
        for i = 1:n
            hi = hs(i);
            xp = x; xp(i) = xp(i) + hi;
            xm = x; xm(i) = xm(i) - hi;
            yp = fn(xp); ym = fn(xm);
            J(:,i) = (yp(:) - ym(:)) / (2*hi);
        end
        if strcmp(kind,'grad')
            D = J(:);            % scalar cost -> n x 1 column gradient (C-1)
        else
            D = J;               % vector output -> m x n Jacobian (C-1)
        end
    case 'hess'
        H = zeros(n, n);
        for i = 1:n
            for j = 1:n
                hi = hs(i); hj = hs(j);
                xpp = x; xpp(i) = xpp(i)+hi; xpp(j) = xpp(j)+hj;
                xpm = x; xpm(i) = xpm(i)+hi; xpm(j) = xpm(j)-hj;
                xmp = x; xmp(i) = xmp(i)-hi; xmp(j) = xmp(j)+hj;
                xmm = x; xmm(i) = xmm(i)-hi; xmm(j) = xmm(j)-hj;
                H(i,j) = (fn(xpp) - fn(xpm) - fn(xmp) + fn(xmm)) / (4*hi*hj);
            end
        end
        D = H;
    otherwise
        D = zeros(n,1);          % unreachable; keeps Coder's output type stable
end
end
