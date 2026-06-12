function y = lse_cost(x,w)
% Weighted log-sum-exp scalar cost (roadmap R4 reverse-mode example):
% a dense-gradient objective where forward mode costs O(n) passes and the
% reverse (adjoint) sweep costs O(1) function evaluations.
y = log(sum(exp(w.*x)));
end
