% N-D declared parameter example (roadmap R2; issue #11 Level 2)
%
% A parameter B of declared size m x n x K is created with
% adigatorCreateAuxInput([m n K]) and sliced inside the differentiated
% function with the natural B(:,:,k) syntax, k being the loop counter
% (tvmap.m). Internally B is its 2D column-major fold and the slice is
% rewritten as the affine column window (k-1)*n + (1:n) - the same
% machinery as the manual folded-2D pattern documented in
% examples/optimization/vectorized/allocation/README.md, with nicer
% syntax. The generated derivative file accepts B either as the 3D array
% or as its 2D fold reshape(B,m,[]).
fprintf('AdiGator example: %s\n', mfilename('fullpath'));
rng(0);
m = 3; n = 2; K = 4;

gx = adigatorCreateDerivInput([n 1],'x');
gB = adigatorCreateAuxInput([m n K]);
adigator('tvmap',{gx,gB},'tvmap_dx',adigatorOptions('overwrite',1));

B = randn(m,n,K);
x.f  = randn(n,1);
x.dx = ones(n,1);
y = tvmap_dx(x,B);
J = sparse(y.dx_location(:,1), y.dx_location(:,2), y.dx, ...
    y.dx_size(1), y.dx_size(2));

% analytic Jacobian: rows (k-1)*m+(1:m) are B(:,:,k)*diag(1 + x.^2/2)
Ja = zeros(m*K,n);
for k = 1:K
  Ja((k-1)*m+(1:m),:) = B(:,:,k)*diag(1 + x.f.^2/2);
end
fprintf('max |J - J_analytic|            : %8.3g\n', max(abs(full(J(:))-Ja(:))));

% central finite differences on the original function
ee = 1e-6;
Jfd = zeros(m*K,n);
for i = 1:n
  e = zeros(n,1); e(i) = ee;
  Jfd(:,i) = (tvmap(x.f+e,B) - tvmap(x.f-e,B))/(2*ee);
end
fprintf('max |J - J_fd|                  : %8.3g\n', max(abs(full(J(:))-Jfd(:))));

% the same generated file also accepts the folded 2D parameter
y2 = tvmap_dx(x, reshape(B,m,[]));
fprintf('max |y(3D arg) - y(folded arg)| : %8.3g\n', ...
    max(abs([y.f-y2.f; y.dx-y2.dx])));
