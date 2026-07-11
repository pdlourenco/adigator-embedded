function y = scostfun_lb(x,N)
% scostfun_lb  Loopbound scalar cost - the allocation/loopbound shape with an
% explicit RUNTIME trip count N (roadmap R3, issue #6 Tier 1). J = sum_{k=1:N}
% phi(x_k), phi = exp + 2*(). Used by the R17 Tier-1 padding-penalty measurement
% (bench/loopboundPaddingPenalty): generated once at N = Nmax and called with any
% n <= Nmax, versus a file regenerated at exact n. It is subscripted (x(k)), so
% its derivative carries a per-iteration nonzero-location table that scales with
% the trip count - which is what makes the Nmax-padding penalty visible.
%
% Copyright Pedro Lourenço and GMV.  2026-07  (roadmap R17 Tier-1 padding penalty, issue #73/#6)
% Distributed under the GNU General Public License version 3.0
y = 0;
for k = 1:N
    y = y + exp(x(k)) + 2*x(k);
end
end
