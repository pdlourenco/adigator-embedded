function D = fdcheck(mode, f, x)
% FDCHECK  Shared central-finite-difference oracle for the test suites.
%
% CI_PLAN.md TS-U-02/03 and the value checks of TS-I-01 use this instead of
% each re-deriving a local FD helper.
%
%   J = fdcheck('jac',  f, x)  -> [numel(f(x)) x numel(x)] Jacobian, the output
%                                 linearized column-major (row k = d f_k / d x_j).
%   H = fdcheck('hess', f, x)  -> [numel(f(x)) x numel(x) x numel(x)] with
%                                 H(k,i,j) = d^2 f_k / d x_i d x_j.
%
% f is a function handle taking x (any shape) and returning a numeric array;
% x is the evaluation point. Central differences: O(h^2) accurate, so callers
% compare at ~1e-5 (Jacobian) / ~1e-4 (Hessian) relative tolerance.

switch lower(char(mode))
    case 'jac'
        D = fdjac(f, x);
    case 'hess'
        D = fdhess(f, x);
    otherwise
        error('fdcheck:mode', 'mode must be ''jac'' or ''hess'', got ''%s''', mode);
end
end

function J = fdjac(f, x)
h = 1e-6;
m = numel(f(x));
n = numel(x);
J = zeros(m, n);
for j = 1:n
    e = zeros(size(x)); e(j) = h;
    J(:,j) = reshape(f(x+e) - f(x-e), [], 1) / (2*h);
end
end

function H = fdhess(f, x)
h = 1e-4;
m = numel(f(x));
n = numel(x);
H = zeros(m, n, n);
for i = 1:n
    ei = zeros(size(x)); ei(i) = h;
    for j = 1:n
        ej = zeros(size(x)); ej(j) = h;
        H(:,i,j) = reshape( ...
            f(x+ei+ej) - f(x+ei-ej) - f(x-ei+ej) + f(x-ei-ej), [], 1) / (4*h^2);
    end
end
end
