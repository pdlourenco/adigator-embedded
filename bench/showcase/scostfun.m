function y = scostfun(x)
% scostfun  Scalar cost with a rolled loop - the allocation/loopbound shape
% J = sum_k phi(x_k). Used by the R17 derivative showcase as the anchor that
% exercises every axis: gradient, Hessian, forward & reverse, rolled & unrolled.
n = size(x,1);
y = 0;
for k = 1:n
    y = y + exp(x(k)) + 2*x(k);
end
end
