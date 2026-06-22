function r = oracleKnownDeriv(c)
%ORACLEKNOWNDERIV  Tolerance-free check vs an analytic derivative (ADR-0007).
%
% Generates the classic derivative for case c (assumed: cwd is a fresh
% working dir holding the fixture) and compares the evaluated derivative at
% c.x0 to the closed form the generator supplied (c.exactJac / c.exactHess).
% Skips cleanly when no closed form was provided (then the FD oracle carries
% the value check).
r = struct('name','knownDeriv','pass',true,'skipped',false,'message','');

needsHess = strcmp(c.deriv,'hessian');
if (needsHess && isempty(c.exactHess)) || (~needsHess && isempty(c.exactJac))
    r.skipped = true; r.message = 'no closed form supplied'; return;
end

g = mcGenClassic(c);
% exact construction: ADiGator computes the same products in double, so the
% agreement is to rounding, not an FD tolerance.
atol = 1e-9; rtol = 1e-9;

switch c.deriv
    case {'jacobian','gradient'}
        out = mcEval(g.wrapper, 2, c.x0);
        D = out{1};
        Dex = c.exactJac(c.x0);
        [r.pass, r.message] = closeEnough(D, Dex, atol, rtol, c.deriv);
    case 'hessian'
        out = mcEval(g.wrapper, 3, c.x0);
        H = out{1}; G = out{2};
        Hex = c.exactHess(c.x0);
        [okH, msgH] = closeEnough(H, Hex, atol, rtol, 'hessian');
        okG = true; msgG = '';
        if ~isempty(c.exactJac)
            [okG, msgG] = closeEnough(G, c.exactJac(c.x0), atol, rtol, 'gradient');
        end
        r.pass = okH && okG;
        if ~okH, r.message = msgH; elseif ~okG, r.message = msgG; end
end
end

function [ok, msg] = closeEnough(A, B, atol, rtol, what)
ok = isequal(size(A), size(B)) && ...
     all(abs(A(:)-B(:)) <= atol + rtol*abs(B(:)));
if ok
    msg = '';
else
    msg = sprintf('%s mismatch: max abs err %.3g (size A=%s, B=%s)', ...
        what, max(abs(A(:)-B(:)), [], 'omitnan'), mat2str(size(A)), mat2str(size(B)));
end
end
