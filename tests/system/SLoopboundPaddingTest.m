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
            % ...and converges to ~1x at n=Nmax. The padded file still carries
            % the loopbound scaffolding (assert guard, runtime-bounded loop) the
            % exact file lacks, so the penalty is structurally >= 1 there; a
            % one-sided band tolerates that fixed overhead without brittleness.
            tc.verifyGreaterThanOrEqual(rN.romPenalty, 0.95, ...
                'padded ROM should not be below exact at n=Nmax');
            tc.verifyLessThan(rN.romPenalty, 1.2, ...
                'padded and exact must converge (~1x) at n=Nmax');
        end
    end
end
