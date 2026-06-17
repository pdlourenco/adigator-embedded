% Demonstrates STRUCT INPUTS through the convenience wrappers (issue #24,
% scope A): the inputs to the user function are carried as fields of a
% single scalar struct, and the derivative variable is one of those fields.
% The auxiliary fields are used internally and pass through unchanged.
%
% Two cases are shown:
%   1) flat   - derivative field at the top level of the struct (in.x)
%   2) nested - derivative field one level deeper (in.vars.x), with the
%               auxiliary parameters in a sibling sub-struct (in.par.*)
%
% The generated wrapper accepts the same struct shape at evaluation time,
% e.g. [H,G,F] = structobj_Hes(in).
%
% Copyright GMV. Distributed under the GNU General Public License v3.0.
clc; clear;
fprintf('AdiGator example: %s\n', mfilename('fullpath'));

n = 4;

opts = adigatorOptions();
opts.path = 'test';
opts.overwrite = 1;

% Common evaluation point and parameters / closed-form references.
rng(0);
Q = randn(n); Q = Q + Q.';     % symmetric
c = randn(n,1);
x = randn(n,1);
Gref = Q*x + c;                % grad
Href = Q;                      % hess
Fref = 0.5*(x.'*(Q*x)) + c.'*x;

% ----------------------- Case 1: flat struct input -------------------- %
gin.x = adigatorCreateDerivInput([n 1],'x');
gin.Q = adigatorCreateAuxInput([n n]);
gin.c = adigatorCreateAuxInput([n 1]);
adigatorGenHesFile('structobj',{gin},opts);

addpath(fullfile(pwd,opts.path));
in.x = x; in.Q = Q; in.c = c;
[H,G,F] = structobj_Hes(in);
rmpath(fullfile(pwd,opts.path));

checkcase('flat (in.x)', F,G,H, Fref,Gref,Href);

% --------------------- Case 2: nested struct input -------------------- %
gin2.vars.x = adigatorCreateDerivInput([n 1],'x');
gin2.par.Q  = adigatorCreateAuxInput([n n]);
gin2.par.c  = adigatorCreateAuxInput([n 1]);
adigatorGenHesFile('structobj_nested',{gin2},opts);

addpath(fullfile(pwd,opts.path));
in2.vars.x = x; in2.par.Q = Q; in2.par.c = c;
[H2,G2,F2] = structobj_nested_Hes(in2);
rmpath(fullfile(pwd,opts.path));

checkcase('nested (in.vars.x)', F2,G2,H2, Fref,Gref,Href);

fprintf('structinput example passed.\n');

% ---------------------------------------------------------------------- %
function checkcase(name, F,G,H, Fref,Gref,Href)
ferr = abs(F - Fref);
gerr = norm(G(:) - Gref(:), inf);
herr = norm(H(:) - Href(:), inf);
fprintf('%-22s value %.3g | grad %.3g | hess %.3g\n', name, ferr, gerr, herr);
assert(ferr < 1e-10 && gerr < 1e-10 && herr < 1e-10, ...
  'structinput example (%s): generated derivatives disagree with the analytic reference', name);
end
