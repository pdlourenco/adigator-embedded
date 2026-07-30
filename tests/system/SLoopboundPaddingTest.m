classdef SLoopboundPaddingTest < matlab.unittest.TestCase
    % SLoopboundPaddingTest  Guards the R17 Tier-1 padding-penalty measurement
    % (issue #73 / #6): a `loopbound` derivative generated at Nmax and run at
    % n<Nmax vs a file regenerated at exact n. Asserts the padded footprint is
    % measured and behaves as found - a subscripted derivative's padded ROM is
    % n-independent and materially larger than the exact-n ROM at small n
    % (multiple-x, the evidence the R6 go/no-go is gated on), converging to ~1x
    % at n=Nmax.
    %
    % Heavyweight (each n is an Embedded Coder build) and gated: on a runner
    % without MATLAB Coder / Embedded Coder the whole test skips cleanly via
    % assumption, like SCodegenShowcaseTest; the ROM assertions additionally need
    % the standalone gcc/size toolchain and skip when it is absent. Runs in the
    % extended/codegen CI suite, not the PR gate.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(root,'bench')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function paddingPenaltyIsMeasuredAndConverges(tc)
            Nmax = 32;
            rp = loopboundPaddingPenalty('Nmax',Nmax,'nSweep',[4 Nmax],'verbose',false);
            tc.assumeTrue(rp.available, ...
                'MATLAB Coder / Embedded Coder not available - skipping.');

            % footprint measured (needs the gcc/size toolchain); skip the ROM
            % assertions cleanly otherwise, but still confirm the sweep ran.
            tc.verifyNumElements(rp.rows, 2, 'expected the two swept sizes');
            tc.assumeTrue(rp.padded.rom > 0, ...
                'gcc/size toolchain absent - ROM not measured, skipping penalty asserts.');

            % padded ROM is n-independent (measured once) and > 0
            tc.verifyGreaterThan(rp.padded.rom, 0, 'padded ROM not measured');

            r4 = rp.rows([rp.rows.n] == 4);
            rN = rp.rows([rp.rows.n] == Nmax);
            tc.assertNotEmpty(r4, 'n=4 row missing');
            tc.assertNotEmpty(rN, 'n=Nmax row missing');

            % the headline: a subscripted derivative's padded ROM is materially
            % larger than the exact-n ROM at small n (the R6 penalty)...
            tc.verifyGreaterThan(r4.romPenalty, 1.5, ...
                'expected a real Nmax-padding ROM penalty at n<<Nmax');
            % ...and converges to ~1x at n=Nmax, which is the whole claim: at
            % the analyzed maximum there is no padding left to pay for.
            %
            % Two-sided band, both edges loose on purpose. The padded file is
            % not simply the exact file plus scaffolding: since B36 the exact
            % file's trip count is a compile-time CONSTANT (assert(N == n)) and
            % so it is fully fixed-size, while the padded file's is genuinely
            % runtime (variable-size at :Nmax). Coder specializes the two
            % differently, leaving a few percent of residual scaffolding -
            % measured 1.0x at Nmax=64, 1.09x at Nmax=32. The band asserts "no
            % padding penalty remains at n=Nmax", not a byte-level relation.
            %
            % Both edges stay loose: this is a Coder-version-sensitive figure,
            % and the ratio has already crossed 1 in BOTH directions across
            % B35/B36 (0.88x while the exact file still carried heap machinery,
            % 1.09x now that it does not). A real regression here is a
            % multiple-x move, not a few percent. The earlier one-sided >= 0.95
            % floor encoded a structural assumption that turned out false.
            tc.verifyGreaterThan(rN.romPenalty, 0.75, ...
                'padded and exact must converge (~1x) at n=Nmax');
            tc.verifyLessThan(rN.romPenalty, 1.2, ...
                'padded and exact must converge (~1x) at n=Nmax');
        end
    end
end
