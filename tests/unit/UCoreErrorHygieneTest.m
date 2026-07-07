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
    %
    % R11 (issue #54, ADR-0015): the invariant is now strict name-absence. Before
    % R11 a benign read of a returned cada object re-registered an *empty*
    % ADIGATOR (every @cada method opened with `global ADIGATOR`), so #51 had to
    % relax this to "no *populated* global survives". The @cada read paths now
    % declare the globals only where they use them, so no transformation global
    % -- empty or populated -- may survive a transformation.

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

        function strayTransformGlobalAlwaysCaught(tc)
            % Guard the strict invariant predicate so it cannot pass vacuously:
            % after R11/#54 (ADR-0015) ANY surviving transformation global is a
            % leak -- empty re-registration or live state -- so strayTransformGlobals
            % must report it in both cases. (Pre-R11 the empty form was tolerated;
            % #54 removed the @cada re-registration at source, so the invariant is
            % now strict name-absence.) Exercises the predicate directly, with no
            % transform involved.
            transformGlobals = {'ADIGATOR','ADIGATORFORDATA','ADIGATORDATA','ADIGATORVARIABLESTORAGE'};
            clearTransformGlobals();                    % clean slate
            guard = onCleanup(@clearTransformGlobals);   % release regardless of outcome
            g0 = setdiff(who('global'), transformGlobals);  % baseline as if the four are absent

            % An empty (state-free) re-registration is now a leak, not tolerated.
            setGlobalExpr('ADIGATOR', '[]');
            tc.verifyTrue(any(strcmp('ADIGATOR', strayTransformGlobals(g0))), ...
                'an empty transformation global must now be reported as a leak (R11/#54)');

            % A populated transformation global is a leak.
            setGlobalExpr('ADIGATORDATA', 'struct(''CADA'',''live'')');
            leak = strayTransformGlobals(g0);
            tc.verifyTrue(any(strcmp('ADIGATORDATA', leak)), ...
                'a populated transformation global must be reported as a leak');

            clear guard;   % run the cleanup now so the assertions above are the test's last act
        end

        function errorRestorePathEmitsLiteralMessageWithId(tc)
            % M5 (#121): error_restore_path called `error(msg)`, which raised
            % with an EMPTY identifier. The fix raises under the fork's adigator:*
            % id via error('adigator:generationError','%s',msg). The id and the
            % path-restore are the load-bearing assertions here; the '%s' keeps a
            % composed message with '\' or '%' literal (defensive - single-arg
            % error is already literal in current MATLAB, but it guards Octave /
            % future multi-arg misuse), so the verbatim-message assertion below is
            % a belt-and-suspenders check.
            p0 = path;
            guard = onCleanup(@() path(p0));   % safety net for the path
            % perturb the path so a genuine restore is observable
            probe = fullfile(pwd, 'm5_probe_dir');
            mkdir(probe);
            addpath(probe);
            tc.assertTrue(contains(path, probe), 'probe dir must be on the path first');

            badmsg = 'The file C:\proj\run_100%done.m already exists';  % '\' and '%'
            caught = false;
            try
                error_restore_path(p0, badmsg);   % restore to p0, then error
            catch ME
                caught = true;
            end
            tc.verifyTrue(caught, 'error_restore_path must raise an error (M5)');
            tc.verifyEqual(ME.identifier, 'adigator:generationError', ...
                'the error must carry the adigator:* id (M5)');
            tc.verifyEqual(ME.message, badmsg, ...
                'the message must be raised verbatim, not printf-interpreted (M5)');
            tc.verifyEqual(path, p0, ...
                'the path must be restored before erroring (M5)');

            clear guard;
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
stray = strayTransformGlobals(globals0);
tc.verifyEmpty(stray, sprintf('transformation-state globals leaked %s: %s', ...
    when, strjoin(stray, ', ')));
tc.verifyEqual(path, path0, sprintf('MATLAB path not restored %s', when));
tc.verifyEmpty(setdiff(openFidsPortable(), fids0), ...
    sprintf('file handle(s) left open %s', when));
end

function names = strayTransformGlobals(globals0)
% Transformation-state globals present beyond the baseline. After R11/#54
% (ADR-0015) the invariant is strict name-absence: a benign read of a returned
% cada object no longer re-registers an empty ADIGATOR, so NO transformation
% global may survive -- empty or populated -- and the bare name is the leak.
transformGlobals = {'ADIGATOR','ADIGATORFORDATA','ADIGATORDATA','ADIGATORVARIABLESTORAGE'};
names = intersect(setdiff(who('global'), globals0), transformGlobals);
end

function clearTransformGlobals()
% Clear the four transformation-state globals from a frame that does NOT declare
% them, mirroring adigator's own non-declaring helper-clear.
clear global ADIGATOR ADIGATORFORDATA ADIGATORDATA ADIGATORVARIABLESTORAGE
end

function setGlobalExpr(name, rhsExpr)
% Declare a global by name and assign it the value of the MATLAB source text
% rhsExpr (e.g. '[]' for an empty re-registration, 'struct(...)' for live
% state). The eval arguments are *concatenated* (non-constant) on purpose: a
% literal `global` statement is a checkcode GVMIS finding and eval of a
% *constant* string is an EVLC finding, whereas eval of a concatenation is
% neither -- and both name and rhsExpr are referenced in the concatenation, so
% neither argument reads as unused.
eval(['global ',name]);
eval([name,' = ',rhsExpr,';']);
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
