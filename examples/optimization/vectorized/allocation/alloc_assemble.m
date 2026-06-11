function [Jcost,gJ,G,JG] = alloc_assemble(u,p,B,tau)
% ALLOC_ASSEMBLE  Evaluate the vectorized per-pair derivative file once and
% assemble the full-problem value and derivatives for any (N, K).
%
% This is the conswrap pattern (cf. examples/optimization/vectorized/
% minimumclimb/conswrap.m) applied in BOTH growth dimensions: the generated
% file alloc_terms_dU supplies the block-diagonal per-pair derivatives, and
% the linear reductions are assembled here with plain (sparse) algebra:
%
%   cost      J   = sum_i phi_i            ->  gJ(i) = dphi_i/du_i
%   moments   G_k = B*h_k - tau_k          ->  JG((k-1)*m+(1:m), (k-1)*N+a)
%                                                = B(:,a) * dh_i
%
%   u   : [N*K x 1] decision
%   p   : [N*K x 3] per-pair parameters (see alloc_terms)
%   B   : [m x N]   moment matrix (actuator -> moment map)
%   tau : [m x K]   demanded moments per time step
%
%   Jcost : scalar cost,  gJ : [N*K x 1] gradient (column convention)
%   G     : [m*K x 1] moment residuals, JG : [m*K x N*K] sparse Jacobian
[m,N] = size(B);
NK = numel(u);
K = NK/N;

% evaluate the (single, size-free) generated derivative file
U.f  = u(:);
U.dU = ones(NK,1);
y = alloc_terms_dU(U,p);

% map derivative columns via the reported single-instance locations
loc  = y.dU_location;          % rows of the per-pair 2x1 Jacobian
dphi = y.dU(:, loc(:,1) == 1); % d phi_i / d u_i
dh   = y.dU(:, loc(:,1) == 2); % d h_i   / d u_i

Jcost = sum(y.f(:,1));
gJ    = dphi(:);

H = reshape(y.f(:,2), N, K);
G = reshape(B*H - tau, [], 1);

% block-structured moment Jacobian: column i = (k-1)*N + a holds B(:,a)*dh_i
rows = zeros(m*NK,1); cols = rows; vals = rows;
idx = 0;
for k = 1:K
    for a = 1:N
        i = (k-1)*N + a;
        rows(idx+(1:m)) = (k-1)*m + (1:m);
        cols(idx+(1:m)) = i;
        vals(idx+(1:m)) = B(:,a)*dh(i);
        idx = idx + m;
    end
end
JG = sparse(rows, cols, vals, m*K, NK);
end
