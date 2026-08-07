classdef IRevGradTest < matlab.unittest.TestCase
    % IRevGradTest  Roadmap R4 acceptance test: adigatorGenRevGradFile,
    % the reverse-mode (adjoint) gradient prototype over the generated
    % forward dialect (docs/ANALYSIS.md 3.4). Gradients of scalar costs
    % with reductions are checked against analytic forms and central
    % differences; structural ops (gather with duplicates, scatter,
    % concatenation), mtimes, unrolled loops with variable reuse (the
    % snapshot machinery), and the scope guards are exercised.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function logsumexpGradient(tc)
            writeFcn('rg_lse', { ...
                'function y = rg_lse(x,w)', ...
                'y = log(sum(exp(w.*x)));', ...
                'end'});
            nx = 5;
            gx = adigatorCreateDerivInput([nx 1],'x');
            gw = adigatorCreateAuxInput([nx 1]);
            adigatorGenRevGradFile('rg_lse',{gx,gw}, ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            rng(1);
            x = randn(nx,1); w = 0.5 + rand(nx,1);
            [g,y] = rg_lse_RGrd(x,w);   % C-6: [Grd, Fun]
            tc.verifyEqual(y, log(sum(exp(w.*x))), ...
                'AbsTol', 1e-14, 'RelTol', 1e-14);
            ga = w.*exp(w.*x)/sum(exp(w.*x));
            tc.verifyEqual(g, ga, 'AbsTol', 1e-12, 'RelTol', 1e-12);
            tc.verifyEqual(g, fdgrad(@(z) rg_lse(z,w), x), ...
                'AbsTol', 1e-5, 'RelTol', 1e-5);
        end

        function repeatedIndexGatherAccumulatesAdjoints(tc)
            % #206 priority cell: GATHER WITH DUPLICATE INDICES.
            %
            % The B24 class - a construct forward mode handles without
            % comment, where reverse mode has a distinct obligation it can
            % silently fail. Forward mode ASSIGNS through an index; reverse
            % mode must ACCUMULATE, because x(1) feeding two outputs
            % contributes twice to dL/dx(1). An adjoint that assigns instead
            % of accumulating produces a gradient that is the right size, the
            % right sign, smooth, and wrong only in the duplicated entries -
            % which no smoke test and no shape check would catch.
            %
            % z = x([1 1 3]); y = sum(z.^2) => dy/dx = [4*x(1); 0; 2*x(3)].
            % The 4 is the whole point: an assigning adjoint gives 2.
            writeFcn('rg_dup', { ...
                'function y = rg_dup(x)', ...
                'z = x([1 1 3]);', ...
                'y = sum(z.^2);', ...
                'end'});
            gx = adigatorCreateDerivInput([3 1],'x');
            adigatorGenRevGradFile('rg_dup',{gx}, ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            rng(4); x = randn(3,1);
            [g,y] = rg_dup_RGrd(x);
            tc.verifyEqual(y, sum(x([1 1 3]).^2), 'AbsTol',1e-14,'RelTol',1e-14);
            ga = [4*x(1); 0; 2*x(3)];
            tc.verifyEqual(g, ga, 'AbsTol',1e-12,'RelTol',1e-12, ...
                'the duplicated index must accumulate both contributions');
            tc.verifyEqual(g, fdgrad(@rg_dup, x), 'AbsTol',1e-5,'RelTol',1e-5);
        end

        function scatterThenReduceAccumulatesAdjoints(tc)
            % #206 priority cell: SCATTER (subsasgn) into a zeroed buffer,
            % then a reduction that reads the buffer twice.
            %
            % The scatter's adjoint must gather back only the written slots,
            % and dot(z,z) reads z twice so each slot's adjoint is 2*z. Both
            % halves are places a wrong-but-plausible gradient hides: a
            % scatter adjoint that gathers the wrong slots is silently wrong
            % on a permutation, and one that drops the double-read is wrong
            % by exactly a factor of two.
            writeFcn('rg_scat', { ...
                'function y = rg_scat(x)', ...
                'z = zeros(4,1);', ...
                'z([1 3]) = x;', ...
                'y = dot(z,z);', ...
                'end'});
            gx = adigatorCreateDerivInput([2 1],'x');
            adigatorGenRevGradFile('rg_scat',{gx}, ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            rng(5); x = randn(2,1);
            [g,y] = rg_scat_RGrd(x);
            tc.verifyEqual(y, sum(x.^2), 'AbsTol',1e-14,'RelTol',1e-14);
            tc.verifyEqual(g, 2*x, 'AbsTol',1e-12,'RelTol',1e-12, ...
                'each written slot is read twice by dot(z,z)');
            tc.verifyEqual(g, fdgrad(@rg_scat, x), 'AbsTol',1e-5,'RelTol',1e-5);
        end

        function matrixDivisionIsRefusedNotMisdifferentiated(tc)
            % B24 / R30, and principle 1 in its purest form. `/` with a
            % NON-scalar denominator is mrdivide (A*inv(B)), not elementwise
            % division. The elementwise adjoint would produce a gradient of
            % plausible size and entirely wrong value - the failure mode B24
            % actually shipped. Reverse mode refuses it at generation time.
            %
            % Pinned by ERROR ID, not by message text: the id is what a caller
            % can catch, and #206 requires every `unsupported` matrix cell to
            % name the id that earns it.
            writeFcn('rg_mrd', { ...
                'function y = rg_mrd(x,A)', ...
                'y = sum(x''/A);', ...
                'end'});
            % x is 3x1 so x' is 1x3 and (1x3)/(3x3) is a WELL-FORMED
            % mrdivide - the guard must be reached on a valid expression, not
            % pre-empted by a dimension error.
            gx = adigatorCreateDerivInput([3 1],'x');
            gA = adigatorCreateAuxInput([3 3]);
            tc.verifyError(@() adigatorGenRevGradFile('rg_mrd',{gx,gA}, ...
                adigatorOptions('overwrite',1,'echo',0)), ...
                'adigator:revgrad:unsupported', ...
                'a non-scalar denominator must be refused, never approximated');
        end

        function activeExponentIsRefused(tc)
            % `.^` with a non-constant exponent has no pullback rule here. The
            % guard exists so the omission surfaces as a named error rather
            % than as a missing term in the adjoint.
            writeFcn('rg_pow', { ...
                'function y = rg_pow(x)', ...
                'y = sum(x.^x);', ...
                'end'});
            gx = adigatorCreateDerivInput([3 1],'x');
            tc.verifyError(@() adigatorGenRevGradFile('rg_pow',{gx}, ...
                adigatorOptions('overwrite',1,'echo',0)), ...
                'adigator:revgrad:unsupported');
        end

        function nonScalarOutputIsRefused(tc)
            % A reverse gradient is defined for a SCALAR objective; a vector
            % output would need one sweep per component. Refused with its own
            % id so the matrix can distinguish "no rule" from "wrong shape".
            writeFcn('rg_vec', { ...
                'function y = rg_vec(x)', ...
                'y = x.^2;', ...
                'end'});
            gx = adigatorCreateDerivInput([3 1],'x');
            tc.verifyError(@() adigatorGenRevGradFile('rg_vec',{gx}, ...
                adigatorOptions('overwrite',1,'echo',0)), ...
                'adigator:revgrad:outputs');
        end

        function leastSquaresWithMtimes(tc)
            writeFcn('rg_ls', { ...
                'function y = rg_ls(x,A,b)', ...
                'r = A*x - b;', ...
                'y = sum(r.^2) + 0.5*sum(x.^2);', ...
                'end'});
            m = 4; nx = 3;
            gx = adigatorCreateDerivInput([nx 1],'x');
            gA = adigatorCreateAuxInput([m nx]);
            gb = adigatorCreateAuxInput([m 1]);
            adigatorGenRevGradFile('rg_ls',{gx,gA,gb}, ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            rng(2);
            x = randn(nx,1); A = randn(m,nx); b = randn(m,1);
            [g,y] = rg_ls_RGrd(x,A,b);   % C-6: [Grd, Fun]
            r = A*x - b;
            tc.verifyEqual(y, sum(r.^2) + 0.5*sum(x.^2), ...
                'AbsTol', 1e-13, 'RelTol', 1e-13);
            tc.verifyEqual(g, 2*A.'*r + x, 'AbsTol', 1e-12, 'RelTol', 1e-12);
        end

        function structuralOpsAndDuplicates(tc)
            % scatter, gather with duplicate indices, and concatenation
            writeFcn('rg_struct', { ...
                'function y = rg_struct(x,c)', ...
                'v = zeros(4,1);', ...
                'v(1:2:3) = x(1:2);', ...
                'v(2:2:4) = c.*x([1;1]);', ...
                'u = [v; x(3)*v(1:2)];', ...
                'y = sum(u.^2);', ...
                'end'});
            nx = 3;
            gx = adigatorCreateDerivInput([nx 1],'x');
            gc = adigatorCreateAuxInput([2 1]);
            adigatorGenRevGradFile('rg_struct',{gx,gc}, ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            rng(3);
            x = randn(nx,1); cc = 0.5 + rand(2,1);
            [g,y] = rg_struct_RGrd(x,cc);   % C-6: [Grd, Fun]
            tc.verifyEqual(y, rg_struct(x,cc), 'AbsTol', 1e-13, 'RelTol', 1e-13);
            tc.verifyEqual(g, fdgrad(@(z) rg_struct(z,cc), x), ...
                'AbsTol', 1e-5, 'RelTol', 1e-5);
        end

        function unrolledLoopWithVariableReuse(tc)
            % the accumulator s is overwritten every (unrolled) iteration
            % and each product needs the PRE-overwrite value: pins the
            % forward-value snapshot machinery
            writeFcn('rg_prod', { ...
                'function y = rg_prod(x)', ...
                's = 1;', ...
                'for i = 1:4', ...
                '  s = s*x(i);', ...
                'end', ...
                'y = s + sum(x);', ...
                'end'});
            nx = 4;
            gx = adigatorCreateDerivInput([nx 1],'x');
            adigatorGenRevGradFile('rg_prod',{gx}, ...
                adigatorOptions('overwrite',1,'echo',0,'unroll',1));
            rehash;

            rng(4);
            x = 0.5 + rand(nx,1);
            [g,y] = rg_prod_RGrd(x);   % C-6: [Grd, Fun]
            tc.verifyEqual(y, prod(x) + sum(x), 'AbsTol', 1e-13, 'RelTol', 1e-13);
            tc.verifyEqual(g, prod(x)./x + 1, 'AbsTol', 1e-12, 'RelTol', 1e-12);
        end

        function scopeGuards(tc)
            gx = @() adigatorCreateDerivInput([3 1],'x');

            % two derivative inputs are rejected
            writeFcn('rg_two', { ...
                'function y = rg_two(x,z)', ...
                'y = sum(x) + sum(z);', ...
                'end'});
            gz = adigatorCreateDerivInput([3 1],'z');
            tc.verifyError(@() adigatorGenRevGradFile('rg_two',{gx(),gz}, ...
                adigatorOptions('overwrite',1,'echo',0)), ...
                'adigator:revgrad:inputs');

            % vector outputs are rejected
            writeFcn('rg_vec', { ...
                'function y = rg_vec(x)', ...
                'y = x.^2;', ...
                'end'});
            tc.verifyError(@() adigatorGenRevGradFile('rg_vec',{gx()}, ...
                adigatorOptions('overwrite',1,'echo',0)), ...
                'adigator:revgrad:outputs');

            % rolled loops in the generated file are rejected with advice
            writeFcn('rg_loop', { ...
                'function y = rg_loop(x)', ...
                'y = 0;', ...
                'for i = 1:3', ...
                '  y = y + x(i)^2;', ...
                'end', ...
                'end'});
            tc.verifyError(@() adigatorGenRevGradFile('rg_loop',{gx()}, ...
                adigatorOptions('overwrite',1,'echo',0)), ...
                'adigator:fwdtape:controlflow');

            % nonsmooth/unsupported active operations are rejected
            writeFcn('rg_abs', { ...
                'function y = rg_abs(x)', ...
                'y = sum(abs(x));', ...
                'end'});
            tc.verifyError(@() adigatorGenRevGradFile('rg_abs',{gx()}, ...
                adigatorOptions('overwrite',1,'echo',0)), ...
                'adigator:revgrad:unsupported');

            % B24: a genuine matrix division A/B (non-scalar denominator) on the
            % active path is rejected -- the elementwise ./ adjoint would give a
            % silently wrong gradient. The matrix adjoint is future work (#128).
            writeFcn('rg_mdiv', { ...
                'function y = rg_mdiv(x)', ...
                'B = [2 0.5 0; 1 3 0.2; 0 1 2];', ...   % 3x3, matches the [3 1] x
                'r = x.'' / B;', ...                     % [1 3] / [3 3] -> mrdivide
                'y = sum(r.^2);', ...
                'end'});
            tc.verifyError(@() adigatorGenRevGradFile('rg_mdiv',{gx()}, ...
                adigatorOptions('overwrite',1,'echo',0)), ...
                'adigator:revgrad:unsupported', ...
                'matrix division A/B must be rejected in reverse mode (B24)');
        end

        function scalarDivisionStillWorks(tc)
            % B24 guard must NOT fire for a scalar denominator: '/' by a scalar
            % (and './') is elementwise, and its reverse gradient matches FD.
            gx = @() adigatorCreateDerivInput([2 1],'x');
            writeFcn('rg_sdiv', { ...
                'function y = rg_sdiv(x)', ...
                'y = sum(exp(x)) / (1 + sum(x.^2));', ...
                'end'});
            adigatorGenRevGradFile('rg_sdiv',{gx()}, ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;
            xv = [0.3; -0.7];
            g_ad = rg_sdiv_RGrd(xv);
            f = @(v) sum(exp(v)) / (1 + sum(v.^2));
            g_fd = fdgrad(f, xv);
            tc.verifyEqual(g_ad(:), g_fd(:), 'AbsTol', 1e-6, 'RelTol', 1e-6, ...
                'scalar-denominator division reverse gradient must match FD');
        end

        function overwriteGuardIsFailFast(tc)
            % M6 (#121): the overwrite guard must fire BEFORE the (expensive)
            % forward generation, so an overwrite=0 collision costs nothing and
            % leaves no forward intermediate (<UserFun>_ADiGatorRGrdFwd.*)
            % behind. Pre-fix the guard ran only after the whole reverse file
            % had been built, littering the forward .m/.mat on the error path.
            writeFcn('rg_ff', {'function y = rg_ff(x)','y = sum(x.^2);','end'});
            % a pre-existing output file the generator must refuse to clobber
            writeFcn('rg_ff_RGrd', {'function y = rg_ff_RGrd(x)','y = x;','end'});
            gx = adigatorCreateDerivInput([3 1],'x');
            tc.verifyError(@() adigatorGenRevGradFile('rg_ff',{gx}, ...
                adigatorOptions('overwrite',0,'echo',0)), ...
                'adigator:revgrad:overwrite', ...
                'an existing output with overwrite=0 must raise the overwrite error');
            tc.verifyNotEqual(exist('rg_ff_ADiGatorRGrdFwd.m','file'), 2, ...
                'the guard must fire before forward generation (no _RGrdFwd.m left)');
            tc.verifyNotEqual(exist('rg_ff_ADiGatorRGrdFwd.mat','file'), 2, ...
                'the guard must fire before forward generation (no _RGrdFwd.mat left)');
        end

        function forwardIntermediateIsCleanedUp(tc)
            % M6 (#121): after a SUCCESSFUL generation the forward throwaway
            % intermediate (<UserFun>_ADiGatorRGrdFwd.m/.mat) is removed on
            % return (onCleanup), leaving only the reverse file.
            writeFcn('rg_cl', {'function y = rg_cl(x)','y = sum(exp(x));','end'});
            gx = adigatorCreateDerivInput([3 1],'x');
            adigatorGenRevGradFile('rg_cl',{gx}, ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;
            tc.verifyEqual(exist('rg_cl_RGrd.m','file'), 2, ...
                'the reverse file must exist after a successful generation');
            tc.verifyNotEqual(exist('rg_cl_ADiGatorRGrdFwd.m','file'), 2, ...
                'the forward intermediate .m must be cleaned up after success');
            tc.verifyNotEqual(exist('rg_cl_ADiGatorRGrdFwd.mat','file'), 2, ...
                'the forward intermediate .mat must be cleaned up after success');
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

function g = fdgrad(f, x)
% central finite differences
ee = 1e-6;
g = zeros(numel(x),1);
for i = 1:numel(x)
    e = zeros(size(x)); e(i) = ee;
    g(i) = (f(x+e) - f(x-e))/(2*ee);
end
end
