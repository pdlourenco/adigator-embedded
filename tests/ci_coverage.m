function ci_coverage()
%CI_COVERAGE  Coverage report + ratchet (CI plan Phase 4).
%
% Re-runs the PR-gate suites under coverage instrumentation of lib/, util/,
% and embedding/, writes results/coverage.xml (Cobertura), and prints the
% aggregate line rate. If tests/coverage_baseline.txt is committed, errors
% when the rate falls more than 0.5 percentage points below it (small
% tolerance for instrumentation/line-count jitter). Without a baseline the
% rate is reported only.
%
% Test failures are NOT gated here (the run-tests CI steps own that); this
% step only measures coverage.

thisDir = fileparts(mfilename('fullpath'));
root = fileparts(thisDir);

import matlab.unittest.TestRunner
import matlab.unittest.plugins.CodeCoveragePlugin
import matlab.unittest.plugins.codecoverage.CoberturaFormat

suite = [testsuite(fullfile(thisDir,'unit')), ...
         testsuite(fullfile(thisDir,'integration'))];

resdir = fullfile(root,'results');
if ~isfolder(resdir); mkdir(resdir); end
covfile = fullfile(resdir,'coverage.xml');

runner = TestRunner.withTextOutput;
runner.addPlugin(CodeCoveragePlugin.forFolder( ...
    {fullfile(root,'lib'), fullfile(root,'util'), fullfile(root,'embedding')}, ...
    'IncludingSubfolders', true, 'Producing', CoberturaFormat(covfile)));
runner.run(suite);

doc = xmlread(covfile);
rate = str2double(char(doc.getDocumentElement.getAttribute('line-rate')));
fprintf('ci_coverage: aggregate line rate %.4f (%.1f%%)\n', rate, 100*rate);

basefile = fullfile(thisDir,'coverage_baseline.txt');
if isfile(basefile)
    base = str2double(strtrim(fileread(basefile)));
    fprintf('ci_coverage: baseline %.4f\n', base);
    if rate < base - 0.005
        error('ci_coverage:regression', ...
            'aggregate line rate %.4f fell below baseline %.4f', rate, base);
    elseif rate > base
        fprintf(['ci_coverage: above baseline; consider tightening ', ...
            'tests/coverage_baseline.txt to %.4f.\n'], rate);
    end
else
    fprintf(['ci_coverage: no baseline committed ', ...
        '(tests/coverage_baseline.txt); reporting only.\n']);
end
end
