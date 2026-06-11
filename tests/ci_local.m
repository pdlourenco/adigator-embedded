function results = ci_local()
%CI_LOCAL  Run the CI gate locally in the current MATLAB session.
%
% License-free way to get the CI verdict before pushing (docs/CI_PLAN.md
% §3.3); can be wired as a git pre-push hook:
%   matlab -batch "addpath('tests'); ci_local"

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

ci_lint();

% system tests skip via assumption when licensed products are unavailable
results = runtests({fullfile(thisDir,'unit'), fullfile(thisDir,'integration'), ...
    fullfile(thisDir,'system')});
disp(table(results));
assertSuccess(results);
end
