function [J,v] = lb_alloc(x,p,N)
% Per-actuator cost terms accumulated in a rolled loop with a RUNTIME
% bound N (roadmap R3; issue #6 Tier 1). Generated once with N = Nmax,
% the derivative file accepts any 1 <= N <= Nmax at runtime: v is
% allocated as zeros(N,1) at the runtime value (the bound parameter
% prints by name), skipped iterations contribute nothing to the
% accumulator J, and the derivative pattern keeps the Nmax shape with
% structural zeros beyond N (padded-program semantics).
v = zeros(N,1);
J = 0;
for a = 1:N
  ua   = x(a);
  v(a) = p(a,1)*ua^2 + p(a,2)*ua;
  J    = J + v(a);
end
end
