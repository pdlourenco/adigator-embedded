function results = ci_gate(folder, junitPath)
%CI_GATE  Run one gated test folder, guarded against SILENT suite loss.
%
%   results = ci_gate('integration')                      % run, no JUnit file
%   results = ci_gate('integration','results/int.xml')    % also write JUnit
%
% Replaces a bare `matlab-actions/run-tests` step, for two reasons that the
% action cannot cover from a workflow file.
%
% 1. `tests/` MUST be on the path. `AdigatorTestCase` lives there, and a class
%    that cannot resolve its base class is dropped from the suite **silently** -
%    no error, no filter, just a smaller count. On hosted CI that removed
%    every `AdigatorTestCase` subclass - 16 tests across 5 classes, in BOTH
%    gated folders (unit 201 -> 195, integration 170 -> 160) - reported as
%    "0 Failed, 0 Incomplete". See `ci_suiteGuard` for the roll-call. The
%    coverage step was no backstop: it adds the path, but `ci_coverage`
%    discards the run result and errors only on a coverage-rate regression.
%
%    Only `tests/` is added - deliberately NOT `genpath`. Every test class
%    declares the product paths it needs through a `PathFixture`, and adding
%    them globally would mask a missing one (ADR-0017 / the #81 clean-path
%    lesson). The point is to resolve the base class, nothing more.
%
% 2. Every test class file in the folder must contribute at least one test -
%    `ci_suiteGuard`, shared with `ci_local` so the guard cannot hold on CI
%    and not locally. See its header for why it is per-class and not a count.
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

import matlab.unittest.TestRunner
import matlab.unittest.plugins.XMLPlugin

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);                       % AdigatorTestCase and the ci_* helpers
root    = fileparts(thisDir);
target  = fullfile(thisDir, folder);
assert(isfolder(target), 'ci_gate:noSuchFolder', ...
    'no test folder tests/%s', folder);

ci_suiteGuard(folder);          % shared with ci_local - see its header
suite = testsuite(target);

runner = TestRunner.withTextOutput;
if nargin > 1 && ~isempty(junitPath)
    if ~isAbsolutePath(junitPath); junitPath = fullfile(root, junitPath); end
    outdir = fileparts(junitPath);
    if ~isempty(outdir) && ~isfolder(outdir); mkdir(outdir); end
    runner.addPlugin(XMLPlugin.producingJUnitFormat(junitPath));
end

results = runner.run(suite);
fprintf('ci_gate(%s): %d passed, %d failed, %d incomplete (of %d).\n', ...
    folder, nnz([results.Passed]), nnz([results.Failed]), ...
    nnz([results.Incomplete]), numel(suite));
assertSuccess(results);
end

function tf = isAbsolutePath(p)
tf = ~isempty(regexp(p, '^([A-Za-z]:[\\/]|[\\/])', 'once'));
end
