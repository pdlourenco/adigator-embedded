function y = vfun(x)
% vfun  Vector output with a rolled loop and a (sparse) diagonal Jacobian - the
% R17 showcase function for the Jacobian axis (which needs a vector output).
n = size(x,1);
y = zeros(n,1);
for k = 1:n
    y(k) = sin(x(k)) + x(k).^2;
end
end
