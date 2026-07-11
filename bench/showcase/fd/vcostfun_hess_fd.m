function [Hes, Grd, Fun] = vcostfun_hess_fd(x)
%#codegen
% Finite-difference Hessian of vcostfun = sum(exp(x)+2x) - the R17 FD method
% (issue #73), C-6 order [Hes, Grd, Fun]. Hes via second central differences,
% Grd via first central differences (both from the shared fdDeriv kernel).
[Hes, Fun] = fdDeriv(@vcostfun, x, 'hess');
[Grd, ~]   = fdDeriv(@vcostfun, x, 'grad');
end
