function g = mcGenClassic(c)
%MCGENCLASSIC  Generate the classic derivative file for a case in the cwd.
%
% Assumes the current folder is a fresh working directory that already
% contains the case fixture (written by the caller via writeFixtureFile) and
% is on the MATLAB path. Generates the requested derivative with the
% user-facing wrappers (which also return output.*Structure), and returns:
%   g.wrapper   - generated function name to call, [Jac|Grd|Hes, ...]
%   g.structure - sparse {Jacobian|Hessian}Structure (ones/zeros)
%   g.kind      - 'jacobian' | 'gradient' | 'hessian'
ax = adigatorCreateDerivInput(c.xsize, 'x');
opts = struct('echo', 0, 'overwrite', 1);

switch c.deriv
    case 'jacobian'
        out = adigatorGenJacFile(c.name, {ax}, opts);
        g.wrapper = [c.name '_Jac'];
        g.structure = cscPattern(out.JacobianCSC);   % v2.0 (#192, ADR-0030)
    case 'gradient'
        out = adigatorGenJacFile(c.name, {ax}, opts, 'Grd');
        g.wrapper = [c.name '_Grd'];
        g.structure = cscPattern(out.GradientCSC);    % scalar-fn gradient role
    case 'hessian'
        out = adigatorGenHesFile(c.name, {ax}, opts);
        g.wrapper = [c.name '_Hes'];
        g.structure = cscPattern(out.HessianCSC);
    otherwise
        error('mcGenClassic:deriv', 'unsupported deriv "%s"', c.deriv);
end
g.kind = c.deriv;
rehash;
end

function S = cscPattern(csc)
% v2.0 (#192, ADR-0030): the structural sparse pattern reconstructed from the
% sole CSC metadata (the old out.*Structure convenience field is removed).
S = adigatorCSCToSparse(csc, ones(csc.Nnz, 1)) ~= 0;
end
