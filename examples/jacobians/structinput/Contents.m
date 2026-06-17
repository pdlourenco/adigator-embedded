% ADiGator struct-input example
%
% Copyright GMV. Distributed under the GNU General Public License version 3.0
%
% ----------------------------------------------------------------------- %
% FILES:
% structobj.m        - scalar quadratic objective, inputs carried in a flat
%                      struct (in.x derivative, in.Q/in.c auxiliary)
% structobj_nested.m - same objective with inputs nested one level deeper
%                      (in.vars.x derivative, in.par.* auxiliary)
% structvecfun.m     - vector-valued function for the Jacobian case
% main.m             - generates and checks gradient/Hessian (flat + nested)
%                      and a Jacobian, and verifies embed-mode ('c'/'l'/'i')
%                      equivalence, all with struct inputs (issue #24)
