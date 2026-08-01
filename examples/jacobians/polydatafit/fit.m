function p = fit(x, d, m)
% FIT -- Given x and d, fit() returns p
% such that norm(V*p-d) = min, where
% V = [1, x, x.^2, ... x.^(m-1)].
%
% Note on the Vandermonde loop below. The natural way to write it is to grow
% the matrix by concatenation:
%
%     V = ones(dim_x, 1);
%     for count = 1 : (m-1)
%       V = [V, x.^count];        % V gains a column each iteration
%     end
%
% That differentiates fine, but it is NOT embeddable, and the reason has
% nothing to do with ADiGator: a variable that grows by concatenation has no
% compile-time size bound, so MATLAB Coder rejects THIS function -- before any
% derivative exists -- under static memory allocation ("Computed maximum size
% is not bounded"), which is the setting an embedded target requires. The
% derivative of a function that cannot be code-generated cannot be
% code-generated either.
%
% Pre-allocating V at its final size and writing into it fixes that: the size
% is known up front, so the function and its derivative both code-generate.
% The mathematics is unchanged. This is a good habit for any function you
% intend to differentiate for an embedded target -- prefer indexed writes into
% a pre-sized array over growing one.

dim_x = size(x, 1);
if dim_x < m
  error('x must have at least m entries');
end

V = ones(dim_x, m);

for count = 1 : (m-1)
  V(:, count+1) = x.^count;
end
p = V\d;
