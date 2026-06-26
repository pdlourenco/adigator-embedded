function y = vvecfun(x)
% vvecfun  Vectorized vector output (no loop) with a diagonal (sparse) Jacobian,
% the codegen-friendly companion to vfun for the R17b C-level Jacobian axis.
y = sin(x) + x.^2;
end
