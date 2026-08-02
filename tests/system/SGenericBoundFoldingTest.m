classdef SGenericBoundFoldingTest < matlab.unittest.TestCase
    % SGenericBoundFoldingTest  R6 Tier-2 / Route B premise: an affine index
    % GENERATOR compiled with a build-time constant bound must cost no ROM.
    %
    % Route B (2026-08-02 engine-v2 analysis §4) proposes emitting generic
    % derivative files -- `zeros(N,1)`, `uint32(reshape(1:1:N,N,1))`,
    % `for k = 1:N` -- and folding the bound back in at BUILD time via
    % `coder.Constant(N)`, instead of baking `n` into the generated MATLAB. The
    % whole route rests on Coder actually doing that folding. If it does not,
    % generators cost runtime ROM and cycles and the design needs a pre-build
    % MATLAB "specialize" step instead.
    %
    % Experiment E2 measured it: with `coder.Constant(64)` the kernel compiles
    % to 48 B ROM, `.rdata` 0, and ZERO `static const` declarations -- the
    % generator is not folded into a table, it is eliminated, because Coder
    % proves `idx(k) == k` and collapses it into the loop induction variable.
    % The runtime-`N` control keeps a `tmp_data[64]` materialization loop.
    %
    % This test exists because that is a claim about the TOOLCHAIN, not about
    % adigator: a Coder upgrade, a config change, or a different target could
    % silently invalidate it, and Route B would be resting on a fact that had
    % quietly stopped being true. ADR-0019's O(n^2) stack figure is the
    % cautionary precedent (#216) -- a measurement quoted into durable documents
    % with no way to re-run it, which then did not reproduce.
    %
    % Coder-gated and skip-clean: MATLAB Coder + Embedded Coder are NOT licensed
    % on hosted runners (CI_PLAN.md §3.2), so this runs locally only. It asserts
    % PROPERTIES (no static tables; no index materialization; strictly smaller
    % than the runtime-bound build) rather than the exact byte counts, which are
    % toolchain-specific and would make it a brittle pin rather than a gate.
    %
    %   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
    %   Public License version 3.0.

    properties (Constant)
        Nmax = 64
    end

    methods (TestClassSetup)
        function requireCoder(tc)
            tc.assumeTrue(~isempty(which('codegen')) && ...
                license('test','MATLAB_Coder') && ...
                license('test','RTW_Embedded_Coder'), ...
                ['MATLAB Coder / Embedded Coder not available - Route B''s ', ...
                 'build-time folding premise cannot be checked here ', ...
                 '(CI_PLAN.md section 3.2).']);
        end
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function constantBoundFoldsTheGeneratorAway(tc)
            % The premise: constant bound => no static table, no runtime index
            % arithmetic. This is the assertion Route B lives or dies on.
            tc.writeKernel();
            c = tc.buildAndRead('clibC', ...
                {coder.typeof(0,[tc.Nmax 1]), coder.Constant(tc.Nmax)});

            tc.verifyEqual(numel(regexp(c.src,'static\s+const','match')), 0, ...
                ['Route B: with a coder.Constant bound the affine index ', ...
                 'generator must not survive as a static const table. If ', ...
                 'this fires, generators cost ROM and the design needs a ', ...
                 'pre-build specialize step instead (engine-v2 analysis, E2).']);
            tc.verifyEqual(c.rdata, 0, ...
                'a fully folded kernel must carry no read-only data at all');
        end

        function runtimeBoundIsTheContrast(tc)
            % Non-vacuity: the assertions above must be discriminating, not
            % trivially true of any small kernel. The SAME source compiled with
            % a runtime bound must keep the index work the constant build sheds.
            tc.writeKernel();
            r = tc.buildAndRead('clibR', ...
                {coder.typeof(0,[tc.Nmax 1]), coder.typeof(0)});
            c = tc.buildAndRead('clibC', ...
                {coder.typeof(0,[tc.Nmax 1]), coder.Constant(tc.Nmax)});

            % The runtime build materializes the index vector into a local.
            tc.verifyNotEmpty(regexp(r.src,'_data\[|tmp_data','once'), ...
                ['expected the runtime-bound build to materialize the index ', ...
                 'generator into a local array - if it no longer does, this ', ...
                 'contrast no longer discriminates and the test above is weaker ', ...
                 'than it looks.']);
            tc.verifyGreaterThan(r.rom, c.rom, ...
                ['the constant-bound build must be strictly cheaper than the ', ...
                 'runtime-bound one; equal ROM would mean the fold did nothing']);
        end
    end

    methods (Access = private)
        function writeKernel(tc)
            % A minimal GENERIC file carrying exactly the three constructs
            % Route B would emit: a size generator, an affine index generator,
            % and a loop whose trip count is the same bound.
            fid = fopen('genkern.m','w');
            assert(fid > 0, 'could not create the genkern fixture');
            closer = onCleanup(@() fclose(fid));
            fprintf(fid, '%s\n', ...
                'function y = genkern(x,N)', ...
                '%#codegen', ...
                sprintf('assert(N <= %d);', tc.Nmax), ...
                'yd = zeros(N,1);                      % size generator', ...
                'idx = uint32(reshape(1:1:N, N, 1));   % affine index generator', ...
                'for k = 1:N                           % same bound as the trip count', ...
                '    yd(idx(k)) = yd(idx(k)) + 2*x(k);', ...
                'end', ...
                'y = yd;', ...
                'end');
            clear closer
            rehash;
        end

        function out = buildAndRead(~, dirname, args)
            % Build under the SHARED strict profile (ADR-0033) and read back the
            % generated C plus its compiled section sizes. Restating the no-heap
            % setting rather than only inheriting it is the ADR-0034 decision-2
            % posture: a footprint measured with the heap on is not an embedded
            % footprint.
            cfg = adigatorCoderConfig();
            cfg.EnableDynamicMemoryAllocation = false;
            % Called directly rather than wrapped in evalc: anything referenced
            % only inside an evalc string reads as unused to checkcode, and
            % suppressing Coder's progress chatter is not worth a lint
            % suppression in a test that already takes a minute to build.
            codegen('genkern','-config',cfg,'-args',args,'-d',dirname);
            clib = fullfile(pwd, dirname);
            out.src = fileread(fullfile(clib,'genkern.c'));
            [out.text, out.rdata] = SGenericBoundFoldingTest.sections(clib,'genkern.c');
            out.rom = out.text + out.rdata;
        end
    end

    methods (Static, Access = private)
        function [textB, rdataB] = sections(clibDir, cfile)
            % .text / .rdata of the compiled object, via the ADR-0027 toolchain
            % (MinGW gcc + size, the same pair measureErtFootprint uses).
            textB = -1; rdataB = -1;
            mingw = getenv('MW_MINGW64_LOC');
            if isempty(mingw)
                mingw = fullfile(matlabroot,'bin',computer('arch'),'mingw64');
            end
            gcc  = fullfile(mingw,'bin','gcc.exe');
            sizx = fullfile(mingw,'bin','size.exe');
            if ~isfile(gcc) || ~isfile(sizx); return; end
            inc = fullfile(matlabroot,'extern','include');
            obj = fullfile(clibDir,[cfile '.o']);
            [st,~] = system(sprintf('cd /d "%s" && "%s" -Os -c "%s" -I"%s" -I"%s" -o "%s"', ...
                clibDir, gcc, cfile, clibDir, inc, obj));
            if st ~= 0; return; end
            [st,out] = system(sprintf('"%s" -A "%s"', sizx, obj));
            if st ~= 0; return; end
            textB  = SGenericBoundFoldingTest.sect(out,'.text');
            rdataB = SGenericBoundFoldingTest.sect(out,'.rdata');
        end

        function v = sect(out,name)
            t = regexp(out, ['^\s*' regexptranslate('escape',name) '\s+(\d+)'], ...
                'tokens','lineanchors','once');
            if isempty(t); v = 0; else; v = str2double(t{1}); end
        end
    end
end
