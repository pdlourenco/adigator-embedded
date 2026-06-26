function y = vcostfun(x)
% vcostfun  Vectorized scalar cost (no loop, no subscripting) - its reverse
% gradient references no index tables, so the embedded reverse file carries ZERO
% static data (ANALYSIS §3.5). The R17 showcase contrast to scostfun's rolled,
% subscripted form (which carries reverse index maps).
y = sum(exp(x) + 2*x);
end
