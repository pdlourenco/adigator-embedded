classdef IVectorizedFenceTest < AdigatorTestCase
    % IVectorizedFenceTest  B40 tripwire: a contraction OVER the vectorized
    % (`Inf`) dimension still slips past `mtimes`' own vectorized guard.
    %
    % `lib/@cada/mtimes.m:130-131` carries a designed refusal for vectorized
    % operands, but it keys on the **result** dimensions (`:129`,
    % `isinf(FMrow) || isinf(FNcol)`). For `x'*x` with `x` of size `[Inf 1]`
    % the inner dimensions agree and the result is a finite `1 x 1`, so no
    % branch fires, execution falls through to the non-vectorized path with the
    % first operand's `xNcol` still `Inf`, and dies at `true(xMrow,xNcol)`
    % (`:162`) with a generic `MATLAB:nonaninf`. A contraction over the free
    % dimension is invisible to a fence that only inspects what comes out --
    % semantically this is `sum`'s case (`sum.m:91`) and wants `sum`'s refusal.
    %
    % Principle 1 is NOT engaged: it errors, before anything is printed. This
    % is diagnostic quality -- the user is stopped, but not told why, and not
    % by us. See `docs/analyses/ANALYSIS.md` §1.3n / B40.
    %
    % SELF-HEALING, and deliberately not pinned on `MATLAB:nonaninf`. That is a
    % MATLAB-internal identifier and an artifact of `true(...,Inf)` rather than
    % anything this project owns -- exactly the kind of unstable id #226 refused
    % to pin. Instead the test asserts only that the failure is **not ours**:
    % the moment either half of B40 is fixed (a named `adigator:` refusal on the
    % contraction, or ids added to the vectorized refusals) this fires and says
    % what to do. It therefore satisfies CI_PLAN.md §1.2's KnownIssue policy
    % without pretending the bug is fixed, and survives MATLAB renaming its own
    % error.
    %
    % License-free: generation-only, no Coder.
    %
    %   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
    %   Public License version 3.0.

    methods (TestClassSetup)
        function addHelperPath(tc)
            import matlab.unittest.fixtures.PathFixture
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            tc.applyFixture(PathFixture(fullfile(root,'tests','helpers')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function contractionOverFreeDimensionStillEscapesTheGuard(tc)
            % B40 defect 1. Retire this method when it fires.
            e = tc.captureGenerationError('vfenceMtimes', 'y = x''*x;');
            tc.assertNotEmpty(e, ...
                ['x''''*x contracts over the vectorized dimension and must ', ...
                 'not generate. If this fires, the engine started ACCEPTING ', ...
                 'a reduction over the free dimension - that is principle 1 ', ...
                 'territory, not a diagnostic-quality issue, and matters far ', ...
                 'more than the rest of B40.']);
            tc.verifyFalse(startsWith(e.identifier, 'adigator:'), sprintf( ...
                ['B40: x''''*x still bypasses the mtimes vectorized guard and ', ...
                 'dies in a MATLAB builtin (%s). When a named adigator: ', ...
                 'refusal lands this fires - update ANALYSIS §1.3n/B40 and ', ...
                 'delete this tripwire.'], e.identifier));
        end

        function theDesignedRefusalsStillHaveNoIdentifier(tc)
            % B40 defect 2, the half that matters for #6 Tier 2: the vectorized
            % refusals are bare error('...') and so are not programmatically
            % catchable, unlike adigator:loopbound:rangemismatch. `sum` stands
            % for the family (prod/max/norm/catenation/subsref/subsasgn are the
            % same shape). Retire when ids land.
            e = tc.captureGenerationError('vfenceSum', 'y = sum(x);');
            tc.assertNotEmpty(e, 'sum over the vectorized dimension must refuse');
            tc.assertNotEmpty(strfind(e.message, 'vectorized dimension'), ...
                'expected the designed vectorized-reduction refusal message');
            tc.verifyEmpty(e.identifier, sprintf( ...
                ['B40: the vectorized refusals are still message-only ', ...
                 '(got id "%s"). When they gain adigator: identifiers this ', ...
                 'fires - update ANALYSIS §1.3n/B40 and delete this ', ...
                 'tripwire.'], e.identifier));
        end
    end

    methods (Access = private)
        function e = captureGenerationError(~, fname, bodyLine)
            % try/catch rather than verifyError: verifyError does not hand back
            % the MException, and the identifier is the whole subject here.
            writeFixtureFile(fname, bodyLine);
            gx = adigatorCreateDerivInput([Inf 1], ...
                struct('vodname','x','vodsize',[Inf 1],'nzlocs',[1 1]));
            % Called directly rather than through evalc: anything referenced
            % only inside an evalc string reads as unused to checkcode, and
            % `echo,0` already suppresses the bulk of the generation chatter.
            e = MException.empty;
            try
                adigator(fname, {gx}, [fname '_dx'], ...
                    adigatorOptions('overwrite',1,'echo',0));
            catch caught
                e = caught;
            end
        end
    end
end
