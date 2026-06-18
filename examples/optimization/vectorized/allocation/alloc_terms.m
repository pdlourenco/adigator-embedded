function y = alloc_terms(u,p)
% ALLOC_TERMS  Per-(actuator, time) terms of the allocation-over-time
% problem, vectorized over the product index i = (k-1)*N + a.
%
% This is the "product fold" of issues #6 (Tier 0) / #11 (option 1): both
% growth dimensions (N actuators, K time steps) are folded into ONE
% vectorized dimension of size N*K, so a single generated derivative file
% is valid for any (N, K).
%
%   u : [N*K x 1] decision, one row per (actuator, time) pair
%   p : [N*K x 3] per-pair parameters:
%       p(:,1) = w     quadratic cost weight
%       p(:,2) = q     linear cost weight
%       p(:,3) = alpha cubic actuator-effectiveness coefficient
%
%   y(:,1) = phi : per-pair cost term            (J   = sum over pairs)
%   y(:,2) = h   : per-pair actuator effectiveness (B*h_k = tau_k per step)
%
% Everything is elementwise in the product dimension (block-diagonal
% derivatives); the reductions over actuators / time live in the assembly
% wrapper alloc_assemble.m, NOT here (vectorized mode forbids reductions
% over the free dimension).
phi = 0.5*p(:,1).*u.^2 + p(:,2).*u;
h   = u + p(:,3).*u.^3;
y   = [phi h];
end
