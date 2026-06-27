function [Jac, Fun] = vvecfun_jac_analytic(x)
%#codegen
% Hand-coded Jacobian of vvecfun = sin(x)+x.^2 (C-6 order [Jac, Fun]).
Jac = diag(cos(x) + 2*x);
Fun = sin(x) + x.^2;
end
