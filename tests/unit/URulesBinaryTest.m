classdef URulesBinaryTest < matlab.unittest.TestCase
    % URulesBinaryTest  Finite-difference check of the binary derivative rules.
    %
    % CI plan: TS-U-02, verifies REQ-C-02. Companion to URulesUnaryTest (the
    % unary rules): each fixture applies one binary operator (plus, minus,
    % times/.*, rdivide/./, power/.^ with an inactive exponent, mtimes/*, and
    % mod/rem under every activity pattern) with the variable of
    % differentiation against a constant of a chosen shape and against itself,
    % spanning the operand-shape combinations {scalar, col, matrix} that drive
    % the broadcasting / reduction in the adjoint. Outputs
    % are kept non-scalar so the raw generated-file derivative (DESIGN C-2) is
    % the plain [numel(y) x numel(x)] unrolled Jacobian; it is reconstructed
    % from y.dX / y.dX_location / y.dX_size and checked against dense finite
    % differences.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
            tc.applyFixture(PathFixture(fullfile(root,'tests','helpers')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
            rng(11);
        end
    end

    methods (Test)
        % ---- plus / minus (broadcasting shapes) ----
        function plusColumnConstant(tc)
            checkBinaryRule(tc, 'plus_col', 'y = x + [1;2;3];', [3 1]);
        end
        function plusScalarConstant(tc)
            checkBinaryRule(tc, 'plus_scalar', 'y = x + 2;', [3 1]);
        end
        function minusConstantFirst(tc)
            checkBinaryRule(tc, 'minus_cf', 'y = [10;20;30] - x;', [3 1]);
        end

        % ---- times (.*), incl. self and column-x-row broadcast ----
        function timesColumnConstant(tc)
            checkBinaryRule(tc, 'times_col', 'y = [2;3;4] .* x;', [3 1]);
        end
        function timesScalarConstant(tc)
            checkBinaryRule(tc, 'times_scalar', 'y = 5 .* x;', [3 1]);
        end
        function timesSelf(tc)
            checkBinaryRule(tc, 'times_xx', 'y = x .* x;', [3 1]);
        end

        % ---- rdivide (./) with active numerator, denominator, and both ----
        function rdivideActiveNumerator(tc)
            checkBinaryRule(tc, 'rdiv_num', 'y = x ./ [2;4;8];', [3 1]);
        end
        function rdivideActiveDenominator(tc)
            checkBinaryRule(tc, 'rdiv_den', 'y = [6;6;6] ./ x;', [3 1]);
        end
        function rdivideActiveBoth(tc)
            checkBinaryRule(tc, 'rdiv_both', 'y = x ./ (1 + x.^2);', [3 1]);
        end

        % ---- power (.^) with an inactive exponent ----
        function powerIntegerExponent(tc)
            checkBinaryRule(tc, 'pow_int', 'y = x .^ 3;', [3 1]);
        end
        function powerColumnExponent(tc)
            checkBinaryRule(tc, 'pow_col', 'y = x .^ [2;3;2];', [3 1]);
        end

        % ---- mtimes (*): const matrix * x, and outer product x * row ----
        function mtimesConstMatrix(tc)
            checkBinaryRule(tc, 'mtimes_A', 'y = [1 2 3; 4 5 6] * x;', [3 1]);
        end

        % ---- scalar variable of differentiation ----
        function scalarVariable(tc)
            checkBinaryRule(tc, 'scalar_vod', 'y = [x^2; 3*x; x/2];', [1 1]);
        end

        % ---- mod / rem: every activity pattern x {scalar, vector} divisor ----
        % A fixed point keeps every x./y at least 0.04 from an integer, so the
        % floor/fix steps are far outside the FD stencil. The signed numerators
        % make mod (floor) and rem (fix) differ. #252: the scalar-divisor arms
        % applied dZ/dY only where y == 0; #251: the divisor-only arm printed
        % dZ/dY without its operands, an unparsable file.
        function modRemActiveBoth(tc)
            for op = ["mod" "rem"]
                checkBinaryRule(tc, op + "_both_s", ...
                    "y = " + op + "([-5;5;-5].*x, x(1)+0.25);", [3 1], tc.ModX);
                checkBinaryRule(tc, op + "_both_v", ...
                    "y = " + op + "([-5;5;-5].*x, 1.7+x);", [3 1], tc.ModX);
            end
        end
        function modRemActiveDivisorOnly(tc)
            for op = ["mod" "rem"]
                checkBinaryRule(tc, op + "_y_s", ...
                    "y = " + op + "([7.3;-8.2;9.7], x(1));", [3 1], tc.ModX);
                checkBinaryRule(tc, op + "_y_v", ...
                    "y = " + op + "(7.3, x);", [3 1], tc.ModX);
            end
        end
        function modRemActiveDividendOnly(tc)
            for op = ["mod" "rem"]
                checkBinaryRule(tc, op + "_x_s", ...
                    "y = " + op + "([-5;5;-5].*x, 1.7);", [3 1], tc.ModX);
            end
        end
        function modScalarDivisorAtZeroHasZeroDerivative(tc)
            % The y == 0 guard's other direction: at a zero scalar divisor the
            % dZ/dY term is zero (as in the vector arm), never -floor(x/0).
            name = 'urb_mod_y0';
            writeFixture(name, 'y = mod([7.3;-8.2;9.7], x(1));');
            adigator(name, {adigatorCreateDerivInput([3 1],'x')}, [name,'_dx'], ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;
            yy = feval([name,'_dx'], struct('f',[0;1.3;0.7],'dx',ones(3,1)));
            tc.verifyEqual(yy.f, [7.3;-8.2;9.7]);
            tc.verifyEqual(reconstructUnrolled(yy,3,3), zeros(3), ...
                'mod at a zero scalar divisor must carry a zero derivative');
        end
    end

    properties (Constant)
        ModX = [0.9; 1.3; 0.7]
    end
end

%% ============================ helpers ================================ %%
function checkBinaryRule(tc, name, body, xsize, xv)
% Generate y = f(x), evaluate the raw generated file with the identity seed,
% reconstruct the unrolled derivative from the C-2 fields, and check it against
% a dense finite-difference Jacobian. Fixtures keep y non-scalar so dx_size is
% [numel(y) numel(x)]. xv (optional) fixes the evaluation point, for rules
% with steps; by default it is drawn in [0.5, 1.5].
name = char(name); body = char(body);
fname = ['urb_', name];
writeFixture(fname, body);
dname = [fname, '_dx'];
ax = adigatorCreateDerivInput(xsize, 'x');
adigator(fname, {ax}, dname, adigatorOptions('overwrite',1,'echo',0));
rehash;

n = prod(xsize);
if nargin < 5
    xv = 0.5 + rand(xsize);           % away from 0 (safe for ./ and .^ and FD)
end
xx.f = xv; xx.dx = ones(n,1);         % identity seed
yy = feval(dname, xx);

yval = feval(fname, xv);
m = numel(yval);

D = reconstructUnrolled(yy, m, n);
Jfd = fdcheck('jac', @(z) feval(fname, z), xv);
tc.verifyEqual(D, Jfd, 'AbsTol', 1e-5, 'RelTol', 1e-5, ...
    sprintf('%s: reconstructed derivative disagrees with finite differences', name));
end

function writeFixture(name, body)
if ischar(body) || isstring(body); body = {char(body)}; end
fid = fopen([name,'.m'], 'w');
assert(fid > 0, 'could not create fixture %s', name);
fprintf(fid, 'function y = %s(x)\n', name);
fprintf(fid, '%s\n', body{:});
fprintf(fid, 'end\n');
fclose(fid);
rehash;
end
