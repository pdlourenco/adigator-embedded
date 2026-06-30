classdef SCasadiOracleTest < AdigatorTestCase
    % SCasadiOracleTest  Independent-oracle check (#87): ADiGator's generated
    % derivative vs CasADi, on the SAME unmodified source m-file.
    %
    % CasADi computes derivatives by a symbolic expression graph - a method
    % wholly independent of ADiGator's source transformation - so agreement is
    % strong evidence of correctness, orthogonal to the existing oracles
    % (oracleKnownDeriv, cross-mode equality, finite differences, hand-analytic).
    % Both engines consume one source m-file (ADiGator via @cada, CasADi via SX),
    % so there is no hand-transcription gap; comparison is on reconstructed dense
    % values, so the engines' differing sparse layouts never enter.
    %
    % CasADi-gated: skips cleanly when CasADi's MATLAB interface is absent
    % (binaries are not committed; provision via CASADI_DIR - see casadiAvailable).
    % Heavyweight-ish (a generation per case) and an extended-suite test like
    % SCodegenShowcaseTest, NOT the PR gate. See ADR-0018.

    properties (Constant)
        % (function, DerType) battery - the SX-consumable showcase cases.
        % vfun is deliberately omitted: its `y = zeros(n,1); y(k) = <expr>`
        % (preallocation + indexed symbolic store) is not SX/MX-consumable
        % (verified); its math is the same as vvecfun (its vectorized sibling,
        % covered below), and its generated code is checked by the cross-mode
        % and analytic oracles. gradient-reverse shares the gradient value, so
        % this also validates reverse mode against CasADi's gradient.
        Battery = {
            'vvecfun',  'jacobian'
            'scostfun', 'gradient'
            'scostfun', 'gradient-reverse'
            'scostfun', 'hessian'
            'vcostfun', 'gradient'
            }
    end

    methods (TestClassSetup)
        function setUpCasadiOracle(tc)
            % AdigatorTestCase (base, #86) already puts root/lib/cadaUtils/util/
            % embedding on the path. Add the showcase battery's home, then gate on
            % CasADi. bench/ is added HERE, immediately before casadiAvailable() is
            % called, so there is NO ordering dependency on the base setup (a
            % separate TestClassSetup method): the skip-clean guarantee holds
            % regardless of the order MATLAB runs the hierarchy's setup methods.
            import matlab.unittest.fixtures.PathFixture
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % tests/system -> root
            tc.applyFixture(PathFixture(fullfile(root, 'bench')));
            tc.applyFixture(PathFixture(fullfile(root, 'bench', 'showcase')));
            tc.assumeTrue(casadiAvailable(), ...
                'CasADi MATLAB interface not available - skipping independent oracle (set CASADI_DIR).');
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            % generate into a throwaway folder; auto-restored at teardown.
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function adigatorMatchesCasadi(tc)
            n = 6; rng(11); xv = 0.3 + rand(n, 1);   % strictly positive: every op is well-defined
            for i = 1:size(tc.Battery, 1)
                fn = tc.Battery{i, 1};
                dt = tc.Battery{i, 2};

                % independent ground truth: the same m-file -> CasADi
                Dc = casadiDeriv(fn, dt, xv);

                % ADiGator's generated derivative, evaluated in plain MATLAB.
                % Classic mode ('c') is deliberate: it needs no MATLAB Coder
                % (unlike 'i', whose coder.const wrappers do), so this test
                % depends on CasADi alone and honors the advertised skip-clean.
                % The derivative VALUE is identical across embed modes (cross-mode
                % identity), which is all the oracle compares.
                % unroll=1: reverse mode of a rolled loop must be unrolled; the
                % value is unroll-invariant.
                opts = adigatorOptions('overwrite', 1, 'echo', 0, ...
                    'embed_mode', 'c', 'unroll', 1);
                adigatorGenDerFile_embedded(dt, fn, {adigatorCreateDerivInput([n 1], 'x')}, opts);
                % the battery regenerates same-named files into the temp folder
                % each iteration; clear the cached function + its ADiGator_* global
                % so feval picks up this iteration's file, not a stale one.
                w = SCasadiOracleTest.wrapperName(fn, dt);
                clear(w); clear('global', ['ADiGator_' w]); rehash;
                out = cell(1, abs(nargout(w)));
                [out{:}] = feval(w, xv);
                Da = full(out{1});   % C-6: the top derivative is output 1

                relErr = norm(Da(:) - Dc(:), inf) / max(1, norm(Dc(:), inf));
                tc.verifyLessThan(relErr, 1e-10, sprintf( ...
                    '%s / %s: ADiGator vs CasADi relative error %.2e (shapes %s vs %s)', ...
                    fn, dt, relErr, mat2str(size(Da)), mat2str(size(Dc))));
            end
        end
    end

    methods (Static)
        function w = wrapperName(fn, dt)
            switch dt
                case 'jacobian';         w = [fn '_Jac'];
                case 'gradient';         w = [fn '_Grd'];
                case 'hessian';          w = [fn '_Hes'];
                case 'gradient-reverse'; w = [fn '_RGrd'];
                otherwise; error('SCasadiOracleTest:DerType', 'unknown DerType %s', dt);
            end
        end
    end
end
