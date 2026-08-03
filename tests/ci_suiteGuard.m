function suite = ci_suiteGuard(folder)
%CI_SUITEGUARD  Fail if any test class in tests/<folder> contributes no tests.
%
%   suite = ci_suiteGuard('integration')   % returns it, so callers need
%                                          % not build the suite twice
%
% A test class that cannot load is dropped from the suite **silently**. It does
% not fail and it is not filtered — it disappears, and the run still reports
% `0 Failed, 0 Incomplete` against a smaller total. Nothing about that looks
% wrong in a log.
%
% That is not hypothetical. `matlab-actions/run-tests` cannot put `tests/` on
% the path, so on hosted CI every class deriving from `AdigatorTestCase` lost
% its base class and vanished — **16 tests across 5 classes**, in both gated
% folders:
%
%   unit         UStripDeadOutputIndicesTest (5), UTestPathHygieneTest (1)
%   integration  IRolledOvermapWidthTest (4, TS-I-29, the #217/B37 regression
%                net), IScatterPrototypeTest (4, TS-I-30, the R21 acceptance
%                references), IVectorizedFenceTest (2, TS-I-31, the B40
%                tripwire)
%
% None could fail CI, across several PRs that each claimed hosted CI covered
% them. It surfaced only from an arithmetic discrepancy in the totals.
%
% The sharpest argument for a mechanical guard is in that list:
% `UTestPathHygieneTest` is the #82 meta-test that exists to catch a class
% forgetting its `PathFixture` — the #81 failure mode. The guard against
% path-related silent test loss was itself silently lost to a path problem,
% and nothing said so.
%
% Deliberately NOT a count check: a number needs bumping on every added test,
% and still misses "class A vanished while class B grew". Per class file needs
% no maintenance and names what disappeared.
%
% Shared by `ci_gate` (the CI gate) and `ci_local` (the pre-push runner) so the
% guard cannot hold in one and not the other.
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

thisDir = fileparts(mfilename('fullpath'));
target  = fullfile(thisDir, folder);
assert(isfolder(target), 'ci_suiteGuard:noSuchFolder', ...
    'no test folder tests/%s', folder);

suite = testsuite(target);
names = {};
if ~isempty(suite); names = {suite.Name}; end

d = dir(fullfile(target,'*.m'));
missing = {};
for k = 1:numel(d)
    p = fullfile(target, d(k).name);
    if ~isTestClassFile(p); continue; end
    [~, cls] = fileparts(d(k).name);
    % `Cls/method`, or `Cls[p=v]/method` when the class takes a
    % ClassSetupParameter - match either, or a fully-present parameterized
    % class would be reported as silently lost.
    pat = ['^' regexptranslate('escape', cls) '[\[/]'];
    if ~any(~cellfun('isempty', regexp(names, pat, 'once')))
        missing{end+1} = cls; %#ok<AGROW>
    end
end

if ~isempty(missing)
    error('ci_suiteGuard:silentSuiteLoss', ...
        ['tests/%s: %d test class(es) contributed NO tests to the suite: %s\n' ...
         'A class that cannot load is dropped silently — it does not fail, it ' ...
         'disappears, and the run still reports 0 Failed. The usual cause is ' ...
         'an unresolvable base class (tests/ missing from the path).'], ...
        folder, numel(missing), strjoin(missing, ', '));
end
fprintf('ci_suiteGuard: tests/%s — %d tests, every test class represented.\n', ...
    folder, numel(suite));
end

%% ---------------------------------------------------------------------- %%
function tf = isTestClassFile(p)
% A classdef whose name contains Test. Read rather than executed, so a file
% that is broken is still recognised as one that OUGHT to have contributed.
% An abstract base (`classdef (Abstract) Foo`) does not match, which is what we
% want - keep that in mind before relaxing the pattern.
tf = false;
try
    txt = fileread(p);
catch
    return
end
txt = regexprep(txt, '^\s*%[^\n]*$', '', 'lineanchors');   % drop comment lines
tf = ~isempty(regexp(txt, '^\s*classdef\s+\w*Test\w*', 'once', 'lineanchors'));
end
