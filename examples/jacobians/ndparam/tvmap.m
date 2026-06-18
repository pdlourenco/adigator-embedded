function y = tvmap(x,B)
% Time-varying linear map (roadmap R2; issue #11 Level 2 veneer).
%
% B is an N-D declared parameter of size m x n x K (see
% adigatorCreateAuxInput): inside the rolled loop it is sliced with the
% natural B(:,:,k) syntax, k being the loop counter. ADiGator rewrites the
% slice as the affine column window (k-1)*n + (1:n) on the internal 2D
% fold of B.
%
% y stacks y_k = B(:,:,k)*g(x), g(x) = x + x.^3/6, over k = 1..K.
K = 4;
m = 3;
g = x + x.^3/6;
y = zeros(m*K,1);
for k = 1:K
  y((k-1)*m+(1:m)) = B(:,:,k)*g;
end
end
