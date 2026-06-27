function [Grd, Fun] = vcostfun_grad_analytic(x)
%#codegen
% Hand-coded gradient of vcostfun = sum(exp(x)+2x); the R17 AD-vs-analytical
% reference (C-6 order [Grd, Fun]). No ADiGator - what a user writes by hand.
Grd = exp(x) + 2;
Fun = sum(exp(x) + 2*x);
end
