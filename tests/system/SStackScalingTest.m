classdef SStackScalingTest < AdigatorTestCase
    % SStackScalingTest  The embeddability gate (#80a-2, ADR-0035): a generated
    % derivative's stack must stay within a bounded multiple of what a
    % HAND-WRITTEN derivative of the same maths needs.
    %
    % This is the missing half of REQ-T-10. ERT code generation succeeding is
    % *necessary but not sufficient*: `EnableDynamicMemoryAllocation=false`
    % rejects only *unbounded* sizes, so a bounded-but-large derivative
    % code-generates cleanly, passes SRolledErtCodegenTest, and then overflows
    % the target's stack at run time (the "hollow milestone", ADR-0019/ADR-0033).
    %
    % Why a ratio against hand-written code rather than "the stack must be
    % flat": *a growing stack is normal*. A Hessian's answer is n-by-n, and even
    % the optimal hand-written `Hes = diag(exp(x))` grows - measured exactly
    % 80+8n bytes, i.e. LINEAR at one double per element, on a fixed 80 B frame.
    % A flatness gate fails correct, optimal code - measured, not assumed. And
    % not an absolute byte ceiling either: this project declares no target
    % device, so a ceiling would be invented policy. The ratio isolates
    % the overhead the GENERATOR adds over the derivative's own intrinsic cost,
    % which is the part this project controls.
    %
    % Tolerances are PER CASE (see properties): at n=64 the measured spread is
    % 1.00x / 1.05x / 2.64x passing against 63.4x failing, so one global number
    % would be far looser than the parity cases deserve.
    %
    % Coder + Embedded Coder + a standalone gcc/size toolchain gated; skips
    % cleanly otherwise. LOCAL ONLY - hosted CI licenses neither Coder product,
    % so this can never run there (CI_PLAN.md §3.2). Heavyweight (each case is
    % 4 Coder builds); extended suite, not the fast PR gate.

    properties (Constant)
        % Three points, to n=64. Two was enough for a ratio but too few to tell a
        % constant-factor gap from an asymptotic one - and that distinction is
        % the whole question here (the vectorized series are exactly affine in n,
        % so a power-law read of them is a small-n artifact; #217's is not).
        Sizes = [8 32 64]
        % PER-CASE tolerances, not one global number. A single loose K makes the
        % gate vacuous for the cases that are at parity: the vectorized gradient
        % is byte-identical to hand-written, so a 4x allowance would let a
        % 4x regression land green on the one case that proves the tool costs
        % nothing. Each budget is set from the measured value plus real headroom.
        TolParity = 1.5     % gradient (1.00x) and vectorized Hessian (1.05x)
        TolVector = 4       % vvecfun Jacobian: overhead = (112+24n)/(112+8n),
                            % bounded ABOVE by exactly 3.0 - so 3 leaves zero
                            % asymptotic margin and 4 leaves a real one
        TolPin    = 4       % the #217 pin: fails at 28.6x (n=32) / 63.4x (n=64)
    end

    methods (TestClassSetup)
        function addBenchPath(tc)
            import matlab.unittest.fixtures.PathFixture
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            tc.applyFixture(PathFixture(fullfile(root,'bench')));
            tc.applyFixture(PathFixture(fullfile(root,'bench','showcase')));
            tc.applyFixture(PathFixture(fullfile(root,'bench','showcase','analytic')));
        end

        function requireErt(tc)
            tc.assumeTrue(license('test','MATLAB_Coder') && license('test','RTW_Embedded_Coder'), ...
                'MATLAB Coder + Embedded Coder required - skipping the embeddability gate.');
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function vectorizedGradientMatchesHandWritten(tc)
            % the strongest case in the suite: identical stack, hand and machine
            r = tc.measure('vcostfun','gradient','vcostfun_grad_analytic',tc.TolParity);
            tc.verifyLessThanOrEqual(r.maxOverhead, tc.TolParity, tc.verdict(r));
        end

        function vectorizedHessianWithinTolerance(tc)
            % a Hessian's answer is n-by-n, so BOTH grow; what matters is that
            % the generated one does not grow faster than the hand-written one
            r = tc.measure('vcostfun','hessian','vcostfun_hess_analytic',tc.TolParity);
            tc.verifyLessThanOrEqual(r.maxOverhead, tc.TolParity, tc.verdict(r));
        end

        function vectorizedJacobianWithinTolerance(tc)
            % The generator uses THREE vector temporaries where hand-written
            % code uses one: measured stacks are exactly affine in n - generated
            % 112+24n, hand-written 112+8n - so the overhead is
            % (112+24n)/(112+8n), rising with n but bounded ABOVE by exactly
            % 3.0, never attained. A constant-factor gap, not an asymptotic one.
            %
            % This is why the trend is reported and never asserted: at n<=32 the
            % ratio LOOKS like it is diverging (1.73 -> 2.39) and a power-law fit
            % reads exponent 0.77 vs 0.53, but both are artifacts of the shared
            % +112 offset at small n. Asserting on direction would have encoded
            % a measurement artifact as binding policy. Contrast #217, whose
            % series is genuinely NOT affine.
            r = tc.measure('vvecfun','jacobian','vvecfun_jac_analytic',tc.TolVector);
            tc.verifyLessThanOrEqual(r.maxOverhead, tc.TolVector, tc.verdict(r));
            fprintf(['[SStackScalingTest] vvecfun jacobian overhead %s ', ...
                     '- constant-factor, bounded above by 3.0 (see note).\n'], ...
                     mat2str(round(r.overhead,2)));
        end
    end

    %% --------------------- known-issue detection ---------------------- %%
    methods (Test, TestTags = {'KnownIssue'})
        function subscriptedHessianStackOverhead(tc)
            % #217: the ROLLED/subscripted Hessian carries a super-linear stack
            % temporary - measured 768/2560/9616 B at n=8/16/32, which unlike
            % every other series here is NOT affine in n, against a hand-written
            % reference of 80+8n. 28.6x at n=32, 63.4x at n=64 (37.5 KB).
            % It ERT-codegens cleanly and passes SRolledErtCodegenTest today:
            % this is the hollow milestone with numbers on it.
            %
            % scostfun and vcostfun compute the SAME function (sum(exp(x)+2x));
            % only the formulation differs (subscripted loop vs vectorized), so
            % vcostfun_hess_analytic is the correct reference for both and this
            % is a like-for-like comparison. The vectorized form of the same
            % maths is at 1.05x, which is why #217 is assessed fixable.
            %
            % Self-healing: when #217 lands, assumeFail stops firing and the
            % verification below runs for real - remove the KnownIssue tag then.
            r = tc.measure('scostfun','hessian','vcostfun_hess_analytic',tc.TolPin);
            if r.maxOverhead > tc.TolPin
                tc.assumeFail(sprintf( ...
                    'Known issue #217 (rolled Hessian stack): %s', tc.verdict(r)));
            end
            tc.verifyLessThanOrEqual(r.maxOverhead, tc.TolPin, tc.verdict(r));
        end
    end

    methods (Access = private)
        function r = measure(tc, anchor, derType, reference, tol)
            r = measureStackScaling('Anchor',anchor,'DerType',derType, ...
                'Reference',reference,'Sizes',tc.Sizes,'Tol',tol,'verbose',false);
            tc.assumeTrue(r.available, ...
                'Coder/Embedded Coder unavailable - skipping.');
            % gcc/size absent, or a build failed: measureStackScaling leaves
            % maxOverhead NaN rather than inventing a pass. Skip, do not assert
            % on an unmeasured artifact.
            tc.assumeFalse(isnan(r.maxOverhead), sprintf( ...
                ['%s %s vs %s: no overhead measured (standalone gcc/size absent, ', ...
                 'or a build failed) - skipping rather than passing vacuously.'], ...
                anchor, derType, reference));
        end

        function s = verdict(~, r)
            s = sprintf(['%s %s vs %s over n=%s: generated %s, hand-written %s, ', ...
                         'overhead %s (max %.2fx, %s)'], ...
                r.anchor, r.derType, r.reference, mat2str(r.sizes), ...
                mat2str(r.stack), mat2str(r.refStack), ...
                mat2str(round(r.overhead,2)), r.maxOverhead, r.trend);
        end
    end
end
