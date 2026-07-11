function results = ci_prepush()
%CI_PREPUSH  Fast, clean-path pre-push gate for the git hook (#82).
%
% Runs the unit-level CI PR gate - lint + unit + integration. It does NOT run
% CI's coverage ratchet (ci_coverage): instrumenting coverage roughly doubles
% the runtime, and a slow hook invites `--no-verify` (ADR-0017), so the ratchet
% stays CI-only - run ci_coverage manually if you changed coverage-sensitive
% code. The system/Coder suite is likewise the heavier extended run; use
% ci_local for the full local gate (adds system).
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
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

ci_lint();

results = runtests({fullfile(thisDir,'unit'), fullfile(thisDir,'integration')});
disp(table(results));
assertSuccess(results);
end
