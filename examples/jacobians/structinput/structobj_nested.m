function f = structobj_nested(in)
% Same quadratic objective as structobj.m, but with the inputs nested one
% level deeper to exercise struct-in-struct derivative inputs (issue #24):
%   in.vars.x : optimization variable, differentiated with respect to
%   in.par.Q  : symmetric weight matrix (auxiliary)
%   in.par.c  : linear term            (auxiliary)
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public License v3.0.
f = 0.5*(in.vars.x.'*(in.par.Q*in.vars.x)) + in.par.c.'*in.vars.x;
end
