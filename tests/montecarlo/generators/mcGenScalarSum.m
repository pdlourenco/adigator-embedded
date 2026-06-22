function c = mcGenScalarSum(uid)
%MCGENSCALARSUM  Random scalar cost f = sum(g(a.*x+b)), exact gradient.
%
% A scalar reduction cost (the shape reverse mode targets — ANALYSIS §3) with
% a closed-form gradient a .* g'(a.*x+b). Used by oracleFwdRev (reverse vs
% forward gradient) and the value/sparsity/cross-mode oracles. g is drawn from
% unary ops that are both smooth on R and on adigatorGenRevGradFile's supported
% active-operation list (sin/cos/tanh/atan/exp).
if nargin < 1, uid = 0; end

ops = { ...
    'sin',  @(t) cos(t); ...
    'cos',  @(t) -sin(t); ...
    'tanh', @(t) sech(t).^2; ...
    'atan', @(t) 1 ./ (1 + t.^2); ...
    'exp',  @(t) exp(t)};

n = randi([2 6]);
a = randi([-2 2], n, 1);
if all(a == 0); a(1) = 1; end
b = randi([-2 2], n, 1);
x0 = 0.4*randn(n, 1);

k = randi(size(ops,1));
gname = ops{k,1};
gp = ops{k,2};

name = sprintf('mc_ssum_%d', uid);
body = { ...
    sprintf('t = %s.*x + %s;', mat2str(a), mat2str(b)), ...
    sprintf('y = sum(%s(t));', gname)};

c = mcCase('name', name, 'body', body, 'xsize', [n 1], ...
    'deriv', 'gradient', 'x0', x0, ...
    'exactJac', @(x) a .* gp(a.*x + b), ...     % gradient, n x 1
    'tags', struct('gen','scalarsum','ops',{{gname}}, ...
                   'inShape',[n 1],'outShape',[1 1], ...
                   'density','dense','order',1,'scalarCost',true));
end
