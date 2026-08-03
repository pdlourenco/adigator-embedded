classdef IScatterPrototypeTest < AdigatorTestCase
    % IScatterPrototypeTest  R21 acceptance reference FOR THE ALLOCATION SHAPE:
    % the fixed-size scatter form must compute exactly what the current rolled
    % emission computes.
    %
    % R21 (issue #80, ADR-0019) replaces the rolled accumulator's
    % "compute at overmap width, remap late" shape with "compute at
    % per-iteration width `nz_k`, scatter through a position map":
    %
    %     yd(Gator1Data.IndexK(:,c)) = yd(Gator1Data.IndexK(:,c)) + contrib;
    %
    % `scatterReference` below IS that target emission, written by hand for the
    % allocation/loopbound anchor, where `nz_k = 1` and the position map is the
    % affine family `col(c) = c`. It was measured against the generated file as
    % experiment E6 of the 2026-08-02 engine-v2 analysis: values identical to
    % the last bit, ROM 4400 -> 160 B, stack 352 -> 96 B.
    %
    % Why this exists as a TEST rather than as the scratch harness it started
    % as: ADR-0019's O(n^2)-stack figure was quoted into CI_PLAN and ADR-0033
    % from a measurement nobody could re-run, did not reproduce, and had to be
    % retracted from both (#216). The ROADMAP now leans on E6's numbers the same
    % way. A file under bench/ that nothing executes would repeat that; a test
    % cannot go stale silently.
    %
    % It is deliberately LICENSE-FREE. The footprint half of E6 (ROM, stack)
    % needs Coder + Embedded Coder + gcc and can never run on hosted CI
    % (CI_PLAN.md §3.2). The VALUE half needs nothing, and it is the half
    % principle 1 cares about: R21 is the highest-correctness-stakes change in
    % the repo, so what must be pinned before it starts is that the new shape
    % and the old shape agree.
    %
    % When R21 lands this test keeps its meaning unchanged -- the generated file
    % should then BE this shape, and must still equal the reference.
    %
    % SCOPE, stated because the headline would otherwise overreach it. This
    % pins the SIMPLEST instance of the target shape: `nz_k = 1`, and a position
    % map that is the identity family `col(c) = c`. Two consequences follow, and
    % neither is a defect in the test so much as a boundary on what it proves:
    %
    %   * **HZ-1 is unreachable here.** Duplicate rows within a position-map
    %     column cannot occur when every column has exactly one entry, so the
    %     silent-wrongness hazard that decides the R21 design is NOT exercised.
    %   * An identity map never exercises the position-map machinery at all.
    %
    % So this is a genuine regression net for the allocation anchor and a real
    % acceptance gate for "the new shape agrees with the old one there" -- but
    % it is not evidence that scatter is correct where the correctness risk
    % actually lives. A second anchor with `nz_k > 1` (a rolled Hessian, or
    % `y = y + x(k)*x(k+1)` for a two-nonzero column) is OWED when R21 is
    % scoped; it is deliberately not added now, because hand-writing a second
    % reference against emission that is about to change would pin the wrong
    % thing. That anchor would also give the E3 duplicate-target question a live
    % fixture instead of a bounded static census.
    %
    %   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
    %   Public License version 3.0.

    properties (Constant)
        Nmax = 16          % generation-time bound of the padded artifact
        % Runtime trip counts. 1 and 2 are included on purpose: small-n
        % structural collapse is where a scatter form would most plausibly
        % disagree with a vector-width one, and Nmax exercises the unpadded end.
        Runtime = [1 2 5 11 16]
    end

    methods (TestClassSetup)
        function addHelperPath(tc)
            % writeFixtureFile lives in tests/helpers, which the base class does
            % not add. Distinct method name so the base setup still runs.
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
        function scatterFormMatchesTheRolledEmission(tc)
            % The E6 equivalence, as a gate. Generated padded gradient vs the
            % §3.2 scatter form, at five runtime trip counts through ONE
            % artifact generated at Nmax.
            tc.writeAnchor();
            d = tc.genPaddedGrd(tc.Nmax);
            rng(21);
            xf = 0.4*randn(tc.Nmax,1);
            for n = tc.Runtime
                [Grd, Fun] = tc.runIn(d, 'scatterAnchor_Grd', xf, n);
                [Gsc, Fsc] = IScatterPrototypeTest.scatterReference(xf, n, tc.Nmax);
                % AbsTol 0 is deliberate and safe, and the two outputs rest on
                % DIFFERENT arguments - worth separating so a future reader does
                % not weaken the tolerance thinking both are fragile.
                %
                %   Grd: structural. With nz_k = 1 and col(c) = c each yd(k) is
                %     written exactly once, starting from 0, so the value is
                %     (0 + e_k) + 2 in both implementations and `0 + e_k` is
                %     exact. Bit-exactness here is not an ordering accident.
                %   Fun: ordering. yf accumulates across all iterations in both,
                %     and they agree because the association is the same, not
                %     merely equivalent - the emitted body computes
                %     (yd(k) + exp(x_k)*1) + 2*1 and the reference writes
                %     (yd(k) + ek.*xdk) + 2.*xdk, same operands, same
                %     left-to-right order.
                %
                % A future emission that reassociates the accumulation fires
                % this, which is correct: R21 must not silently change the
                % arithmetic.
                tc.verifyEqual(Grd, Gsc, 'AbsTol', 0, sprintf( ...
                    ['R21: the scatter form must reproduce the rolled ', ...
                     'emission BIT-EXACTLY at n=%d. Same operands, same ', ...
                     'association per element - a difference means the ', ...
                     'arithmetic changed, not merely the rounding.'], n));
                tc.verifyEqual(Fun, Fsc, 'AbsTol', 0, sprintf( ...
                    'R21: function values must agree exactly at n=%d', n));
            end
        end

        function scatterFormMatchesTheAnalyticGradient(tc)
            % Principle 1: "the two agree" is worthless if both are wrong. Pin
            % the reference against the closed form and against finite
            % differences, so this class cannot certify a shared error.
            tc.writeAnchor();
            rng(21);   % same point as scatterFormMatchesTheRolledEmission, so
                       % generated == reference == analytic closes at one x
            xf = 0.4*randn(tc.Nmax,1);
            for n = tc.Runtime
                [Gsc, Fsc] = IScatterPrototypeTest.scatterReference(xf, n, tc.Nmax);
                want = zeros(tc.Nmax,1);
                want(1:n) = exp(xf(1:n)) + 2;
                tc.verifyEqual(Gsc, want, 'AbsTol', 1e-12, 'RelTol', 1e-12, ...
                    sprintf('d/dx sum_{k<=%d} (exp(x_k)+2x_k) = exp(x)+2 on 1:%d', n, n));
                tc.verifyEqual(Fsc, sum(exp(xf(1:n)) + 2*xf(1:n)), ...
                    'AbsTol', 1e-12, 'RelTol', 1e-12);
                % Padded-program semantics (HZ-3): iterations above n never run,
                % so the tail must be a structural zero, not merely small.
                tc.verifyEqual(Gsc(n+1:end), zeros(tc.Nmax-n,1), 'AbsTol', 0, ...
                    'the padded tail must be exactly zero, by construction');
            end
            % fdcheck has no 'grad' mode; a scalar cost's Jacobian is its
            % gradient as a row, so compare flattened.
            Gfd = fdcheck('jac', @(v) scatterAnchor(v, tc.Nmax), xf);
            Gsc = IScatterPrototypeTest.scatterReference(xf, tc.Nmax, tc.Nmax);
            tc.verifyEqual(Gsc(:), Gfd(:), 'AbsTol', 1e-5, ...
                'the scatter reference must survive a finite-difference check');
        end

        function perIterationWidthIsTheScatterPremise(tc)
            % Guard the premise rather than assuming it. §3.2 targets O(1)
            % per-iteration width for this shape; if the anchor ever stopped
            % having nz_k = 1 the reference above would be modelling something
            % else, and the equivalence test would pass while meaning nothing.
            tc.writeAnchor();
            d = tc.genPaddedGrd(tc.Nmax);
            S = load(fullfile(d, 'scatterAnchor_ADiGatorGrd.mat'));
            T = S.scatterAnchor_ADiGatorGrd;
            tc.assertTrue(isfield(T,'Gator1Data'), ...
                'first-derivative static data missing - generation changed shape');
            % Today's tables are [nzover x niters] masks, i.e. Nmax^2. This is
            % a lower bound on numel only - the shape itself is asserted in the
            % loop below, which is where the premise actually lives.
            widest = 0;
            for f = fieldnames(T.Gator1Data).'
                if strncmp(f{1},'Index',5)
                    widest = max(widest, numel(T.Gator1Data.(f{1})));
                end
            end
            tc.verifyGreaterThanOrEqual(widest, tc.Nmax, ...
                'expected a per-iteration index table of at least Nmax entries');
            % One nonzero per column is the nz_k = 1 premise, read off the mask.
            nChecked = 0;
            for f = fieldnames(T.Gator1Data).'
                A = T.Gator1Data.(f{1});
                if strncmp(f{1},'Index',5) && size(A,2) == tc.Nmax && size(A,1) == tc.Nmax
                    % full(): the classic .mat stores these tables SPARSE, and
                    % verifyEqual compares sparsity as well as value.
                    nChecked = nChecked + 1;
                    perCol = full(sum(A ~= 0, 1));
                    tc.verifyEqual(unique(perCol), 1, sprintf( ...
                        ['R21 premise: %s must carry exactly one nonzero per ', ...
                         'iteration column (nz_k = 1) for the allocation ', ...
                         'shape; found %s.'], f{1}, mat2str(unique(perCol))));
                end
            end
            tc.assertGreaterThan(nChecked, 0, ...
                ['no [Nmax x Nmax] Gator1Data.Index* table was found, so the ', ...
                 'nz_k premise was never actually checked and this method ', ...
                 'passed vacuously. If the emission changed shape - R21 ', ...
                 'landing is the expected cause - re-derive this guard ', ...
                 'against the new table layout. Do not delete it.']);
        end
    end

    methods (Access = private)
        function writeAnchor(~)
            % The allocation/loopbound shape: a scalar cost accumulated over a
            % subscripted read, with a RUNTIME trip count. Mirrors
            % bench/showcase/scostfun_lb without depending on it (bench/ is
            % stripped from the release archive; tests must stand alone).
            %
            % Written here rather than through tests/helpers/writeFixtureFile,
            % which emits a single-input `function y = name(x)`; this anchor
            % needs the trip count as a second input, and widening a helper
            % five other classes rely on is the wrong trade for one fixture.
            fid = fopen('scatterAnchor.m','w');
            assert(fid > 0, 'could not create the scatterAnchor fixture');
            closer = onCleanup(@() fclose(fid));
            fprintf(fid, '%s\n', ...
                'function y = scatterAnchor(x,N)', ...
                'y = 0;', ...
                'for k = 1:N', ...
                '    y = y + exp(x(k)) + 2*x(k);', ...
                'end', ...
                'end');
            clear closer
            rehash;
        end

        function d = genPaddedGrd(~, Nmax)
            % ONE artifact at Nmax with a runtime bound (Tier 1 padded
            % semantics), classic mode so the .mat survives for inspection.
            d = fullfile(pwd, sprintf('scatterAnchor_N%d', Nmax));
            adigatorGenJacFile('scatterAnchor', ...
                {adigatorCreateDerivInput([Nmax 1],'x'), Nmax}, ...
                adigatorOptions('overwrite',1,'echo',0,'path',d,'loopbound','N'), ...
                'Grd');
        end

        function varargout = runIn(~, d, wrapper, xf, n)
            old = cd(d);
            restore = onCleanup(@() cd(old));
            adi = strrep(wrapper,'_Grd','_ADiGatorGrd');
            clear(wrapper); clear(adi); clear('global',['ADiGator_',adi]);
            rehash;
            [varargout{1:nargout}] = feval(wrapper, xf, n);
        end
    end

    methods (Static)
        function [yd, yf] = scatterReference(x, N, Nmax)
            % THE §3.2 TARGET EMISSION, by hand.
            %
            % Operands stay at per-iteration width (nz_k = 1 here: only x(k)
            % contributes to iteration k), and the result is scattered into the
            % overmap-sized accumulator through the position map column -- which
            % for this shape is the affine family col(c) = c, the case §5's
            % generator recognition would emit as an expression and drop the
            % table entirely.
            %
            % Contrast today's emission, which per iteration allocates a
            % zeros(Nmax,1) temporary, gathers through an [Nmax x Nmax] mask,
            % and adds two full-width vectors to update one entry.
            assert(N <= Nmax);
            yf = 0;
            yd = zeros(Nmax,1);          % accumulator, allocated ONCE (HZ-3)
            for c = 1:N
                k    = c;                % position map column
                xk   = x(k);
                xdk  = 1;                % per-iteration operand width nz_k = 1
                ek   = exp(xk);
                yd(k) = yd(k) + ek.*xdk + 2.*xdk;   % scatter into the accumulator
                yf   = yf + ek + 2*xk;
            end
        end
    end
end
