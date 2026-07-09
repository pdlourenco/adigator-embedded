function c = mcGenShapeFuzz(uid)
%MCGENSHAPEFUZZ  Random vector-valued expression over a domain-safe op set.
%
% Broader-coverage generator (ADR-0007 Phase A): each output entry is a small
% expression drawn from operations that are differentiable everywhere (no
% log/sqrt/asin domain traps), so a randomly drawn sample point is always
% valid. No closed-form derivative is emitted, so these cases are value-checked
% by the FD secondary oracle oracleFiniteDiff (#145, ADR-0007 R9 Phase C) --
% which finite-differences the user function and compares the generated
% derivative's values -- alongside the structural cross-mode / sparsity oracles.
% (Before #145 they had no value oracle at all, so a cross-mode-consistent wrong
% value could pass.)
if nargin < 1, uid = 0; end

n = randi([2 6]);
m = randi([1 6]);
x0 = 0.5*randn(n, 1);      % modest magnitude keeps exp/products well scaled

% Domain-safe entry templates: {format, #index-slots}. Every one is smooth
% on all of R, so no rejection sampling is needed at this phase.
tpl = { ...
    'x(%d).*x(%d)', 2; ...
    'x(%d).^2',     1; ...
    'sin(x(%d))',   1; ...
    'cos(x(%d))',   1; ...
    '(x(%d) + x(%d))', 2; ...
    '(x(%d) - x(%d))', 2; ...
    '0.5.*exp(0.3.*x(%d))', 1; ...
    'x(%d).*sin(x(%d))', 2};

entries = cell(1, m);
ops = {};
for k = 1:m
    t = randi(size(tpl,1));
    idx = num2cell(randi(n, 1, tpl{t,2}));
    entries{k} = sprintf(tpl{t,1}, idx{:});
    ops{end+1} = strtrim(regexprep(tpl{t,1}, '[^a-z]', '')); %#ok<AGROW>
end
body = sprintf('y = [%s];', strjoin(entries, '; '));

name = sprintf('mc_shape_%d', uid);
c = mcCase('name', name, 'body', body, 'xsize', [n 1], ...
    'deriv', 'jacobian', 'x0', x0, ...
    'exactJac', [], ...   % no closed form; value-checked by oracleFiniteDiff (#145)
    'tags', struct('gen','shapefuzz','ops',{unique(ops)}, ...
                   'inShape',[n 1],'outShape',[m 1], ...
                   'density','sparse','order',1));
end
