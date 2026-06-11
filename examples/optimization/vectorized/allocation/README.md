# Allocation over time with free (N, K) — pattern catalog

Roadmap item R1 (`docs/ROADMAP.md`); validates issue
[#6](https://github.com/pdlourenco/adigator-embedded/issues/6) Tier 0 and
issue [#11](https://github.com/pdlourenco/adigator-embedded/issues/11)
options 1–2 with today's machinery: one generated derivative file serves
any number of actuators `N` and time steps `K`.

## The decomposition

```
min_u  Σ_{a,k} φ(u_{a,k}; p_{a,k})        separable cost
s.t.   B · h(u_k) = τ_k   for k = 1..K    moment matching per time step
```

1. **Product fold** (#11 option 1): everything that is local to one
   (actuator, time) pair is written elementwise over a single vectorized
   dimension of size `N·K`, ordered `i = (k-1)·N + a`. Vectorized mode
   does not care that the free dimension is a product — see
   `alloc_terms.m`. ADiGator is called once with
   `adigatorCreateDerivInput([Inf 1], ...)`; the generated
   `alloc_terms_dU` is valid for every `(N, K)`.
2. **Assembly wrappers** (#11 option 2, the `conswrap` pattern): the
   reductions — the cost sum over all pairs and the moment contraction
   over actuators at each time step — are *linear*, so they are applied
   outside the generated file with constant/sparse algebra
   (`alloc_assemble.m`). Vectorized mode forbids reductions over the free
   dimension; this is how to put them back.
3. **Run** `main.m`: generates once, then verifies the assembled gradient
   and Jacobian against central finite differences for several `(N, K)`.

## Related patterns available today (#11 Level 1)

- **Folded-2D parameters:** a time-varying matrix parameter `B(:,:,k)`
  (`m × n × K`) can be stored as the 2-D fold `Bf = reshape(B, m, n*K)`
  and sliced with the affine column window
  `Bf(:, (k-1)*n + (1:n))` inside a rolled loop — the organizational-op
  machinery handles affine-in-counter windows. With two indices
  (`B(:,:,a,k)`, `m × n × N × K`) the window is
  `Bf(:, ((k-1)*N + (a-1))*n + (1:n))`.
- **Cell arrays:** `B{k}` of 2-D matrices, indexed by a loop counter
  (`@cadastruct` supports this), at the cost of less natural syntax.
- A nicer surface syntax for both (`B(:,:,a,k)` on declared N-D
  parameters) is roadmap item R2 (#11 Level 2).

## What this example does NOT cover (and what will)

- **Failure / reconfiguration masks** (evaluate with `n < N` active
  actuators without regenerating): roadmap R3 = issue #6 Tier 1
  (`Nmax` generation + runtime trip count). With the product fold, a
  failed actuator can today be masked by zeroing its cost weights and
  `B` column — exact because all couplings are linear in the per-pair
  terms.
- **Nonseparable / reduction-heavy scalar costs**: roadmap R4 (reverse
  mode) is the structurally right tool there.
