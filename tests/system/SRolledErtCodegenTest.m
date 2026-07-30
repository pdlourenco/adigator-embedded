classdef SRolledErtCodegenTest < AdigatorTestCase
    % SRolledErtCodegenTest  Regression guard (#80 Gap B / Path A): the ROLLED
    % subscripted derivatives must codegen under strict Embedded Coder (ERT) at a
    % size large enough to trigger static-data index de-duplication.
    %
    % The original break was rolled `scostfun` Hessian at n>=32 failing ERT with
    % "Structure field 'Index5' does not exist ... addition of new fields after a
    % structure has been read or used" - the static-data helper aliased a deduped
    % index to its sibling struct field (`S.x.Index5 = S.x.Index4`, a read-then-
    % add). Fixed in structure_to_embed_mfile by routing the shared copy through a
    % local temp. UEmbedMfileTest pins the emitted FORM; this pins the thing that
    % actually broke: ERT acceptance end to end.
    %
    % Coder + Embedded Coder gated: skips cleanly without the licenses, like the
    % other tests/system Coder tests. `GenCodeOnly` (no C compiler needed - the
    % field-add-after-read is caught at MATLAB->C generation). Extended suite, not
    % the PR gate.

    methods (TestClassSetup)
        function addShowcasePath(tc)
            import matlab.unittest.fixtures.PathFixture
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % tests/system -> root
            tc.applyFixture(PathFixture(fullfile(root, 'bench', 'showcase')));
        end

        function requireErt(tc)
            tc.assumeTrue(license('test','MATLAB_Coder') && license('test','RTW_Embedded_Coder'), ...
                'MATLAB Coder + Embedded Coder required - skipping ERT rolled-codegen guard.');
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function rolledGradientAndHessianErtCodegen(tc)
            % n=32: large enough that identical index tables get de-duplicated -
            % the regime where the read-then-add alias used to break ERT (n=8 did
            % not trigger it).
            n   = 32;
            cfg = coder.config('lib', 'ecoder', true);
            cfg.GenCodeOnly = true;
            for spec = {{'gradient','_Grd'}, {'hessian','_Hes'}}
                dt  = spec{1}{1};
                w   = ['scostfun' spec{1}{2}];
                adigatorGenDerFile_embedded(dt, 'scostfun', ...
                    {adigatorCreateDerivInput([n 1], 'x')}, ...
                    adigatorOptions('overwrite',1,'echo',0,'embed_mode','i','unroll',0,'slim_embed',1));
                ok = true; msg = '';
                try
                    codegen(w, '-config', cfg, '-args', {zeros(n,1)}, '-d', ['clib_' dt]);
                catch e
                    ok = false; msg = e.message;
                end
                tc.verifyTrue(ok, sprintf( ...
                    'rolled %s must ERT-codegen at n=%d (#80 Path A): %s', dt, n, msg));
            end
        end

        function loopboundGradientErtCodegenStaticMemory(tc)
            % B35: a 'loopbound' derivative must codegen with dynamic memory
            % allocation DISABLED - the no-heap regime an embedded target
            % actually runs in.
            %
            % It did not: the runtime-bound guard was emitted at the loop
            % header only, so the bound-dependent expressions ahead of the loop
            % (the user's own `zeros(N,1)`, and the `cadaforvar<k> = 1:N` loop
            % variable the machinery materializes) reached Coder with no upper
            % bound and it refused the file - "computed maximum size of the
            % output of function 'colon' is not bounded". Hoisting the guard to
            % the top of the body (adigatorFunctionInitialize) bounds them.
            %
            % Static memory allocation is the whole point of the assertion, so
            % this test sets EnableDynamicMemoryAllocation explicitly rather
            % than relying on the config default: with the heap enabled the
            % file generates either way and the test proves nothing.
            %
            % Subfunction reach: the hoisted guard lives in the MAIN function
            % only, so a subfunction doing its own pre-loop `zeros(N,1)` relies
            % on Coder carrying the caller-established bound across the call.
            % It does - probed directly on R2024a, a callee's `zeros(N,1)` and
            % `1:N` both build no-heap under a caller-side `assert(N <= 8)`.
            % Left as a note rather than a fixture here: an adigator-generated
            % subfunction+loopbound artifact is a heavier build, and the failure
            % direction is loud (codegen refusal), not a wrong derivative.
            n   = 8;
            cfg = coder.config('lib', 'ecoder', true);
            cfg.EnableDynamicMemoryAllocation = false;
            cfg.GenCodeOnly = true;
            cfg.GenerateReport = false;
            adigatorGenDerFile_embedded('gradient', 'scostfun_lb', ...
                {adigatorCreateDerivInput([n 1], 'x'), n}, ...
                adigatorOptions('overwrite',1,'echo',0,'embed_mode','i', ...
                                'unroll',0,'loopbound','N'));
            ok = true; msg = '';
            try
                % x fixed-size; N is the RUNTIME bound the padded file is called with
                codegen('scostfun_lb_Grd', '-config', cfg, ...
                    '-args', {zeros(n,1), coder.typeof(0)}, '-d', 'clib_lb');
            catch e
                ok = false; msg = e.message;
            end
            tc.verifyTrue(ok, sprintf( ...
                'loopbound gradient must ERT-codegen with static memory allocation (B35): %s', msg));
        end
    end
end
