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
% f: Rn -> Rm
% x in Rn
%
% Hessian(f)_x = [d2f/dx1dx1  ... d2f/dx1dxn
%                 ...
%                 d2f/dxndx1  ... d2f/dxndxn]
%
% size(Gradient(f)) = [length(x) length(f)]
%
% usage in computations: x' * Hessian_x(f) * x


%%% VECTOR FUNCTION OF VECTOR VARIABLE (JACOBIAN)
% f: Rn -> Rm
% x in Rn
%
% Jacobian(f)_x = [df1/dx1  ... df1/dxn
%                  ...
%                  dfm/dx1   ... dfn/dxn]
%
% size(Gradient(f)) = [length(x) length(f)]
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
