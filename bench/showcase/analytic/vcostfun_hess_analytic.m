function [Hes, Grd, Fun] = vcostfun_hess_analytic(x)
%#codegen
% Hand-coded Hessian of vcostfun = sum(exp(x)+2x) (C-6 order [Hes, Grd, Fun]).
Hes = diag(exp(x));
Grd = exp(x) + 2;
Fun = sum(exp(x) + 2*x);
end
