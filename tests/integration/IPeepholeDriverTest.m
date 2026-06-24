classdef IPeepholeDriverTest < matlab.unittest.TestCase
    % IPeepholeDriverTest  Positive assertion that the R7c union-copy peephole
    % fires THROUGH THE REAL slim_embed DRIVER (issue #44 item 2 / roadmap
    % R10(b); ANALYSIS §2.3(6), ADR-0006). TS-I-08.
    %
    % Why this test exists. UPeepholeTest (TS-U-13) unit-tests the collapse
    % logic on synthetic text, and IEmbedSlimTest (TS-I-06) exercises the driver
    % on real generated code - but a probe of ~40 generated Jacobians/Hessians
    % (straight-line, rolled, unrolled) found that adigator's emitter never
    % produces the ordered-identity FULL fill the peephole collapses: real
    % overmaps are always strict PARTIAL fills into a union-sized buffer, and
    % equal-pattern unions are added with no buffer at all. So on today's
    % generated code the driver's collapse count is always 0 - meaning a silent
    % regression that disabled the R7c peephole inside adigatorSlimEmbeddedDeriv
    % would pass every other test unnoticed. This test drives a SYNTHETIC but
    % structurally faithful, genuinely-runnable fixture (the identity y = x, so
    % the union copy is a true no-op) through adigatorSlimEmbeddedDeriv and
    % asserts that collapsed > 0 - closing that gap. See
    % tests/fixtures/collapse/cf_ADiGatorJac.m for the fixture and the rationale.

    properties
        FixtureDir
    end

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
            tc.FixtureDir = fullfile(root,'tests','fixtures','collapse');
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function driverCollapsesOrderedIdentityUnionCopy(tc)
            genfile = tc.stageFixture();

            info = adigatorSlimEmbeddedDeriv(genfile, ...
                {adigatorCreateDerivInput([3 1],'x')});

            % (1) the collapse fired through the real driver path
            tc.verifyGreaterThan(info.collapsed, 0, ...
                'the slim_embed driver must report a collapsed union copy');

            % (2) the authoritative rewrite landed on disk: the zeros+scatter
            %     pair is gone, replaced by the reshape. Check CODE lines only
            %     (drop comments) so an illustrative mention in the fixture
            %     header cannot mask a regression either way.
            code = codeLines(readlines(genfile.m));
            tc.verifyTrue(any(contains(code,'reshape(x.dx,3,1)')), ...
                'the collapsed pair must be rewritten to reshape(x.dx,3,1)');
            tc.verifyFalse(any(contains(code,'cada1td1 = zeros(3,1)')), ...
                'the zeros allocation of the collapsed pair must be dropped');
            tc.verifyFalse(any(contains(code,'cada1td1(Gator1Data.Index1')), ...
                'the scatter of the collapsed pair must be dropped');

            % (3) the driver's numeric round-trip cross-check ran AND agreed -
            %     a mismatch would have rejected the rewrite (collapsed==0), so
            %     reaching here with checked==true proves end-to-end equivalence
            tc.verifyTrue(info.checked, ...
                'the numeric round-trip cross-check should have run for a runnable fixture');
        end
    end

    methods (Access = private)
        function genfile = stageFixture(tc)
            % Copy the committed synthetic fixture (wrapper + derivative) into
            % the temp working folder and build the matching .mat there. The
            % .mat is reconstructed from explicit, reviewable index arrays
            % rather than committed as an opaque binary. The fixture is fixed at
            % vector length K=3 (the (1:3).' identity, the 3x3 Jacobian, the
            % reshape(...,3,1)): Index1 is the ordered identity (1:3).' that
            % makes the union copy collapsible; Index2 is the diagonal location
            % table the wrapper scatters through.
            dest = pwd;
            copyfile(fullfile(tc.FixtureDir,'cf_ADiGatorJac.m'), dest);
            copyfile(fullfile(tc.FixtureDir,'cf_Jac.m'), dest);

            cf_ADiGatorJac.Gator1Data.Index1 = (1:3).';
            cf_ADiGatorJac.Gator1Data.Index2 = [(1:3).', (1:3).'];
            save(fullfile(dest,'cf_ADiGatorJac.mat'),'cf_ADiGatorJac');
            rehash;

            genfile = struct( ...
                'main',    fullfile(dest,'cf_Jac.m'), ...
                'm',       fullfile(dest,'cf_ADiGatorJac.m'), ...
                'mat',     fullfile(dest,'cf_ADiGatorJac.mat'), ...
                'name',    'cf_Jac', ...
                'dername', 'cf_ADiGatorJac', ...
                'path',    dest);
        end
    end
end

% --------------------------- helpers ----------------------------------- %
function c = codeLines(lines)
% the non-comment lines of a file (leading-whitespace '%' lines dropped), so a
% text scan asserts against live code rather than illustrative comments
s = strtrim(string(lines(:)));
c = s(~startsWith(s,'%'));
end
