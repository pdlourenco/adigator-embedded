function [J,v] = lb_alloc(x,p,N)
% Per-actuator cost terms accumulated in a rolled loop with a RUNTIME
% bound N (roadmap R3; issue #6 Tier 1). Generated once with N = Nmax,
% the derivative file accepts any 1 <= N <= Nmax at runtime: v is
% allocated as zeros(N,1) at the runtime value (the bound parameter
% prints by name), skipped iterations contribute nothing to the
% accumulator J, and the derivative pattern keeps the Nmax shape with
% structural zeros beyond N (padded-program semantics).
%
% Embeddability. This function alone does not code-generate under static memory
% allocation: v = zeros(N,1) has no compile-time bound when N is a runtime
% input (measured). The generated derivative does, because `loopbound` declares
% Nmax and emits the runtime guard that lets Coder size everything statically.
% So a runtime bound is not itself a barrier to an embeddable derivative -- an
% UNDECLARED one is. Contrast examples/stiffodes/, where the same runtime-sized
% shape has no loop for `loopbound` to match and the size must be pinned.
v = zeros(N,1);
J = 0;
for a = 1:N
  ua   = x(a);
  v(a) = p(a,1)*ua^2 + p(a,2)*ua;
  J    = J + v(a);
end
end
