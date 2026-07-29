classdef IZeroHessianTest < matlab.unittest.TestCase
    % IZeroHessianTest  B32 regression: adigatorGenHesFile must generate a
    % correct all-zero Hessian for a structurally-zero (locally-linear-
    % objective) case, not crash. Found by the #38 Phase C expression-tree
    % fuzzer (mcGenExprTree): the Hessian of y = x(k) reached
    % adigatorGenHesFile:446 (HesLocs1 = dydxlocs(dydxdxlocs(:,1),:)) with an
    % empty (0x0) dydxdxlocs and threw "Index in position 2 exceeds array
    % bounds" (the crash line is `HesLocs1 = dydxlocs(dydxdxlocs(:,1),:)`), and
    % the value emission then referenced a nonexistent runtime
    % <deriv>dxdx_location field. The fix normalizes the empty second-derivative
    % locations to 0x2 (so the CSC pattern builds) and short-circuits the value
    % emission to a literal zeros(...) (so nothing scatters from an absent
    % field). See docs/analyses/ANALYSIS.md B32.

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
        function classicLinearObjectiveHessianIsZero(tc)
            % A locally-linear scalar objective has an all-zero Hessian; classic
            % generation must produce it (was: crash), the wrapper must run and
            % return zeros(n,n), and the emitted file must use the literal-zero
            % short-circuit (no _location scatter).
            cases = { 'zh_s', 'y = 2.*x(1);',               1; ...   % n==1 scalar-of-scalar
                      'zh_a', 'y = x(2);',                  2; ...
                      'zh_b', 'y = sum(x);',                3; ...
                      'zh_c', 'y = 2.*x(1) - x(3) + x(4);', 4 };
            for k = 1:size(cases,1)
                nm = cases{k,1}; body = cases{k,2}; n = cases{k,3};
                writeFcn(nm, {sprintf('function y = %s(x)', nm), body, 'end'});
                gx = adigatorCreateDerivInput([n 1], 'x');
                adigatorGenHesFile(nm, {gx}, struct('overwrite',1,'echo',0));

                [H, G, F] = feval([nm '_Hes'], 0.7*ones(n,1));
                tc.verifyEqual(size(H), [n n], sprintf('%s: Hessian must be n x n', nm));
                tc.verifyLessThan(max(abs(full(H(:)))), 1e-12, ...
                    sprintf('%s: a linear objective must have an all-zero Hessian', nm));
                tc.verifyEqual(numel(F), 1, sprintf('%s: scalar objective expected', nm));
                % the companion gradient must survive the Hessian short-circuit:
                % a linear objective has a constant, nonzero gradient.
                tc.verifyTrue(all(isfinite(G(:))) && any(G(:) ~= 0), ...
                    sprintf('%s: the gradient must still be emitted (nonzero for a linear objective)', nm));

                src = fileread([nm '_Hes.m']);
                tc.verifyTrue(contains(src, 'Hes = zeros'), ...
                    sprintf('%s: zero-Hessian file must emit a literal zeros(...)', nm));
                % The Hessian must NOT scatter from the second-derivative
                % location field (dxdx_location) — that field is absent from the
                % runtime struct for a zero Hessian and was the crash symptom.
                % (The gradient's own dx_location scatter is fine and expected.)
                tc.verifyFalse(contains(src, 'dxdx_location'), ...
                    sprintf('%s: zero-Hessian file must not scatter from dxdx_location', nm));
            end
        end

        function nonZeroHessianUnaffected(tc)
            % The B32 short-circuit must not perturb the normal (nonzero) path.
            writeFcn('zh_mix', {'function y = zh_mix(x)', 'y = x(1).^2 + 3.*x(2);', 'end'});
            adigatorGenHesFile('zh_mix', {adigatorCreateDerivInput([2 1],'x')}, ...
                struct('overwrite',1,'echo',0));
            Hmix = full(zh_mix_Hes([0.4; 0.9]));
            tc.verifyLessThan(max(abs(Hmix(:) - reshape([2 0; 0 0], [], 1))), 1e-12, ...
                'mixed quadratic+linear Hessian is wrong');

            writeFcn('zh_q', {'function y = zh_q(x)', 'y = x.'' * x;', 'end'});
            adigatorGenHesFile('zh_q', {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('overwrite',1,'echo',0));
            Hq = full(zh_q_Hes([0.2; -0.5; 0.8]));
            tc.verifyLessThan(max(abs(Hq(:) - reshape(2*eye(3), [], 1))), 1e-12, ...
                'quadratic dot v.''*v Hessian is wrong (should be 2*I)');
        end

        function vectorOutputLinearHessianIsZero(tc)
            % A linear VECTOR function (m>1, n>1) has an all-zero [m*n x n]
            % Hessian — exercises the else -> zeros(m*n,n) fold of the B32 guard
            % (the scalar cases above only cover n==1 -> ysize and m==1).
            writeFcn('zh_vec', {'function y = zh_vec(x)', ...
                'y = [x(1) + x(2); x(2) - x(3)];', 'end'});
            adigatorGenHesFile('zh_vec', {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('overwrite',1,'echo',0));
            H = full(zh_vec_Hes(0.5*ones(3,1)));
            tc.verifyEqual(size(H), [6 3], 'vector-output Hessian must be [m*n x n]');
            tc.verifyLessThan(max(abs(H(:))), 1e-12, ...
                'a linear vector function must have an all-zero Hessian');
        end

        function cscZeroHessianMode(tc)
            % der_output='csc' on a zero Hessian: an empty value stream and a
            % HessianCSC pattern with Nnz==0 (the empty-pattern path through
            % adigatorBuildCSC).
            writeFcn('zh_csc', {'function y = zh_csc(x)', 'y = sum(x);', 'end'});
            out = adigatorGenHesFile('zh_csc', {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('overwrite',1,'echo',0,'der_output','csc'));
            vals = zh_csc_Hes(0.5*ones(3,1));
            tc.verifyEmpty(vals, 'csc zero-Hessian value stream must be empty');
            tc.verifyEqual(out.HessianCSC.Nnz, 0, ...
                'HessianCSC.Nnz must be 0 for a structurally-zero Hessian');
        end

        function embedZeroHessianGeneratesAndRuns(tc)
            % The embed value-emission branch (the embed literal-scatter) indexes
            % the same dydxdxlocs, so it must also survive a zero Hessian. Pin
            % generation for both embed modes, and RUN the inline ('i') file —
            % which is self-contained — to confirm it evaluates to zeros(n,n).
            for mode = {'i','l'}
                nm = ['zh_em_' mode{1}];
                writeFcn(nm, {sprintf('function y = %s(x)', nm), 'y = sum(x);', 'end'});
                adigatorGenHesFile(nm, {adigatorCreateDerivInput([3 1],'x')}, ...
                    struct('overwrite',1,'echo',0,'embed_mode',mode{1}));
                tc.verifyTrue(isfile([nm '_Hes.m']), ...
                    sprintf('embed_mode=%s zero-Hessian file was not generated', mode{1}));
            end
            rehash;
            Hi = full(zh_em_i_Hes(0.5*ones(3,1)));
            tc.verifyEqual(size(Hi), [3 3], 'inline embed zero-Hessian shape must be n x n');
            tc.verifyLessThan(max(abs(Hi(:))), 1e-12, ...
                'inline embed zero Hessian must run to all zeros');
        end
    end
end

function writeFcn(name, lines)
% write a fixture function file into the (temporary) working folder
fid = fopen([name '.m'], 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end
