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
% and a number that gets routinely bumped is one people bump without reading —
% the same dynamic that let 195-vs-201 and 160-vs-170 sit unnoticed. Per class
% file needs no maintenance and names what disappeared.
%
% Known gap, stated so it is not mistaken for coverage: a class that survives
% but loses SOME of its methods still contributes >= 1 test and passes here. A
% per-class count RATCHET (committed baseline, failing only on a drop, in the
% idiom of coverage_baseline_folders.txt / ADR-0032) would catch that; tracked
% separately rather than folded in.
%
% Shared by `ci_gate` (the CI gate), `ci_local` and `ci_prepush` (the pre-push
% hook) so the guard cannot hold in one and not the others.
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
% A file that OUGHT to contribute tests: a classdef declaring a `methods (Test)`
% block. Read rather than executed, so a class that is broken — the whole point
% of this guard — is still recognised as one that should have contributed.
%
% Deliberately NOT keyed on the file name matching *Test*, for two reasons:
%
%   * a shared BASE class matches by name. `AdigatorTestCase` is not abstract
%     and its name contains "Test", so a name-based check would report it as
%     silently lost the moment such a base sat in a scanned folder — leaving
%     file location as the only protection, which is not a property worth
%     resting on. It declares no `methods (Test)`, so the block check excludes
%     it by substance instead, wherever it lives.
%   * a test class not following the naming convention would otherwise go
%     unguarded — exactly the blind spot this function exists to remove.
%
% Verified across the four test folders: 64 classdefs, all 64 declare a
% `methods (Test...)` block, and `AdigatorTestCase` declares none.
%
% The word boundary after Test is load-bearing, not decoration: without it
% `methods (TestClassSetup)` matches, and `AdigatorTestCase` has one of those —
% so dropping it silently reintroduces the very false positive this rewrite
% removed. `\<Test\>` still admits attributes, e.g. `methods (Test, TestTags=…)`.
tf = false;
try
    txt = fileread(p);
catch
    return
end
txt = regexprep(txt, '^[^\S\r\n]*%[^\r\n]*$', '', 'lineanchors');  % strip comments
isClass  = ~isempty(regexp(txt, '^\s*classdef\>', 'once', 'lineanchors'));
hasTests = ~isempty(regexp(txt, 'methods\s*\(\s*\<Test\>', 'once'));
tf = isClass && hasTests;
end
