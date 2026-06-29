classdef UTestPathHygieneTest < AdigatorTestCase
    % UTestPathHygieneTest  Meta-test guard (#82): every test class under
    % tests/{unit,integration} must set up its own path - either by subclassing
    % AdigatorTestCase or by declaring its own `methods (TestClassSetup)`.
    %
    % This catches, in the suite itself (so CI and the clean-path pre-push hook
    % both flag it), the PR #81 failure mode: a new test class that calls
    % embedding/ or util/ functions but forgets the PathFixture passes on a
    % dirty interactive path and only fails on CI's clean path with a cryptic
    % "Undefined function". A class with NEITHER a base class nor a
    % TestClassSetup is reported here by name instead.
    %
    % Scope: this checks that a setup mechanism is PRESENT, not that it adds the
    % RIGHT paths - a present-but-incomplete TestClassSetup is out of scope
    % (ADR-0017); the clean-path run itself catches that. (Subclasses
    % AdigatorTestCase itself, so it passes its own rule. The base class lives in
    % tests/, outside the scanned unit/integration folders.)

    methods (Test)
        function everyTestClassSetsUpItsPath(tc)
            testDir   = fileparts(mfilename('fullpath'));   % tests/unit
            repoTests = fileparts(testDir);                 % tests
            dirs = {fullfile(repoTests,'unit'), fullfile(repoTests,'integration')};

            offenders = strings(0,1);
            for d = 1:numel(dirs)
                files = dir(fullfile(dirs{d},'*.m'));
                for k = 1:numel(files)
                    txt = fileread(fullfile(files(k).folder, files(k).name));
                    % only consider files that actually declare a test class
                    if isempty(regexp(txt, 'classdef\s+\w+\s*<', 'once')); continue; end
                    extendsBase = ~isempty(regexp(txt, ...
                        'classdef\s+\w+\s*<\s*AdigatorTestCase\>', 'once'));
                    hasSetup = ~isempty(regexp(txt, ...
                        'methods\s*\(\s*TestClassSetup\s*\)', 'once'));
                    if ~(extendsBase || hasSetup)
                        offenders(end+1,1) = string(files(k).name); %#ok<AGROW>
                    end
                end
            end

            tc.verifyEmpty(offenders, sprintf([ ...
                'test class(es) with no path setup - subclass AdigatorTestCase ' ...
                'or declare a TestClassSetup PathFixture (else they pass only on ' ...
                'a dirty path and fail on CI, #82): %s'], strjoin(offenders, ', ')));
        end
    end
end
