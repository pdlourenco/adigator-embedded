function [Grd, Fun] = vcostfun_grad_fd(x)
%#codegen
% Finite-difference gradient of vcostfun = sum(exp(x)+2x) - the R17 FD method
% (issue #73), C-6 order [Grd, Fun]. Central difference via the shared fdDeriv
% kernel; the `@vcostfun` literal is a Coder compile-time constant, so this is a
% codegen entry point exactly like vcostfun_grad_analytic.
[Grd, Fun] = fdDeriv(@vcostfun, x, 'grad');
end
