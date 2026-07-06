%% definition of derivatives
% following the conventions on https://en.wikipedia.org/wiki/Matrix_calculus

%%% SCALAR FUNCTION OF VECTOR VARIABLE (GRADIENT)
% f: Rn -> R
% x in Rn
%
% Gradient_x(f) = [df/dx1
%                  ...
%                  df/dxn]
%
% size(Gradient_x(f)) = [length(x) length(f)]
%
% usage in computations: Gradient_x(f)' * x


%%% SCALAR FUNCTION OF VECTOR VARIABLE (HESSIAN)
% f: Rn -> R
% x in Rn
%
% Hessian(f)_x = [d2f/dx1dx1  ... d2f/dx1dxn
%                 ...
%                 d2f/dxndx1  ... d2f/dxndxn]
%
% size(Hessian_x(f)) = [length(x) length(x)]
%
% usage in computations: x' * Hessian_x(f) * x


%%% VECTOR FUNCTION OF VECTOR VARIABLE (JACOBIAN)
% f: Rn -> Rm
% x in Rn
%
% Jacobian(f)_x = [df1/dx1  ... df1/dxn
%                  ...
%                  dfm/dx1   ... dfm/dxn]
%
% size(Jacobian_x(f)) = [length(f) length(x)]   % m x n (contract C-1)
%
% usage in computations: Jacobian_x(f) * x

%%% GENERALIZATION
% f: Rnxm -> Rrxc
% x in Rnxm
%
%		    c=1	    c=1	    c>1	    c>1
%		    r=1	    r>1	    r=1	    r>1
% n=1	m=1	1 x 1	r x 1	c x 1	r x c
% n=1	m>1	m x 1	r x m	c x m	r*c x m
% n>1	m=1	n x 1	r x n	c x n	r*c x n
% n>1	m>1	n x m	r x n*m	c x n*m	r*c x n*m

% all(c,r=1)                any(n,m=1) & ~all(n,m>1)		n*m x 1
% all(c,r=1)                all(n,m>1)		                n x m
%
% any(c,r=1) & any(c,r>1)			                        r*c x n*m
% all(c,r>1)	            any(n,m>1)		                r*c x n*m
% all(c,r>1)	            all(n,m=1)		                r x c

%%% GENERATED-FILE OUTPUTS: NAMES + ORDER (see docs/DESIGN.md Contract C-6)
% Every generated derivative file - forward, reverse, and matrix-free product -
% returns its outputs under these canonical variable names, the same object
% always named the same:
%
%   Fun = function value      Jv  = Jac*v   (directional derivative, R18)
%   Grd = gradient            Jtv = Jac.'*v (transposed-Jacobian-vector product)
%   Jac = Jacobian            Hv  = Hes*v   (Hessian-vector product, R18)
%   Hes = Hessian
%
% where v is a runtime input vector. Outputs are ordered highest-derivative-
% order first, with Fun LAST:
%
%   Jacobian file : [Jac, Fun]            (gradient is the m=1 Jacobian: [Grd, Fun])
%   Hessian file  : [Hes, Grd, Fun]
%   J*v   (R18)   : [Jv, Fun]
%   H*v   (R18)   : [Hv, Grd, Fun]
%
% The DER_LEVELS option (0 = Fun, 1 = first derivative, 2 = Hessian; default []
% = all levels) selects WHICH levels appear, preserving this order and always
% keeping the top level - e.g. der_levels = [1 2] on a Hessian file -> [Hes,
% Grd]; [1] on a Jacobian file -> [Jac]. It applies to ALL derivative
% generators, resolved uniformly by adigatorResolveDerLevels (roadmap R7a,
% issue #21).

%%% HIGHER-ORDER (n-th) DERIVATIVES  (see docs/DESIGN.md C-1, decisions/ADR-0020, issue #85)
% Binding convention (ADR-0020 ratified). The 'nth-derivative' DerType + n option
% and the host-side dvp/unfold utilities are the R22 implementation; each staged
% slice lands its Verified-by test as built. Here n = the requested
% top order and k a general order 1..n. With N = numel(x) and M = numel(f)
% (unrolled; N=n*m for a matrix VARIABLE shape, M=r*c for a matrix output), the
% k-th derivative D^k f has entries (i; j1..jk), output i in 1..M, deriv vars
% j_l in 1..N, and is symmetric in j1..jk.
%
%  - Native/default form: the vector of possible nonzeros (C-2) with one location
%    column per dimension (output + k deriv dims) + an exported pattern via the
%    der_output='nonzeros' / *Locs family (issue #84). DEFAULT for k>=3 (the dense
%    object is M*N^k).
%  - Optional dense fold (vec(x)->columns, vec(f)->output block, column-major with
%    i fastest and the last deriv dim as columns):
%        size = [M*N^(k-1)  x  N]
%        row  = i + (j1-1)*M + (j2-1)*M*N + ... + (j_{k-1}-1)*M*N^(k-2),  col = j_k
%        (unvec(result) = size(f); trailing deriv dim = columns, so D*V contracts
%         one order, permute-free)
%    k=1 -> [M x N] (Jacobian); k=2 -> row=(j1-1)*M+i -> [M*N x N] (vector Hessian,
%    the (x1-1)*M+y rule). Scalar-function gradient keeps its N x 1 column.
%  - dvp(D,V): derivative-vector/matrix product, V is N x s; contracts the trailing
%    dim -> order-(k-1) fold via a bare reshape (permute-free). Taylor term / HVP /
%    directional derivative are all callers. unfold(D): N-D view [M x N x ... x N]
%    for inspection. Storage stays the flat fold (embedded); dvp/unfold are host-side.
%  - Names (C-6): Der{k} for k>=3 (Grd/Jac keep k=1, Hes keeps k=2); the
%    'nth-derivative' file returns [Der{n}, ..., Hes, Grd, Fun], der_levels-selectable.
%  - Symmetry (C(N+k-1,k) unique tuples) is a later efficiency dedup, not correctness.
% Staged: scalar/scalar -> scalar-var -> scalar-fn-of-vector-var -> vector -> matrix.
