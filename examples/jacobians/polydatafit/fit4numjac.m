function p= fit4numjac(t,x, d, m)
% FIT -- Given x and d, fit() returns p
% such that norm(V*p-d) = min, where
% V = [1, x, x.?2, ... x.?(m-1)].

dim_x = size(x, 1);
if dim_x < m
  error('x must have at least m entries');
end

% Note: this numjac callback keeps the concatenation-grown V on purpose --
% it is a host-only finite-difference reference and is never differentiated
% or code-generated. fit.m explains why the differentiated copy pre-sizes V.
V = ones(dim_x, 1);

for count = 1 : (m-1)
  V = [V, x.^count];
end

p = V \ d;