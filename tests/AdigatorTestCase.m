classdef AdigatorTestCase < matlab.unittest.TestCase
    % AdigatorTestCase  Shared base class for ADiGator-embedded tests.
    %
    % Puts the repo source folders (root, lib, lib/cadaUtils, util, embedding)
    % on the MATLAB path via a TestClassSetup PathFixture, so a test class does
    % not have to hand-roll the fixture - and, crucially, cannot silently FORGET
    % it and then pass only because the developer's interactive session already
    % had those folders on the path (the PR #81 "dirty path" failure: green
    % locally, red on CI's clean path). Subclass this instead of
    % matlab.unittest.TestCase.
    %
    % The PathFixture auto-restores at class teardown, so the paths do not leak
    % into other classes. A subclass that needs EXTRA paths (e.g. bench/,
    % tests/fixtures) just declares its own `methods (TestClassSetup)` adding
    % them, using a DIFFERENT method name than addAdigatorPaths - MATLAB runs
    % the (differently-named) setup methods of every class in the hierarchy, so
    % the base paths and the extra paths are both applied. (Reusing the name
    % addAdigatorPaths would override the base and drop its paths.)
    %
    % See issue #82 (the pre-push hook + this guard) and CONTRIBUTING.md
    % §"Local development & pre-push CI".
    %
    %   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
    %   Public License version 3.0.

    methods (TestClassSetup)
        function addAdigatorPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            % this file lives in tests/, so the parent of its folder is the root.
            root = fileparts(fileparts(mfilename('fullpath')));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
            tc.applyFixture(PathFixture(fullfile(root,'embedding')));
        end
    end
end
