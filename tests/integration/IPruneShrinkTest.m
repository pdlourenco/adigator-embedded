classdef IPruneShrinkTest < matlab.unittest.TestCase
    % IPruneShrinkTest  Slice-before-prune data half (issue #21, ADR-0010) in
    % the CI gate.
    %
    % Thin wrapper around the license-free core tests/offline/
    % prune_shrink_offline_checks.m, which exercises the REAL
    % embedding/adigatorReferencedIndex and embedding/prune_adigator_mat (both
    % char/cellstr + regexp, so they run in base MATLAB and GNU Octave alike) on
    % hand-written generated-derivative snippets AND on the committed slim1
    % fixture: it confirms the scanner maps the referenced Gator<d>Data.Index<n>
    % per function, keep-alls on non-literal table use, and that the prune drops
    % the unread index (the orphan Index7 of the real fixture) while preserving a
    % referenced-but-unindexed table via the unshrunk fallback.
    %
    % The core stays runnable license-free for local verification (it only needs
    % char/regexp, no MATLAB toolbox); this wrapper puts it in the MATLAB CI
    % gate. See ADR-0008 for the offline-core / matlab.unittest-wrapper split.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(root, 'tests', 'offline')));
            tc.applyFixture(PathFixture(fullfile(root, 'embedding')));
        end
    end

    methods (Test)
        function offlineCoreChecksPass(tc)
            r = prune_shrink_offline_checks();   % errors internally on any mismatch
            tc.verifyGreaterThan(r.checks, 0, 'the offline core ran no checks');
        end
    end
end
