function results = ci_prepush()
%CI_PREPUSH  Fast, clean-path PR-gate equivalent for the pre-push hook (#82).
%
% Runs the same gate as CI's PR runner - lint + unit + integration - and
% NOTHING that is not on that gate (the system/Coder suite is the heavier,
% Coder-gated extended run; use ci_local for the full local gate including it).
%
% The point is the CLEAN PATH: invoke it in a FRESH `matlab -batch` so only
% `tests/` is on the path and each test class supplies its own source paths
% (via AdigatorTestCase or its own TestClassSetup). Running it this way
% reproduces CI exactly - PR #81 went red because a dirty interactive path,
% or an `addpath(genpath(pwd))`, masked a test class missing its PathFixture.
%
%   matlab -batch "addpath('tests'); ci_prepush"
%
% Wired by .githooks/pre-push; see CONTRIBUTING.md §"Local development &
% pre-push CI".
%
%   Copyright 2026 Pedro Lourenço @ GMV. Distributed under the GNU General
%   Public License version 3.0.

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

ci_lint();

results = runtests({fullfile(thisDir,'unit'), fullfile(thisDir,'integration')});
disp(table(results));
assertSuccess(results);
end
