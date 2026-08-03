function results = ci_local()
%CI_LOCAL  Run the CI gate locally in the current MATLAB session.
%
% License-free way to get the CI verdict before pushing (docs/CI_PLAN.md
% §3.3); can be wired as a git pre-push hook:
%   matlab -batch "addpath('tests'); ci_local"

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

ci_lint();

% Same guard the CI gate runs (ci_gate -> ci_suiteGuard): a test class that
% cannot load vanishes from the suite silently rather than failing, so a green
% run can mean "fewer tests" instead of "all passing". Run it here too, or the
% pre-push check is weaker than the gate it stands in for.
ci_suiteGuard('unit');
ci_suiteGuard('integration');
ci_suiteGuard('system');   % three AdigatorTestCase subclasses live here too

% system tests skip via assumption when licensed products are unavailable
results = runtests({fullfile(thisDir,'unit'), fullfile(thisDir,'integration'), ...
    fullfile(thisDir,'system')});
disp(table(results));
assertSuccess(results);
end
