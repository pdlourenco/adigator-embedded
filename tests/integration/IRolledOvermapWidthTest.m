classdef IRolledOvermapWidthTest < AdigatorTestCase
    % IRolledOvermapWidthTest  #217 / ADR-0036: the printing run of a rolled
    % loop must not carry a second-derivative pattern wider than the loop
    % overmap it is about to be squeezed into.
    %
    % A rolled `for` is walked twice. The OVERMAP run sees each iteration's
    % EXACT derivative pattern and unions them; the PRINTING run walks the body
    % once, so every operand carries that union instead. Composing two unions as
    % if they were independent loses the correlation between them: for
    % `y = y + exp(x(k))` the per-iteration second-derivative pattern is the
    % single entry (k,k) and the union is the n-nonzero DIAGONAL, but the
    % printing run produced the full n-by-n cross product and gathered n^2
    % doubles onto the stack - 37.5 KB at n=64, 63x hand-written - only for
    % cadaPrintReMap to squeeze it back to n one statement later.
    %
    % This is the LICENSE-FREE half of that regression. The stack itself is
    % measurable only with Coder + Embedded Coder + gcc, so the real gate
    % (SStackScalingTest, ADR-0035) can never run on hosted CI (CI_PLAN.md
    % §3.2). But the n^2 temporary was gathered THROUGH an n^2 static
    % second-derivative index table, so `Gator2Data`'s size tracks the defect
    % exactly: it is quadratic if and only if the stack temporary is. That needs
    % no toolchain at all.
    %
    % Gator1Data is deliberately NOT asserted on: its per-iteration mask table is
    % [nzover x niters] and therefore n^2 by construction in a rolled loop. That
    % is the rolled form's own cost, not this defect, and it lives in ROM as
    % int8 rather than on the stack as doubles.
    %
    %   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
    %   Public License version 3.0.

    properties (Constant)
        % Two sizes, because the question is a growth law and one point cannot
        % answer it. Before ADR-0036 these tables were 64 and 256 entries.
        Sizes = [8 16]
        % Generous: the exact post-fix answer is n. A quadratic table is 8n at
        % n=8 and 16n at n=16, so 4n separates the two regimes at BOTH sizes
        % without pinning an incidental constant.
        MaxPerN = 4
    end

    methods (TestClassSetup)
        function addHelperPath(tc)
            % writeFixtureFile / fdcheck live in tests/helpers, which the base
            % class does not add. Distinct method name so the base setup still
            % runs (see AdigatorTestCase).
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
        function diagonalHessianKeepsLinearSecondDerivMetadata(tc)
            % The #217 anchor, as a growth law. y = sum_k exp(x_k) + 2 x_k has a
            % DIAGONAL Hessian, and the tool knows it - the exported pattern is
            % n nonzeros (SCscMetadataTest/TS-S-08). Nothing interior may be
            % quadratic either.
            writeFixtureFile('rowRolledDiag', { ...
                'n = size(x,1);', 'y = 0;', ...
                'for k = 1:n', '    y = y + exp(x(k)) + 2*x(k);', 'end'});
            widths = zeros(size(tc.Sizes));
            for i = 1:numel(tc.Sizes)
                n = tc.Sizes(i);
                [widths(i), which] = tc.gator2Width('rowRolledDiag', n);
                tc.verifyLessThanOrEqual(widths(i), tc.MaxPerN*n, sprintf( ...
                    ['#217: widest Gator2Data index table is %s at %d entries, ', ...
                     'n=%d. The Hessian of sum_k exp(x_k) is diagonal, so the ', ...
                     'interior second-derivative pattern must be O(n), not ', ...
                     'O(n^2) - a quadratic table is the n^2 stack gather ', ...
                     'ADR-0036 removed.'], which, widths(i), n));
            end
            % Growth law, not just magnitude: doubling n must roughly double the
            % table (linear), not quadruple it (the defect).
            tc.verifyLessThanOrEqual(widths(2), 2.5*widths(1), sprintf( ...
                ['#217: Gator2Data width went %d -> %d over n = %d -> %d. ', ...
                 'Doubling n must about double it; ~4x is the quadratic ', ...
                 'signature.'], widths(1), widths(2), tc.Sizes(1), tc.Sizes(2)));
        end

        function prunedRolledHessianStillMatchesAnalytic(tc)
            % Principle 1: a narrower pattern must not mean a different answer.
            % Values, against the closed form AND against finite differences.
            writeFixtureFile('rowRolledDiagV', { ...
                'n = size(x,1);', 'y = 0;', ...
                'for k = 1:n', '    y = y + exp(x(k)) + 2*x(k);', 'end'});
            n = 8;
            d = tc.genHes('rowRolledDiagV', n);
            rng(4); xf = 0.4*randn(n,1);
            [H,G,F] = tc.runIn(d, 'rowRolledDiagV_Hes', xf);
            tc.verifyEqual(H, diag(exp(xf)), 'AbsTol', 1e-12, 'RelTol', 1e-12, ...
                'rolled diagonal Hessian must equal diag(exp(x))');
            tc.verifyEqual(G(:), exp(xf) + 2, 'AbsTol', 1e-12, 'RelTol', 1e-12, ...
                'rolled gradient must equal exp(x)+2');
            tc.verifyEqual(F, sum(exp(xf) + 2*xf), 'AbsTol', 1e-12, 'RelTol', 1e-12);
            Hfd = squeeze(fdcheck('hess', @(v) rowRolledDiagV(v), xf));
            tc.verifyEqual(H, Hfd, 'AbsTol', 1e-4, ...
                'rolled diagonal Hessian must survive a finite-difference check');
        end

        function genuinelyDenseRolledHessianIsNotPruned(tc)
            % The other side of the guard, and the one that matters: the prune
            % must not fire when the answer really IS dense. Here every iteration
            % couples x(k) to ALL of x through the sum, so the exact Hessian is
            % full - if pruning were over-eager it would silently zero the
            % off-diagonal, which is exactly the failure mode principle 1 is
            % about.
            %
            % Two assertions make this a guard rather than theatre. The width
            % must come out QUADRATIC here (the opposite of the case above): that
            % is what shows the prune ran over a genuinely wide pattern and kept
            % it, not that this fixture is a second diagonal case in disguise.
            % And the values must survive finite differences. If a future change
            % legitimately narrows this shape, the width assertion fires first -
            % check the FD values still pass, then relax it.
            writeFixtureFile('rowRolledDense', { ...
                'n = size(x,1);', 'p = sum(x);', 'y = 0;', ...
                'for k = 1:n', '    y = y + p*exp(x(k));', 'end'});
            n = 6;
            d = tc.genHes('rowRolledDense', n);
            rng(11); xf = 0.3*randn(n,1);
            [H,G,F] = tc.runIn(d, 'rowRolledDense_Hes', xf);
            tc.verifyEqual(F, sum(sum(xf)*exp(xf)), 'AbsTol', 1e-12, 'RelTol', 1e-12);
            tc.verifyEqual(G(:), fdcheck('jac', @(v) rowRolledDense(v), xf).', ...
                'AbsTol', 1e-5, 'gradient of the dense rolled case');
            Hfd = squeeze(fdcheck('hess', @(v) rowRolledDense(v), xf));
            tc.verifyEqual(H, Hfd, 'AbsTol', 1e-4, ...
                ['dense rolled Hessian must survive finite differences - if the ', ...
                 'ADR-0036 prune fires here it drops real off-diagonal terms']);
            tc.verifyGreaterThan(nnz(abs(H) > 1e-8), n, ...
                'this fixture is only a guard if its Hessian is actually dense');
            [w, which] = tc.gator2Width('rowRolledDense', n);
            tc.verifyGreaterThan(w, tc.MaxPerN*n, sprintf( ...
                ['the dense fixture''s widest Gator2Data table is %s at %d ', ...
                 'entries for n=%d - that is not quadratic, so this case no ', ...
                 'longer proves the ADR-0036 prune leaves a genuinely wide ', ...
                 'pattern alone.'], which, w, n));
        end

        function pruneGateStaysInStepWithTheRemapGate(tc)
            % The load-bearing obligation ADR-0036 creates, made testable.
            %
            % The whole safety argument is "the prune removes only what
            % cadaPrintReMap is about to discard anyway", and that holds ONLY
            % because cadaOverMapTargetNz gates on the same two things
            % cadaOverMap's printing branch uses to decide whether it calls
            % cadaPrintReMap at all: OVERMAP.FOR(id,1) and NAMELOCS(id,3). If
            % either side's gate is changed without the other, the prune starts
            % removing locations that survive - a silently wrong derivative,
            % not an error (principle 1). Vigilance is not a mechanism; this is.
            %
            % Static, comment-stripped (a comment naming the pattern must not
            % satisfy the guard), and license-free.
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            gate = @(s) [~isempty(regexp(s, ...
                            'ADIGATOR\.VARINFO\.OVERMAP\.FOR\(\s*\w+\s*,\s*1\s*\)','once')), ...
                         ~isempty(regexp(s, ...
                            'ADIGATOR\.VARINFO\.NAMELOCS\(\s*\w+\s*,\s*3\s*\)','once'))];

            helper = tc.codeLines(fullfile(root,'lib','@cada','private','cadaOverMapTargetNz.m'));
            tc.verifyEqual(gate(helper), [true true], ...
                ['cadaOverMapTargetNz no longer gates on BOTH OVERMAP.FOR(id,1) ', ...
                 'and NAMELOCS(id,3). Those two are what make the prune a subset ', ...
                 'of what cadaPrintReMap discards (ADR-0036) - if the gate has ', ...
                 'genuinely moved, re-derive the safety argument before relaxing ', ...
                 'this test.']);

            overmap = tc.codeLines(fullfile(root,'lib','@cada','cadaOverMap.m'));
            tc.verifyEqual(gate(overmap), [true true], ...
                ['cadaOverMap no longer gates its remap on BOTH OVERMAP.FOR(id,1) ', ...
                 'and NAMELOCS(id,3), so cadaOverMapTargetNz is mirroring a test ', ...
                 'that no longer exists (ADR-0036).']);

            % and the mirrored site must still be the one that calls the remap
            tc.verifyNotEmpty(regexp(overmap,'cadaPrintReMap','once'), ...
                'cadaOverMap no longer calls cadaPrintReMap - ADR-0036 needs revisiting');
        end
    end

    methods (Access = private)
        function s = codeLines(~, file)
            % File contents with comments stripped, so a static guard cannot be
            % satisfied by a comment that merely names the pattern it requires.
            % The strip is naive (first '%' to end of line); for a REQUIRE-style
            % guard like this one that direction is strict, never permissive.
            txt = fileread(file);
            c = regexp(txt, '\r\n|\n|\r', 'split');
            s = strjoin(regexprep(c, '%.*$', ''), newline);
        end

        function [w, which] = gator2Width(tc, fname, n)
            % Widest Gator2Data index table of the rolled Hessian at size n, and
            % which field it was. The max is over every Index* rather than the
            % one field that carried the #217 gather, because the emitted names
            % are generation-order artifacts and pinning one would be more
            % brittle than the breadth is - `which` is returned so a future
            % failure names the table instead of just the number.
            d = tc.genHes(fname, n);
            S = load(fullfile(d, [fname '_ADiGatorHes.mat']));
            T = S.([fname '_ADiGatorHes']);
            tc.assertTrue(isfield(T,'Gator2Data'), ...
                'second-derivative static data missing - generation changed shape');
            g = T.Gator2Data;
            w = 0; which = '';
            for f = fieldnames(g).'
                if strncmp(f{1},'Index',5) && numel(g.(f{1})) > w
                    w = numel(g.(f{1})); which = f{1};
                end
            end
            tc.assertGreaterThan(w, 0, 'no Gator2Data.Index* tables found');
        end

        function d = genHes(~, fname, n)
            % Rolled (unroll=0, the default) classic Hessian into its own folder,
            % so the .mat with the static index tables survives for inspection.
            d = fullfile(pwd, sprintf('%s_n%d', fname, n));
            adigatorGenHesFile(fname, {adigatorCreateDerivInput([n 1],'x')}, ...
                adigatorOptions('overwrite',1,'echo',0,'path',d));
        end

        function varargout = runIn(~, d, wrapper, xf)
            % Clear the wrapper, the _ADiGatorHes file AND its persistent global
            % before running: this class generates same-named artifacts into
            % sibling folders, and a plain clear(wrapper) misses the
            % cross-directory .mat staleness (the ILoopboundTest precedent).
            old = cd(d);
            restore = onCleanup(@() cd(old));
            adi = strrep(wrapper,'_Hes','_ADiGatorHes');
            clear(wrapper); clear(adi); clear('global',['ADiGator_',adi]);
            rehash;
            [varargout{1:nargout}] = feval(wrapper, xf);
        end
    end
end
