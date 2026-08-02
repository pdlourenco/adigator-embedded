classdef ISpecializedTripCountTest < matlab.unittest.TestCase
    % ISpecializedTripCountTest  B36 / issue #210: a loop whose range NAMES a
    % main-function input specializes the generated file to one trip count, and
    % the file must say so.
    %
    % Passing a plain numeric `n` to adigator fixes the ANALYSIS trip count but
    % does not make the input a compile-time constant: it stays a named function
    % input, so the generated file kept `cadaforvar<k> = 1:N` while specializing
    % the loop HEADER to the analyzed literal. The two disagreed, and the
    % disagreement was not symmetric:
    %
    %   N < n   index out of bounds                      - loud
    %   N > n   runs, returns the ANALYZED problem's      - SILENT, and wrong
    %           answer with an output of the requested      (principle 1)
    %           length whose tail is never written
    %
    % ...and with nothing bounding `N`, Embedded Coder refused the file under
    % static memory allocation, the same way B35's loopbound case was refused.
    %
    % The fix emits `assert(N == n);` as the first statement of the body (the
    % B35 position, for the B35 reason: the parameter also sizes expressions
    % ahead of the loop). See ADR-0034 and docs/analyses/ANALYSIS.md §1.3j.

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
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function specializedFileStatesItsTripCount(tc)
            % the guard is emitted, first, and with the equality operator
            writeCubeSum();
            n = 5;
            adigator('tc_cube',{adigatorCreateDerivInput([n 1],'x'),n},'tc_d', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            L = strtrim(string(splitlines(string(fileread('tc_d.m')))));
            bodyStart = find(contains(L,'ADiGator Start Derivative Computations'),1);
            tc.assertNotEmpty(bodyStart,'generated file must carry the body marker');
            tc.verifyEqual(char(L(bodyStart+1)), sprintf('assert(N == %d);',n), ...
                'the specialization guard must be the first body statement');

            % exactly one - a duplicate would mean the prologue and some other
            % site both emitted it
            tc.verifyEqual(nnz(startsWith(L,'assert(')), 1, ...
                'expected exactly one guard in a singly-specialized file');
        end

        function oversizedCallNoLongerSilentlyWrong(tc)
            % the principle-1 case: pre-fix this RAN and returned the n-sized
            % answer for an N-sized request
            writeCubeSum();
            n = 5;
            adigator('tc_cube',{adigatorCreateDerivInput([n 1],'x'),n},'tc_d', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            x.f = (1:n).'; x.dx = ones(n,1);
            out = tc_d(x,n);
            tc.verifyEqual(out.f, sum((1:n).'.^3), 'AbsTol', 0, ...
                'the analyzed trip count must still compute correctly');
            tc.verifyEqual(out.dx, 3*(1:n).'.^2, 'AbsTol', 1e-12, 'RelTol', 1e-12);

            % pin the IDENTIFIER: xBig is also the wrong size for this file, so
            % several unrelated errors would satisfy a bare ?MException and the
            % test could pass without the guard existing at all
            xBig.f = (1:n+3).'; xBig.dx = ones(n+3,1);
            tc.verifyError(@() tc_d(xBig,n+3), 'MATLAB:assertion:failed', ...
                'a call above the specialized trip count must fail the guard');
        end

        function subfunctionLoopDoesNotForgeAGuard(tc)
            % The TRIPCOUNTSCAN gate, which is the ONLY thing standing between
            % this feature and a false guard. A subfunction parameter can shadow
            % a same-named main input while holding a different value; harvesting
            % it would emit `assert(N == 3)` into a function whose own N is 5,
            % rejecting every correct call. Delete the gate and this test is the
            % one that notices.
            writeFcn('tc_shadow', { ...
                'function y = tc_shadow(x,N)', ...
                'y = sub(x,3) + N*0;', ...     % sub's N shadows ours, value 3
                'end', ...
                'function s = sub(x,N)', ...
                's = 0;', ...
                'for k = 1:N', ...
                '  s = s + x(k)^2;', ...
                'end', ...
                'end'});
            n = 5;
            adigator('tc_shadow',{adigatorCreateDerivInput([n 1],'x'),n},'tc_sh_d', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            txt = fileread('tc_sh_d.m');
            tc.verifyFalse(contains(txt,'assert(N == 3);'), ...
                'a subfunction''s shadowing bound must never be guarded as ours');

            % and the outer call still works at its own N
            x.f = (1:n).'; x.dx = ones(n,1);
            out = tc_sh_d(x,n);
            tc.verifyEqual(out.f, sum((1:3).'.^2), 'AbsTol', 1e-12, 'RelTol', 1e-12, ...
                'the subfunction still runs its own trip count');
        end

        function rediffAtADifferentTripCountFailsLoud(tc)
            % The source file is specialized to the value it was generated at -
            % its loop headers and index tables are built for it. Chaining a
            % second derivative with a DIFFERENT value cannot produce a valid
            % file: the new pass would stamp its own value onto a body still
            % serving the old one, so the emitted guard would ACCEPT the wrong
            % trip count and REJECT the only correct one. That is worse than no
            % guard, so it must not generate at all.
            writeCubeSum();
            gx = adigatorCreateDerivInput([5 1],'x');
            adigator('tc_cube',{gx,5},'tc_a1', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;
            gx2 = struct('f',gx,'dx',ones(5,1));

            tc.verifyError(@() adigator('tc_a1',{gx2,8},'tc_a2', ...
                adigatorOptions('overwrite',1,'echo',0)), ...
                'adigator:tripcount:mismatch', ...
                're-differentiating at a different trip count must fail loudly');

            % ...and the matching value still works, so the check is not a blanket ban
            adigator('tc_a1',{gx2,5},'tc_a2', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;
            L = strtrim(string(splitlines(string(fileread('tc_a2.m')))));
            tc.verifyEqual(nnz(startsWith(L,'assert(')), 1);
            tc.verifyEqual(char(L(find(startsWith(L,'assert('),1))),'assert(N == 5);');
        end

        function userEqualityAssertIsNotSilentlyDropped(tc)
            % The == recognizer must not swallow a user's own precondition. An
            % equality guard is ours only if it names a MAIN-function input and
            % sits in the main function; a user assert on a local must keep
            % taking the fail-loud path it took before B36 rather than being
            % silently deleted from the generated file.
            writeFcn('tc_userassert', { ...
                'function y = tc_userassert(x,N)', ...
                'nSteps = 4;', ...
                'assert(nSteps == 4);', ...   % the user's own, on a LOCAL
                'y = 0;', ...
                'for k = 1:N', ...
                '  y = y + x(k)^2;', ...
                'end', ...
                'end'});
            tc.verifyError(@() adigator('tc_userassert', ...
                {adigatorCreateDerivInput([4 1],'x'),4},'tc_ua_d', ...
                adigatorOptions('overwrite',1,'echo',0)), ?MException, ...
                'a user assert must not be silently absorbed');
        end

        function guardSurvivesToThirdDerivative(tc)
            % The load-bearing case, and the reason this is a 3rd-order test
            % rather than a 2nd-order one: at level 1 the parameter name is
            % recovered from the loop RANGE, but from level 2 on the source
            % file's loop header is already a literal, so the name survives ONLY
            % because the previous level's guard is recognized, dropped and
            % re-recorded (adigatorPrintTempFiles). Level 3 exercises that path
            % twice. A recognizer bug shows up here as a duplicated guard or -
            % worse - a silently dropped one, and is invisible at 1st order.
            writeCubeSum();
            n  = 4;
            o  = adigatorOptions('overwrite',1,'echo',0);
            o2 = adigatorOptions('overwrite',1,'echo',0,'comments',0);
            gx = adigatorCreateDerivInput([n 1],'x');
            adigator('tc_cube',{gx,n},'tc_d1',o);
            gx2 = struct('f',gx,'dx',ones(n,1));   % nth-derivative input idiom
            adigator('tc_d1',{gx2,n},'tc_d2',o2);
            adigator('tc_d2',{gx2,n},'tc_d3',o2);
            rehash;

            for f = {'tc_d1','tc_d2','tc_d3'}
                L = strtrim(string(splitlines(string(fileread([f{1} '.m'])))));
                tc.verifyEqual(nnz(startsWith(L,'assert(')), 1, sprintf( ...
                    '%s must carry exactly one specialization guard', f{1}));
                tc.verifyEqual(char(L(find(startsWith(L,'assert('),1))), ...
                    sprintf('assert(N == %d);',n), sprintf( ...
                    '%s guard must name the trip count with ==', f{1}));
            end

            % ...and the derivatives are right, not merely present:
            % d/dx sum(x^3) = 3x^2, d2 = 6x, d3 = 6
            x = struct('f',(1:n).','dx',ones(n,1));
            out = tc_d3(x,n);
            tc.verifyEqual(out.f,      sum((1:n).'.^3), 'AbsTol', 0);
            tc.verifyEqual(out.dx,     3*(1:n).'.^2, 'AbsTol', 1e-12, 'RelTol', 1e-12);
            tc.verifyEqual(out.dxdx,   6*(1:n).',     'AbsTol', 1e-12, 'RelTol', 1e-12);
            tc.verifyEqual(out.dxdxdx, 6*ones(n,1),   'AbsTol', 1e-12, 'RelTol', 1e-12);
        end

        function loopboundKeepsInequalityNotEquality(tc)
            % the two guards are mutually exclusive by construction: a declared
            % runtime bound is padded (<=), never specialized (==). If a name
            % ever picked up both, the padded semantics would be dead on arrival.
            writeCubeSum();
            Nmax = 6;
            adigator('tc_cube',{adigatorCreateDerivInput([Nmax 1],'x'),Nmax},'tc_lb', ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N'));
            rehash;

            txt = fileread('tc_lb.m');
            tc.verifyTrue(contains(txt,sprintf('assert(N <= %d);',Nmax)), ...
                'a loopbound file must keep the <= guard');
            tc.verifyFalse(contains(txt,'assert(N =='), ...
                'a loopbound parameter must NOT also get an == specialization guard');

            % and it still serves any n <= Nmax, which is the whole point
            x.f = (1:Nmax).'; x.dx = ones(Nmax,1);
            out = tc_lb(x,4);
            tc.verifyEqual(out.f, sum((1:4).'.^3), 'AbsTol', 0, ...
                'padded semantics must survive the B36 change');
        end

        function nonInputNamesAreNotGuarded(tc)
            % the collection filter: only a MAIN-function input bound to a plain
            % integer scalar earns a guard. A local computed inside the function
            % is not an input and must not produce one (it would name a variable
            % the guard position cannot see).
            %
            % The OTHER half of the filter - a non-integer scalar input, dropped
            % because a floating-point equality assert is never the right shape -
            % is deliberately not pinned here: that case is a known residual of
            % B36, still specialized and still unguarded (ANALYSIS.md §1.3j).
            % Pinning it would assert the gap is intended rather than tolerated.
            writeFcn('tc_local', { ...
                'function y = tc_local(x)', ...
                'm = 4;', ...            % a local, not an input
                'y = 0;', ...
                'for k = 1:m', ...
                '  y = y + x(k)^2;', ...
                'end', ...
                'end'});
            adigator('tc_local',{adigatorCreateDerivInput([4 1],'x')},'tc_loc_d', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;
            txt = fileread('tc_loc_d.m');
            tc.verifyFalse(contains(txt,'assert('), ...
                'a local loop bound is not a function input - no guard is emittable');

            % values still correct with no guard involved
            x.f = (1:4).'; x.dx = ones(4,1);
            out = tc_loc_d(x);
            tc.verifyEqual(out.f, sum((1:4).'.^2), 'AbsTol', 1e-12, 'RelTol', 1e-12);
        end

        %% -------- route 1: bound passed through into a subfunction -------- %%

        function passThroughSubfunctionEarnsAGuard(tc)
            % Route 1 of the B36 residuals (#213), the shape the issue calls the
            % most likely real-world one: main takes N and hands it to a
            % subfunction that loops on it. The guard is earned by resolving the
            % SUBFUNCTION's parameter back through the call site to a main input
            % - so it is still the main-scope `assert(N == n);` #211 already
            % emits, and every recognizer/whitelist/re-diff path is unchanged.
            writeFcn('tc_pt', { ...
                'function y = tc_pt(x,N)', 'y = tc_pt_sub(x,N);', 'end', ...
                'function s = tc_pt_sub(x,N)', 's = 0;', ...
                'for k = 1:N', '  s = s + x(k)^2;', 'end', 'end'});
            n = 4;
            adigatorGenJacFile('tc_pt', ...
                {adigatorCreateDerivInput([n 1],'x'), n}, ...
                adigatorOptions('overwrite',1,'echo',0), 'Grd');
            rehash;
            tc.verifyTrue(contains(fileread('tc_pt_ADiGatorGrd.m'), ...
                sprintf('assert(N == %d);',n)), ...
                'a bound passed through to a subfunction must be guarded');

            % values right at the generated count ...
            rng(3); xf = randn(n,1);
            [G,F] = tc_pt_Grd(xf,n);
            tc.verifyEqual(F, sum(xf.^2), 'AbsTol',1e-12, 'RelTol',1e-12);
            tc.verifyEqual(G(:), 2*xf, 'AbsTol',1e-12, 'RelTol',1e-12);
            % ... and the silent-wrong call B36 exists to stop now errors
            tc.verifyError(@() tc_pt_Grd(randn(8,1),8), ...
                'MATLAB:assertion:failed', ...
                'calling above the specialized count must fail, not return the old answer');
        end

        function passThroughGuardsTheCallersInputNotTheParameterName(tc)
            % Resolution is by IDENTITY THROUGH THE CALL, not name equality:
            % main's input is M, the subfunction spells its parameter N, and the
            % guard must name M. This is the property that dissolves the
            % shadowing forge rather than merely dodging it - a guard on the
            % callee's spelling would be meaningless in main's scope.
            writeFcn('tc_ptr', { ...
                'function y = tc_ptr(x,M)', 'y = tc_ptr_sub(x,M);', 'end', ...
                'function s = tc_ptr_sub(x,N)', 's = 0;', ...
                'for k = 1:N', '  s = s + x(k)^2;', 'end', 'end'});
            n = 4;
            adigatorGenJacFile('tc_ptr', ...
                {adigatorCreateDerivInput([n 1],'x'), n}, ...
                adigatorOptions('overwrite',1,'echo',0), 'Grd');
            rehash;
            txt = fileread('tc_ptr_ADiGatorGrd.m');
            tc.verifyTrue(contains(txt, sprintf('assert(M == %d);',n)), ...
                'the guard must name the CALLER''s input');
            tc.verifyFalse(contains(txt,'assert(N =='), ...
                'the callee''s parameter spelling is not a name in main''s scope');
        end

        function passThroughDeclinesWhenCallSitesDisagree(tc)
            % One printed body serves all call sites (adigator prints per
            % FUNCTION, not per call), so a callee reached with two different
            % inputs has no single value to assert. Guarding either one would
            % reject correct calls through the other - fail closed instead.
            writeFcn('tc_ptd', { ...
                'function y = tc_ptd(x,N,M)', ...
                'a = tc_ptd_sub(x,N);', 'b = tc_ptd_sub(x,M);', 'y = a+b;', 'end', ...
                'function s = tc_ptd_sub(x,N)', 's = 0;', ...
                'for k = 1:N', '  s = s + x(k)^2;', 'end', 'end'});
            n = 4;
            adigatorGenJacFile('tc_ptd', ...
                {adigatorCreateDerivInput([n 1],'x'), n, n}, ...
                adigatorOptions('overwrite',1,'echo',0), 'Grd');
            rehash;
            txt = fileread('tc_ptd_ADiGatorGrd.m');
            tc.verifyFalse(contains(txt,'assert(N =='), ...
                'disagreeing call sites must not earn a guard');
            tc.verifyFalse(contains(txt,'assert(M =='), ...
                'disagreeing call sites must not earn a guard');
        end

        function twoHopCallSiteDoesNotForgeAGuard(tc)
            % The shadowing forge, one hop deeper - and the reason resolution
            % records the CALLER's id and not just the argument text. Here
            % `energy` has a LOCAL `N = numel(x)` that merely shares main's
            % spelling, and passes it to a subfunction that loops on it. main's
            % own `N` is an unrelated multiplier: the file is correct for EVERY
            % N, so any guard on it rejects correct calls.
            %
            % Resolving that call site would be name equality, not identity -
            % exactly what the TRIPCOUNTSCAN gate exists to prevent. Only a call
            % site inside the main function names something in main's scope.
            % (one user-function call per line - an ADiGator restriction)
            writeFcn('tc_2hop', { ...
                'function y = tc_2hop(x,N)', ...
                'a = tc_2hop_scale(x,N);', ...
                'b = tc_2hop_energy(x);', ...
                'y = a + b;', 'end', ...
                'function y = tc_2hop_scale(x,N)', 'y = sum(x)*N;', 'end', ...
                'function y = tc_2hop_energy(x)', ...
                'N = numel(x);', 'y = tc_2hop_accum(x,N);', 'end', ...
                'function y = tc_2hop_accum(x,N)', 'y = 0;', ...
                'for k = 1:N', '  y = y + x(k)^2;', 'end', 'end'});
            n = 4;
            adigatorGenJacFile('tc_2hop', ...
                {adigatorCreateDerivInput([n 1],'x'), 2}, ...
                adigatorOptions('overwrite',1,'echo',0), 'Grd');
            rehash;
            tc.verifyFalse(contains(fileread('tc_2hop_ADiGatorGrd.m'),'assert(N =='), ...
                ['a name resolved from a SUBFUNCTION''s scope must never be ', ...
                 'guarded as a main input - that is the shadowing forge']);

            % and the file must still work at a DIFFERENT N, which is the whole
            % point: N here does not control any trip count
            rng(2); xf = randn(n,1);
            [G,F] = tc_2hop_Grd(xf,5);
            tc.verifyEqual(F, sum(xf)*5 + sum(xf.^2), 'AbsTol',1e-12, 'RelTol',1e-12, ...
                'a forged guard would have rejected this correct call');
            tc.verifyEqual(G(:), 5*ones(n,1) + 2*xf, 'AbsTol',1e-12, 'RelTol',1e-12);
        end

        function passThroughDeclinesOnANonBareArgument(tc)
            % Only a bare identifier carries a main input's value unchanged
            % through the call. An expression does not - `sub(x,N-1)` loops N-1
            % times, so `assert(N == n)` would state the wrong specialization.
            writeFcn('tc_pte', { ...
                'function y = tc_pte(x,N)', 'y = tc_pte_sub(x,N-1);', 'end', ...
                'function s = tc_pte_sub(x,N)', 's = 0;', ...
                'for k = 1:N', '  s = s + x(k)^2;', 'end', 'end'});
            n = 5;
            adigatorGenJacFile('tc_pte', ...
                {adigatorCreateDerivInput([n 1],'x'), n}, ...
                adigatorOptions('overwrite',1,'echo',0), 'Grd');
            rehash;
            tc.verifyFalse(contains(fileread('tc_pte_ADiGatorGrd.m'),'assert(N =='), ...
                'an expression argument must not earn a guard');
        end

        function passThroughGuardSurvivesReDifferentiation(tc)
            % The load-bearing case, same as the direct form's: from level 2 the
            % source's loop header is already a literal, so the parameter name
            % survives only by recognizing, dropping and re-recording the
            % previous level's guard. Exercised here through the SECOND-order
            % path, which is as far as this shape goes -- see the third-order
            % note below.
            writeFcn('tc_pt2', { ...
                'function y = tc_pt2(x,N)', 'y = tc_pt2_sub(x,N);', 'end', ...
                'function s = tc_pt2_sub(x,N)', 's = 0;', ...
                'for k = 1:N', '  s = s + x(k)^3;', 'end', 'end'});
            n = 4;
            adigatorGenHesFile('tc_pt2', ...
                {adigatorCreateDerivInput([n 1],'x'), n}, ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;
            for f = {'tc_pt2_ADiGatorGrd.m','tc_pt2_ADiGatorHes.m'}
                tc.verifyEqual(numel(strfind(fileread(f{1}), ...
                    sprintf('assert(N == %d);',n))), 1, ...
                    sprintf('%s must carry exactly one specialization guard',f{1}));
            end
            % analytic-exact through 2nd order: sum(x^3) -> 3x^2 -> diag(6x)
            rng(7); xf = randn(n,1);
            [H,G,F] = tc_pt2_Hes(xf,n);
            tc.verifyEqual(F, sum(xf.^3), 'AbsTol',1e-12, 'RelTol',1e-12);
            tc.verifyEqual(G(:), 3*xf.^2, 'AbsTol',1e-12, 'RelTol',1e-12);
            tc.verifyEqual(full(H), diag(6*xf), 'AbsTol',1e-12, 'RelTol',1e-12);
            tc.verifyError(@() tc_pt2_Hes(randn(8,1),8), ...
                'MATLAB:assertion:failed', ...
                'the guard must still fire at second order');
        end

        function reDifferentiatingASubfunctionCallingFileIsUnsupported(tc)
            % Boundary, and NOT a route-1 defect: chaining adigator() by hand
            % over a generated file that CALLS A SUBFUNCTION fails, and it fails
            % with no trip count, no bound parameter and nothing this feature
            % touches. It is why the test above stops at second order (which
            % adigatorGenHesFile reaches by its own route) rather than pinning
            % third the way the direct form does.
            %
            % Pinned so the boundary is a known, stated one: if a future change
            % makes this work, this test fails and the third-order pin can be
            % restored for the pass-through shape too.
            writeFcn('tc_srp', { ...
                'function y = tc_srp(x)', 'y = tc_srp_sub(x);', 'end', ...
                'function s = tc_srp_sub(x)', 's = sum(x.^3);', 'end'});
            n = 4;
            adigator('tc_srp',{adigatorCreateDerivInput([n 1],'x')},'tc_srp_d', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;
            tc.verifyError(@() adigator('tc_srp_d', ...
                {adigatorCreateDerivInput([n 1],'x')},'tc_srp_dd', ...
                adigatorOptions('overwrite',1,'echo',0)), ...
                ?MException, ...
                ['re-differentiating a subfunction-calling generated file is ', ...
                 'expected to fail today; if it now works, restore the ', ...
                 'third-order pass-through pin. Deliberately NOT pinned to a ', ...
                 'specific error id - the failure is MATLAB-internal and not ', ...
                 'this feature''s to own, so the id is not a stable contract']);
        end

        %% ---- route 4(a): a bound-derived count that matches no bound ---- %%

        function boundDerivedCountThatMatchesNoBoundIsRefused(tc)
            % Route 4(a) of the B36 residuals (#213), and the last silent-wrong
            % of this family. `loopbound` matches loops BY TRIP-COUNT VALUE, so
            % a second loop over `N-1` matches nothing, silently takes a LITERAL
            % header inside a runtime-bound file, and is then wrong for every
            % call below the maximum - while the file's own `assert(N <= Nmax)`
            % is satisfied by exactly those calls.
            %
            % It refuses rather than emitting a bound-derived header for an
            % EXPRESSIVE reason, not a semantic one: `for c = 1:N-1` under the
            % file's existing assert would in fact be correct (the analyzed set
            % contains the runtime one and the loop-variable values do not
            % depend on N), but matching is by trip-count VALUE and only
            % `1:<name>` headers can be emitted, so an affine bound has no form
            % today - issue #6 Tier 2. Until it does, loud beats silent.
            Nmax = 6;
            writeFcn('tc_r4bad', { ...
                'function y = tc_r4bad(x,N)', 'y = 0;', ...
                'for a = 1:N', '  y = y + x(a)^2;', 'end', ...
                'for b = 1:N-1', '  y = y + x(b);', 'end', 'end'});
            tc.verifyError(@() adigatorGenJacFile('tc_r4bad', ...
                {adigatorCreateDerivInput([Nmax 1],'x'), Nmax}, ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N'), 'Grd'), ...
                'adigator:loopbound:rangemismatch', ...
                ['a bound-derived trip count matching no declared bound must ', ...
                 'refuse, not silently take a literal header']);
        end

        function legitimateLoopboundShapesStillGenerate(tc)
            % The refusal above must be narrow. It keys on the range EXPRESSION
            % naming a declared bound, so: two loops that BOTH match are fine, a
            % deliberate fixed `1:3` inside a loopbound file never mentions the
            % bound and is untouched, and a single matching loop is the ordinary
            % case. If any of these started refusing, the check would have made
            % the option unusable rather than safer.
            Nmax = 6;
            gx = @() adigatorCreateDerivInput([Nmax 1],'x');
            opt = adigatorOptions('overwrite',1,'echo',0,'loopbound','N');

            writeFcn('tc_r4ok', { ...
                'function y = tc_r4ok(x,N)', 'y = 0;', ...
                'for a = 1:N', '  y = y + x(a)^2;', 'end', ...
                'for b = 1:N', '  y = y + x(b);', 'end', 'end'});
            tc.verifyWarningFree(@() adigatorGenJacFile('tc_r4ok', ...
                {gx(), Nmax}, opt, 'Grd'), 'two matching loops must generate');

            writeFcn('tc_r4lit', { ...
                'function y = tc_r4lit(x,N)', 'y = 0;', ...
                'for a = 1:N', '  y = y + x(a)^2;', 'end', ...
                'for b = 1:3', '  y = y + x(b);', 'end', 'end'});
            tc.verifyWarningFree(@() adigatorGenJacFile('tc_r4lit', ...
                {gx(), Nmax}, opt, 'Grd'), ...
                'a deliberate literal loop names no bound and must generate');

            writeFcn('tc_r4one', { ...
                'function y = tc_r4one(x,N)', 'y = 0;', ...
                'for a = 1:N', '  y = y + x(a)^2;', 'end', 'end'});
            tc.verifyWarningFree(@() adigatorGenJacFile('tc_r4one', ...
                {gx(), Nmax}, opt, 'Grd'), ...
                'the ordinary single-loop loopbound case must generate');

            % and the ordinary case still behaves: padded semantics at n < Nmax
            rehash;
            rng(11); xf = randn(Nmax,1);
            [G,F] = tc_r4one_Grd(xf,4);
            tc.verifyEqual(F, sum(xf(1:4).^2), 'AbsTol',1e-12, 'RelTol',1e-12, ...
                'the runtime bound must still run its first n iterations');
            tc.verifyEqual(G(1:4), 2*xf(1:4), 'AbsTol',1e-12, 'RelTol',1e-12);
            tc.verifyEqual(G(5:end), zeros(Nmax-4,1), 'AbsTol', 0, ...
                'the skipped tail must stay structurally zero');

            % pin the HEADERS, not just the absence of an error: a regression
            % that made adigatorLoopboundMatch match everything would otherwise
            % keep this test green.
            src = fileread('tc_r4ok_ADiGatorGrd.m');
            tc.verifyEqual(numel(regexp(src,'for cadaforcount\d+ = 1:N','match')), 2, ...
                'both matching loops must take the RUNTIME header');
            src = fileread('tc_r4lit_ADiGatorGrd.m');
            tc.verifyNotEmpty(regexp(src,'for cadaforcount\d+ = 1:N','once'), ...
                'the matching loop must take the runtime header');
            tc.verifyNotEmpty(regexp(src,'for cadaforcount\d+ = 1:3','once'), ...
                'the deliberate literal loop must stay literal');
        end

        function aSubfunctionLoopOverTheBoundDoesNotDisturbTheCheck(tc)
            % ForCount RESTARTS per function (0 for the main function, 1 for
            % every subfunction), so an ungated record has subfunction loops
            % overwriting main-function entries BY INDEX. That cuts both ways,
            % and both are pinned here.
            Nmax = 6;
            opt = adigatorOptions('overwrite',1,'echo',0,'loopbound','N');

            % (a) FALSE REFUSAL: main's second loop is a deliberate literal, but
            % a subfunction's loop over the bound lands on the same ForCount.
            % Ungated, that forges a refusal for a file that is correct.
            writeFcn('tc_r4sub', { ...
                'function y = tc_r4sub(x,N)', 'y = 0;', ...
                'for a = 1:N', '  y = y + x(a)^2;', 'end', ...
                'for b = 1:3', '  y = y + x(b);', 'end', ...
                'y = y + tc_r4sub_h(x,N);', 'end', ...
                'function z = tc_r4sub_h(x,N)', 'z = 0;', ...
                'for i = 1:N', '  z = z + x(i);', 'end', 'end'});
            tc.verifyWarningFree(@() adigatorGenJacFile('tc_r4sub', ...
                {adigatorCreateDerivInput([Nmax 1],'x'), Nmax}, opt, 'Grd'), ...
                ['a subfunction loop over the bound must not forge a refusal ', ...
                 'for an unrelated main-function loop']);

            % (b) FALSE NEGATIVE: the real route-4(a) pair in main, plus a
            % subfunction loop that does NOT name the bound. Ungated, the
            % subfunction erases main's record and the bad file generates.
            writeFcn('tc_r4sub2', { ...
                'function y = tc_r4sub2(x,N)', 'y = 0;', ...
                'for a = 1:N', '  y = y + x(a)^2;', 'end', ...
                'for b = 1:N-1', '  y = y + x(b);', 'end', ...
                'y = y + tc_r4sub2_h(x);', 'end', ...
                'function z = tc_r4sub2_h(x)', 'z = 0;', ...
                'for i = 1:2', '  z = z + x(i);', 'end', 'end'});
            tc.verifyError(@() adigatorGenJacFile('tc_r4sub2', ...
                {adigatorCreateDerivInput([Nmax 1],'x'), Nmax}, opt, 'Grd'), ...
                'adigator:loopbound:rangemismatch', ...
                ['a subfunction loop must not erase the main function''s ', ...
                 'record and let the mismatched loop through']);
        end

        function aFieldReferencedBoundIsNotTreatedAsAMention(tc)
            % `1:p.N` is route 2 of the residuals, not route 4(a): the `N` there
            % is a struct field, not the declared bound. The recorder's
            % leading-dot exclusion keeps it generating as it does today - over-
            % collecting here would refuse a shape that has always worked.
            Nmax = 6;
            writeFcn('tc_r4fld', { ...
                'function y = tc_r4fld(x,N,p)', 'y = 0;', ...
                'for a = 1:N', '  y = y + x(a)^2;', 'end', ...
                'for b = 1:p.N', '  y = y + x(b);', 'end', 'end'});
            pp.N = 3;
            tc.verifyWarningFree(@() adigatorGenJacFile('tc_r4fld', ...
                {adigatorCreateDerivInput([Nmax 1],'x'), Nmax, pp}, ...
                adigatorOptions('overwrite',1,'echo',0,'loopbound','N'), 'Grd'), ...
                'a field reference must not read as a mention of the bound');
        end
    end
end

function writeCubeSum()
% sum of cubes over a NAMED runtime trip count - analytic to any order
writeFcn('tc_cube', { ...
    'function y = tc_cube(x,N)', ...
    'y = 0;', ...
    'for k = 1:N', ...
    '  y = y + x(k)^3;', ...
    'end', ...
    'end'});
end

function writeFcn(name, lines)
% write a fixture function file into the (temporary) working folder
fid = fopen([name '.m'], 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end
