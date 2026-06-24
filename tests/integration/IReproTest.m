classdef IReproTest < matlab.unittest.TestCase
    % IReproTest  Reproducible regeneration through the embedded entry point.
    %
    % CI plan: TS-I-03, verifies REQ-T-06. Covers the regeneration contract of
    % adigatorGenDerFile_embedded:
    %  - regenerating the same fixture twice is byte-identical (modulo any
    %    timestamp line; the generator currently emits none, so the strip is a
    %    forward-looking safeguard);
    %  - regeneration over an already-populated folder succeeds BY DEFAULT --
    %    like the other wrapper-generation entry points, OVERWRITE defaults to 1
    %    here (adigatorOptions NOTES: the default differs for the wrapper
    %    generators vs. the basic adigator file). This is a regression guard:
    %    the embedded generator forwards a fully-resolved opts struct to the
    %    inner wrappers, which always carries an `overwrite` value and would
    %    otherwise defeat their "force overwrite=1 unless the caller passed one"
    %    logic, aborting the second pass with "file already exists";
    %  - an explicit overwrite=0 is still honoured (no silent clobber);
    %  - opts.path places the artifacts in the requested folder and leaves the
    %    deliverables out of the calling directory.
    %
    % Uses the pipg example's gapfun (subfunctions + integer constants), the
    % same fixture as the cross-mode suite.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
            tc.applyFixture(PathFixture(fullfile(root,'embedding')));
            tc.applyFixture(PathFixture(fullfile(root,'examples','optimization','pipg')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function regenerateTwiceIsDeterministic(tc)
            base = pwd;
            d1 = fullfile(base, 'gen_a');
            d2 = fullfile(base, 'gen_b');
            tc.generateInto(d1, 'l');
            tc.generateInto(d2, 'l');

            f1 = fullfile(d1, 'gapfun_Grd.m');
            f2 = fullfile(d2, 'gapfun_Grd.m');
            tc.assertTrue(isfile(f1) && isfile(f2), 'wrappers not generated');
            tc.verifyEqual(stripTimestamps(readlines(f1)), ...
                           stripTimestamps(readlines(f2)), ...
                'two independent generations of the same fixture differ');
        end

        function regeneratesOverExistingFilesByDefault(tc)
            gendir = fullfile(pwd, 'regen');

            % first pass populates gendir
            tc.generateInto(gendir, 'i');
            tc.assertTrue(isfile(fullfile(gendir, 'gapfun_Grd.m')), ...
                'first generation did not produce the wrapper');

            % second pass over the now-populated folder must succeed by
            % default (overwrite=1); on the pre-fix generator this aborted
            % with "file already exists, quitting transformation".
            tc.generateInto(gendir, 'i');
            tc.verifyTrue(isfile(fullfile(gendir, 'gapfun_Grd.m')), ...
                'regenerated wrapper missing after second pass');
        end

        function explicitOverwriteZeroIsHonoured(tc)
            gendir = fullfile(pwd, 'regen0');

            % populate the folder first
            tc.generateInto(gendir, 'i');
            tc.assertTrue(isfile(fullfile(gendir, 'gapfun_Grd.m')), ...
                'first generation did not produce the wrapper');

            % a caller who explicitly opts out of overwriting must still be
            % protected from clobbering: regeneration must abort.
            opts = struct('embed_mode','i','path',gendir,'echo',0,'overwrite',0);
            tc.verifyError(@() tc.generateWith(opts), ?MException, ...
                'explicit overwrite=0 must not silently clobber existing files');
        end

        function pathPlacementKeepsCallingDirClean(tc)
            base = pwd;
            gendir = fullfile(base, 'placed');
            tc.generateInto(gendir, 'l');

            % deliverables land under opts.path ...
            tc.verifyTrue(isfile(fullfile(gendir, 'gapfun_Grd.m')), ...
                'wrapper not placed under opts.path');
            tc.verifyTrue(isfile(fullfile(gendir, 'gapfun_ADiGatorGrd.mat')), ...
                'pruned .mat not placed under opts.path');

            % ... and not in the calling directory
            tc.verifyEmpty(dir(fullfile(base, 'gapfun_Grd.m')), ...
                'wrapper leaked into the calling directory');
            tc.verifyEmpty(dir(fullfile(base, '*.mat')), ...
                'a .mat leaked into the calling directory');
        end
    end

    methods (Access = private)
        function generateInto(tc, gendir, mode)
            tc.generateWith(struct('embed_mode',mode,'path',gendir,'echo',0));
        end

        function generateWith(~, opts)
            % fresh deriv inputs per call (the generator is path-driven)
            z = adigatorCreateDerivInput([2 1], 'z');
            w = adigatorCreateAuxInput([2 1]);
            adigatorGenDerFile_embedded('gradient', 'gapfun', {w, z}, opts);
        end
    end
end

function lines = stripTimestamps(lines)
% Drop any line carrying a date so a future timestamp header would not make
% the determinism check spurious. Patterns: 01-Jan-2026 and 2026-01-01.
keep = ~(contains(lines, regexpPattern('\d{1,2}-[A-Za-z]{3}-\d{4}')) | ...
         contains(lines, regexpPattern('\d{4}-\d{2}-\d{2}')));
lines = lines(keep);
end
