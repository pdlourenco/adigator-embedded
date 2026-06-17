% Demonstrates STRUCT INPUTS through the convenience wrappers (issue #24,
% scope A): the inputs to the user function are carried as fields of a
% single scalar struct, and the derivative variable is one of those fields
% (in.x). The auxiliary fields (in.Q, in.c) are used internally and pass
% through unchanged.
%
% The generated wrapper accepts the same struct shape at evaluation time:
%   [H,G,F] = structobj_Hes(in)
% with in.x the point of evaluation and in.Q/in.c the parameters.
%
% Copyright GMV. Distributed under the GNU General Public License v3.0.
clc; clear;
fprintf('AdiGator example: %s\n', mfilename('fullpath'));

n = 4;

% ------------------------------ ADiGator ------------------------------- %
opts = adigatorOptions();
opts.path = 'test';
opts.overwrite = 1;

% Build the struct input: a derivative field plus auxiliary fields.
gin.x = adigatorCreateDerivInput([n 1],'x');
gin.Q = adigatorCreateAuxInput([n n]);
gin.c = adigatorCreateAuxInput([n 1]);

% Gradient + Hessian wrapper (also writes structobj_Grd).
adigatorGenHesFile('structobj',{gin},opts);
addpath(fullfile(pwd,opts.path));

% ----------------------------- Evaluate -------------------------------- %
rng(0);
Q = randn(n); Q = Q + Q.';     % symmetric
c = randn(n,1);
x = randn(n,1);

in.x = x; in.Q = Q; in.c = c;  % same struct shape, numeric values
[H,G,F] = structobj_Hes(in);

rmpath(fullfile(pwd,opts.path));

% --------------------------- Check vs analytic ------------------------- %
Gref = Q*x + c;     % grad
Href = Q;           % hess
Fref = 0.5*(x.'*(Q*x)) + c.'*x;

gerr = norm(G(:) - Gref(:), inf);
herr = norm(H(:) - Href(:), inf);
ferr = abs(F - Fref);

fprintf('value error    : %g\n', ferr);
fprintf('gradient error : %g\n', gerr);
fprintf('Hessian error  : %g\n', herr);

assert(ferr < 1e-10 && gerr < 1e-10 && herr < 1e-10, ...
  'structinput example: generated derivatives disagree with the analytic reference');
fprintf('structinput example passed.\n');
