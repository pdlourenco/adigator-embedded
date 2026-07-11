% Demonstrates STRUCT INPUTS through the convenience/embedded wrappers
% (issue #24, scope A): the inputs to the user function are carried as
% fields of a single scalar struct, and the derivative variable is one of
% those fields. Auxiliary fields are used internally and pass through.
%
% Cases exercised (all with struct inputs):
%   1) flat   Hessian, classic   - derivative field at the top level (in.x)
%   2) nested Hessian, classic   - derivative field one level deeper
%                                  (in.vars.x; aux in a sibling sub-struct)
%   3) Jacobian, classic         - vector-valued function (in.x)
%   4) flat   Hessian, embed 'i' - same struct objective through the
%                                  embedded (inline) pipeline; round-trips
%                                  and matches the classic/analytic result
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public License v3.0.
clc; clear;
fprintf('AdiGator example: %s\n', mfilename('fullpath'));

n = 4;
opts = adigatorOptions();
opts.overwrite = 1;

% Common evaluation point / parameters and closed-form references.
rng(0);
Q = randn(n); Q = Q + Q.';     % symmetric
c = randn(n,1);
x = randn(n,1);
Gref = Q*x + c;                % grad of 1/2 x'Qx + c'x
Href = Q;                      % hess
Fref = 0.5*(x.'*(Q*x)) + c.'*x;

% --------------------- 1) flat struct, Hessian, classic --------------- %
o = opts; o.path = 'generated/flat';
gin.x = adigatorCreateDerivInput([n 1],'x');
gin.Q = adigatorCreateAuxInput([n n]);
gin.c = adigatorCreateAuxInput([n 1]);
adigatorGenHesFile('structobj',{gin},o);
in.x = x; in.Q = Q; in.c = c;
[F,G,H] = runHes('structobj_Hes', o.path, in);
checkder('flat classic (in.x)', F,G,H, Fref,Gref,Href);

% -------------------- 2) nested struct, Hessian, classic -------------- %
o = opts; o.path = 'generated/nested';
gin2.vars.x = adigatorCreateDerivInput([n 1],'x');
gin2.par.Q  = adigatorCreateAuxInput([n n]);
gin2.par.c  = adigatorCreateAuxInput([n 1]);
adigatorGenHesFile('structobj_nested',{gin2},o);
in2.vars.x = x; in2.par.Q = Q; in2.par.c = c;
[F2,G2,H2] = runHes('structobj_nested_Hes', o.path, in2);
checkder('nested classic (in.vars.x)', F2,G2,H2, Fref,Gref,Href);

% ----------------- 3) Jacobian of a vector function, classic ---------- %
m = 3;
A = randn(m,n); b = randn(m,1);
o = opts; o.path = 'generated/jac';
ginj.x = adigatorCreateDerivInput([n 1],'x');
ginj.A = adigatorCreateAuxInput([m n]);
ginj.b = adigatorCreateAuxInput([m 1]);
adigatorGenJacFile('structvecfun',{ginj},o);
inj.x = x; inj.A = A; inj.b = b;
clear structvecfun_Jac structvecfun_ADiGatorJac
addpath(fullfile(pwd,o.path)); rehash;
[J,Y] = structvecfun_Jac(inj);
rmpath(fullfile(pwd,o.path));
jerr = norm(J(:) - reshape(A,[],1), inf);
yerr = norm(Y(:) - (A*x+b), inf);
fprintf('%-28s jac %.3g | val %.3g\n', 'jacobian classic (in.x)', jerr, yerr);
assert(jerr < 1e-10 && yerr < 1e-10, 'structinput: Jacobian case disagrees with reference');

% --------------- 4) flat struct, Hessian, embedded inline ('i') ------- %
% Same struct objective, generated through the embedded (inline) pipeline,
% confirming struct inputs survive prune/patch/inline and round-trip.
o = opts; o.path = 'generated/embed_i'; o.embed_mode = 'i';
gine.x = adigatorCreateDerivInput([n 1],'x');
gine.Q = adigatorCreateAuxInput([n n]);
gine.c = adigatorCreateAuxInput([n 1]);
adigatorGenDerFile_embedded('hessian','structobj',{gine},o);
% drop the classic-mode structobj_Hes (case 1) so the inline one is picked
clear structobj_Hes structobj_ADiGatorHes structobj_Grd structobj_ADiGatorGrd
% Evaluating inline ('i') output uses coder.const, which needs the coder.*
% namespace (MATLAB Coder) to run in plain MATLAB; generation always runs,
% the evaluation is skipped (not failed) when Coder is unavailable.
try
  [Fe,Ge,He] = runHes('structobj_Hes', o.path, in);
  checkder('inline embed (in.x)', Fe,Ge,He, Fref,Gref,Href);
catch e
  if strcmp(e.identifier,'MATLAB:UndefinedFunction') && contains(e.message,'coder.')
    fprintf('%-28s skipped (MATLAB Coder coder.* namespace unavailable)\n', 'inline embed (in.x)');
  else
    rethrow(e);
  end
end

fprintf('structinput example passed.\n');

% ----------------------------------------------------------------------- %
function [F,G,H] = runHes(fname, p, in)
% Evaluate a generated <name>_Hes, returning [Fun,Grd,Hes]. Clears any
% stale cached copy so the version on path p is the one that runs.
clear(fname);
addpath(fullfile(pwd,p)); rehash;
[H,G,F] = feval(fname, in);
rmpath(fullfile(pwd,p));
end

function checkder(name, F,G,H, Fref,Gref,Href)
ferr = abs(F - Fref);
gerr = norm(G(:) - Gref(:), inf);
herr = norm(H(:) - Href(:), inf);
fprintf('%-28s value %.3g | grad %.3g | hess %.3g\n', name, ferr, gerr, herr);
assert(ferr < 1e-10 && gerr < 1e-10 && herr < 1e-10, ...
  'structinput (%s): generated derivatives disagree with the analytic reference', name);
end
