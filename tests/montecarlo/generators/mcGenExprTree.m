function c = mcGenExprTree(uid)
%MCGENEXPRTREE  Nested typed expression-tree generator (ADR-0007 Phase C, #38).
%
% Unlike the flat, depth-1 mcGenShapeFuzz, this builds a *nested* expression by
% recursively composing a small, domain-safe typed op set, tracking value shape
% (a scalar vs the length-n vector) so every elementwise binary op conforms
% without rejection sampling. Two case shapes, alternating by uid parity:
%   - hessian:  scalar output  y = <scalar expr>       (Hessian, n x n)
%   - jacobian: vector output  y = [<s1>; ...; <sm>]   (m x n)
%
% No closed form is emitted, so the derivative VALUES are checked by the FD
% secondary oracle oracleFiniteDiff. Crucially, the scalar-Hessian cases this
% generator produces are the first closed-form-free *hessian* cases in the
% campaign, and they exercise the FD-Hessian path that oracleFiniteDiff gained
% in the same change (#38 Phase C) -- before this, every hessian case had a
% closed form and the FD-Hessian path was dead.
%
% Op set (Phase C PR1): all smooth on all of R, so any sample point is valid and
% no rejection sampling is needed:
%   - elementwise unary  sin, cos, scaled-exp, square, negate
%   - elementwise binary + - .*
%   - reductions         sum, and an inner product u.'*v of two subexpressions
%                        (exercises mtimes + transpose)
%   - shape ops          reshape, (double) transpose
% Vectors always stay length n (the full x), so elementwise binary operands
% always conform -- transpose is used doubled (n x 1 -> 1 x n -> n x 1) in vector
% context and singly only inside the scalar dot product. The domain-constrained
% families (interp1/interp2/ppval, inv/mldivide/mrdivide, cross, prod, sub2ind,
% repmat, cat, subsref-asgn) with domain-aware ranges + rejection sampling are
% Phase C PR2 -- they are the shipped-surface coverage gaps
% (docs/vv/cada-surface-inventory.md) that raise the correctness-path floor.

if nargin < 1, uid = 0; end

n = randi([2 6]);
x0 = 0.5*randn(n, 1);          % modest magnitude keeps square/exp well scaled
maxdepth = randi([2 4]);
opsUsed = {};

makeHess = mod(uid, 2) == 0;   % alternate scalar-Hessian / vector-Jacobian
if makeHess
    body  = sprintf('y = %s;', genScalar(maxdepth));
    deriv = 'hessian';
    m = 1;
else
    m = randi([2 6]);
    entries = cell(1, m);
    for k = 1:m
        entries{k} = genScalar(maxdepth);
    end
    body  = sprintf('y = [%s];', strjoin(entries, '; '));
    deriv = 'jacobian';
end

name = sprintf('mc_expr_%d', uid);
c = mcCase('name', name, 'body', body, 'xsize', [n 1], ...
    'deriv', deriv, 'x0', x0, ...
    'exactJac', [], 'exactHess', [], ...   % closed-form-free; FD-checked
    'tags', struct('gen','exprtree', 'ops', {unique(opsUsed)}, ...
                   'inShape', [n 1], 'outShape', [m 1], ...
                   'density', 'sparse', 'order', 1 + makeHess, ...
                   'depth', maxdepth));

    % ---- nested recursive builders (share n, opsUsed) ----------------- %
    function s = genScalar(d)
        % A source string evaluating to a scalar.
        if d <= 0, s = leafScalar(); return; end
        switch randi(6)
            case {1, 5}
                s = unary(genScalar(d-1));
            case 2
                s = sprintf('(%s %s %s)', genScalar(d-1), binop(), genScalar(d-1));
            case 3
                use('sum');
                s = sprintf('sum(%s)', genVector(d-1));
            case 4
                use('mtimes'); use('transpose');
                s = sprintf('(%s.'' * %s)', genVector(d-1), genVector(d-1));
            otherwise
                s = leafScalar();
        end
    end

    function s = genVector(d)
        % A source string evaluating to an n x 1 vector (length preserved).
        if d <= 0, s = 'x'; return; end
        switch randi(6)
            case 1
                s = unary(genVector(d-1));
            case 2
                s = sprintf('(%s %s %s)', genVector(d-1), binop(), genVector(d-1));
            case 3
                s = sprintf('(%s .* %s)', genScalar(d-1), genVector(d-1));
            case 4
                use('reshape');
                s = sprintf('reshape(%s, [%d 1])', genVector(d-1), n);
            case 5
                use('transpose');
                s = sprintf('transpose(transpose(%s))', genVector(d-1));
            otherwise
                s = 'x';
        end
    end

    function s = leafScalar()
        s = sprintf('x(%d)', randi(n));
    end

    function s = unary(sub)
        switch randi(5)
            case 1, use('sin');    s = sprintf('sin(%s)', sub);
            case 2, use('cos');    s = sprintf('cos(%s)', sub);
            case 3, use('exp');    s = sprintf('(0.5.*exp(0.3.*%s))', sub);
            case 4, use('square'); s = sprintf('(%s).^2', sub);
            otherwise, use('negate'); s = sprintf('(-%s)', sub);
        end
    end

    function o = binop()
        b = {'+', '-', '.*'};
        o = b{randi(3)};
        use(o);
    end

    function use(op)
        opsUsed{end+1} = op;
    end
end
