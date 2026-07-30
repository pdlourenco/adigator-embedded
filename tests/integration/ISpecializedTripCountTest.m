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
