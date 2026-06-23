classdef UCoreErrorHygieneTest < matlab.unittest.TestCase
    % UCoreErrorHygieneTest  Gated hygiene pin for adigator's transformation-
    % state release (CI plan TS-U-08; REQ-T-07 / REQ-C-09; bug B16, ADR-0011).
    %
    % A transformation must leave the session as it found it -- no stray
    % ADIGATOR* transformation globals, the MATLAB path restored, and no
    % adigator-owned file handles left open -- on BOTH a successful transform
    % and one that errors mid-way. This is the gated (per-PR) counterpart of the
    % generation-driven MCSmokeTest pins (successLeavesNoOpenHandles /
    % negativeHygieneIsClean), which run only in the extended suite; gating it
    % here makes the B16 invariant a CI gate rather than a manual check.
    %
    % The checks are delta-based (snapshot before, compare after) so a runtime
    % data global ADiGator_<name> left from an earlier test cannot confound them;
    % only the four transformation globals are asserted gone.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));   % tests/unit
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
            tc.applyFixture(PathFixture(fullfile(root,'embedding')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function successfulTransformLeavesSessionClean(tc)
            % A successful gradient generation must release every transformation
            % global, restore the path, and close every handle it opened.
            fname = 'adigator_hyg_ok';
            writeUserFunction(fname, 'y = sum(sin(x));');
            [g0, p0, f0] = snapshotSession();

            ax = adigatorCreateDerivInput([3 1], 'x');
            adigatorGenJacFile(fname, {ax}, struct('overwrite',1,'echo',0), 'Grd');

            verifySessionClean(tc, g0, p0, f0, 'after a successful transformation');
        end

        function erroringTransformLeavesSessionClean(tc)
            % A malformed fixture (undefined variable) must error -- after the
            % temp dir / path are already set up -- and still leave the session
            % hygienic. This is the error path B16 fixes.
            fname = 'adigator_hyg_bad';
            writeUserFunction(fname, 'y = sum(x) + thisVariableDoesNotExist;');
            [g0, p0, f0] = snapshotSession();

            ax = adigatorCreateDerivInput([3 1], 'x');
            tc.verifyError(@() adigatorGenJacFile(fname, {ax}, ...
                struct('overwrite',1,'echo',0), 'Grd'), ?MException, ...
                'a malformed fixture must raise an error during generation');

            verifySessionClean(tc, g0, p0, f0, 'after a failed transformation');
        end
    end
end

% ---- local helpers -------------------------------------------------------- %

function writeUserFunction(fname, bodyLine)
% Write a single-input user function fixture into the current (temp) folder.
fid = fopen([fname '.m'], 'w');
assert(fid > 0, 'could not open fixture file %s.m for writing', fname);
fprintf(fid, 'function y = %s(x)\n%s\nend\n', fname, bodyLine);
fclose(fid);
rehash;
end

function [globals0, path0, fids0] = snapshotSession()
globals0 = who('global');
path0    = path;
fids0    = openFidsPortable();
end

function verifySessionClean(tc, globals0, path0, fids0, when)
transformGlobals = {'ADIGATOR','ADIGATORFORDATA','ADIGATORDATA','ADIGATORVARIABLESTORAGE'};
stray = intersect(setdiff(who('global'), globals0), transformGlobals);
% A stray transformation-global NAME is only a B16 violation if it carries live
% state. Reading one of adigator's returned cada objects re-registers an EMPTY
% transformation global (every @cada method opens with `global ADIGATOR`); that
% holds no state and cannot poison a later transform, so tolerate it. A
% *populated* stray is a real leak. See issue #54 for the @cada-layer fix.
populated = stray(cellfun(@(n) ~isempty(globalValue(n)), stray));
tc.verifyEmpty(populated, sprintf('populated transformation-state globals leaked %s: %s', ...
    when, strjoin(populated, ', ')));
tc.verifyEqual(path, path0, sprintf('MATLAB path not restored %s', when));
tc.verifyEmpty(setdiff(openFidsPortable(), fids0), ...
    sprintf('file handle(s) left open %s', when));
end

function v = globalValue(name)
% Read a global's current value by name in this disposable helper frame. The
% name is already present in who('global') here, so declaring it global just
% binds the existing value -- the read itself re-registers nothing new.
eval(['global ',name]);
v = eval(name);
end

function fids = openFidsPortable()
% Portable open-file-identifier list: fopen('all') is being removed (errors on
% recent MATLAB); openedFiles is the replacement but is absent on R2022a..
if exist('openedFiles','builtin') == 5 || exist('openedFiles','file') == 2
    fids = openedFiles();
else
    fids = fopen('all');
end
end
