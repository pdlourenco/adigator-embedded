function D = casadiDeriv(fn, DerType, xv)
% casadiDeriv  Dense derivative of a showcase function via CasADi.
%
%   D = casadiDeriv(FN, DERTYPE, XV) returns the DERTYPE derivative of function
%   FN evaluated at the column point XV, computed by CasADi (a symbolic
%   expression-graph AD, a method entirely independent of ADiGator's source
%   transformation). It is the independent ground truth for SCasadiOracleTest.
%
%   DERTYPE is 'jacobian' | 'gradient' | 'gradient-reverse' | 'hessian'.
%   (gradient and gradient-reverse share a value - the gradient - so reverse
%   mode is validated against the same CasADi gradient.)
%
%   The SAME unmodified source m-file feeds both engines: ADiGator overloads via
%   @cada, CasADi via the SX symbolic type, so passing an SX symbol into FN
%   returns an SX expression with no hand-transcription of the math (the
%   transcription gap is exactly what an oracle must not have). Comparison is on
%   reconstructed DENSE values, so the two engines' differing sparse layouts /
%   nonzero orderings never enter.
%
%   Throws if FN is not SX-consumable - e.g. preallocation followed by an indexed
%   symbolic store, `y = zeros(n,1); y(k) = <expr>` (as in vfun), which CasADi
%   cannot assign into a double array. The caller treats that as "skip this
%   case": such a function's math is covered by its vectorized sibling (vfun by
%   vvecfun) and by the cross-mode / analytic oracles.
%
%   See ADR-0018 and issue #87.
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

    import casadi.*
    xv = xv(:);
    n  = numel(xv);
    x  = SX.sym('x', n);

    fx = feval(fn, x);             % same source m-file; may throw if not SX-consumable

    switch DerType
        case 'jacobian'
            expr = jacobian(fx, x);
        case {'gradient', 'gradient-reverse'}
            expr = jacobian(fx, x).';   % fx scalar -> 1xn row; transpose to the C-6 nx1 column
        case 'hessian'
            expr = hessian(fx, x);
        otherwise
            error('casadiDeriv:DerType', 'unsupported DerType ''%s''', DerType);
    end

    f = Function('f', {x}, {expr});
    D = full(f(xv));
end
