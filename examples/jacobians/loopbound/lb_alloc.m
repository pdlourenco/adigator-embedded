function [J,v] = lb_alloc(x,p,N)
% Per-actuator cost terms accumulated in a rolled loop with a RUNTIME
% bound N (roadmap R3; issue #6 Tier 1). Generated once with N = Nmax,
% the derivative file accepts any 1 <= N <= Nmax at runtime: skipped
% iterations leave exact structural zeros in v and contribute nothing
% to the accumulator J (padded-program semantics).
v = zeros(N,1);
J = 0;
for a = 1:N
  ua   = x(a);
  v(a) = p(a,1)*ua^2 + p(a,2)*ua;
  J    = J + v(a);
end
end
