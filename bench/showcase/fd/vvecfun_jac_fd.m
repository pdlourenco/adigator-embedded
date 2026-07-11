function [Jac, Fun] = vvecfun_jac_fd(x)
%#codegen
% Finite-difference Jacobian of vvecfun = sin(x)+x.^2 - the R17 FD method
% (issue #73), C-6 order [Jac, Fun]. Central difference via the shared fdDeriv
% kernel (m x n; here diagonal).
[Jac, Fun] = fdDeriv(@vvecfun, x, 'jac');
end
