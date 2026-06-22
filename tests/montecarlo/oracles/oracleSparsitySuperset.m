function r = oracleSparsitySuperset(c)
%ORACLESPARSITYSUPERSET  Structure ⊇ numeric nonzeros (REQ-T-03, ADR-0007).
%
% A structural oracle that needs no derivative reference: the declared
% output.{Jacobian|Hessian}Structure must cover every numerically nonzero
% entry of the evaluated derivative at c.x0. Catches the B10-class metadata
% drift where the exported sparsity pattern disagrees with the wrapper's
% element placement.
r = struct('name','sparsitySuperset','pass',true,'skipped',false,'message','');

g = mcGenClassic(c);
S = g.structure;
if isempty(S)
    r.skipped = true; r.message = 'no structure exported'; return;
end

switch c.deriv
    case 'jacobian'
        out = mcEval(g.wrapper, 2, c.x0); D = out{1};
    case 'gradient'
        out = mcEval(g.wrapper, 2, c.x0); D = out{1};
    case 'hessian'
        out = mcEval(g.wrapper, 3, c.x0); D = out{1};
end

% Sparsity is position-based; a vector derivative and its structure may be
% stored in different orientations, so compare as columns when either is a
% vector.
if isvector(D) || isvector(S)
    D = D(:); S = S(:);
end
if ~isequal(size(D), size(full(S)))
    r.pass = false;
    r.message = sprintf('structure size %s != derivative size %s', ...
        mat2str(size(S)), mat2str(size(D)));
    return;
end

tol = 1e-12;
nz = abs(D) > tol;                 % numerically nonzero entries
covered = (full(S) ~= 0);          % declared-structural entries
viol = nz & ~covered;
if any(viol(:))
    r.pass = false;
    r.message = sprintf('%d numerically-nonzero entries are outside the declared structure', ...
        nnz(viol));
end
end
