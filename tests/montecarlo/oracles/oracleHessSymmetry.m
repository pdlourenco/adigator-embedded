function r = oracleHessSymmetry(c)
%ORACLEHESSSYMMETRY  Second derivatives are symmetric (ADR-0007 Phase B).
%
% A cheap structural oracle for scalar Hessian cases: the generated Hessian
% must equal its transpose. Catches index-multiplier / placement bugs in the
% Hessian wrapper (the B7/B8 family) that break symmetry. Skips cleanly for
% non-Hessian cases. Tight tolerance, not literal equality: a correct Hessian
% can differ from its transpose by rounding when the two halves come from
% different accumulation orders.
r = struct('name','hessSymmetry','pass',true,'skipped',false,'message','');

if ~strcmp(c.deriv, 'hessian')
    r.skipped = true; r.message = 'not a Hessian case'; return;
end

g = mcGenClassic(c);
out = mcEval(g.wrapper, 3, c.x0);
H = out{1};

if ~ismatrix(H) || size(H,1) ~= size(H,2)
    r.pass = false;
    r.message = sprintf('Hessian is not square: size %s', mat2str(size(H)));
    return;
end

asym = max(abs(H(:) - reshape(H.', [], 1)), [], 'omitnan');
tol = 1e-9 * max(1, max(abs(H(:)), [], 'omitnan'));
if asym > tol
    r.pass = false;
    r.message = sprintf('Hessian not symmetric: max |H - H''| = %.3g', asym);
end
end
