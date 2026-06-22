function c = mcGenElementwise(uid)
%MCGENELEMENTWISE  Random elementwise unary map y = g(a.*x+b), exact Jacobian.
%
% Known-derivative-by-construction generator that exercises the cadaunarymath
% rule table (REQ-C-01) under randomization: for a smooth unary g the Jacobian
% of y = g(a.*x + b) is the diagonal diag(a .* g'(a.*x+b)), checkable without
% finite differences. g is drawn from operations that are smooth on all of R,
% so any random x is in-domain. The diagonal Jacobian also exercises the
% structurally-sparse projection path.
if nargin < 1, uid = 0; end

% {name, derivative-handle}. All smooth on R; exp is kept well-scaled by the
% modest argument range below.
ops = { ...
    'sin',  @(t) cos(t); ...
    'cos',  @(t) -sin(t); ...
    'tanh', @(t) sech(t).^2; ...   % mirror cadaunarymath's emitted form exactly
    'atan', @(t) 1 ./ (1 + t.^2); ...
    'exp',  @(t) exp(t)};

n = randi([2 6]);
a = randi([-2 2], n, 1);
if all(a == 0); a(1) = 1; end       % keep at least one nonzero slope
b = randi([-2 2], n, 1);
x0 = 0.4*randn(n, 1);               % arg stays in ~[-3,3] -> exp well scaled

k = randi(size(ops,1));
gname = ops{k,1};
gp = ops{k,2};

name = sprintf('mc_elem_%d', uid);
body = { ...
    sprintf('t = %s.*x + %s;', mat2str(a), mat2str(b)), ...
    sprintf('y = %s(t);', gname)};

c = mcCase('name', name, 'body', body, 'xsize', [n 1], ...
    'deriv', 'jacobian', 'x0', x0, ...
    'exactJac', @(x) diag(a .* gp(a.*x + b)), ...
    'tags', struct('gen','elementwise','ops',{{gname}}, ...
                   'inShape',[n 1],'outShape',[n 1], ...
                   'density','sparse','order',1));
end
