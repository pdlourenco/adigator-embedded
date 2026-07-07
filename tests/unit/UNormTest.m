classdef UNormTest < matlab.unittest.TestCase
    % UNormTest  @cada/norm overload + isnan/isinf/isfinite predicates (issue #28).
    %
    % Verifies (REQ-C-01-adjacent):
    %  - vector p-norms (2, 1, Inf, 'fro') gradients match finite differences,
    %    for column and row orientation;
    %  - the induced/spectral matrix norms (norm(A), norm(A,2/1/Inf/-Inf))
    %    raise adigator:norm:matrixNorm rather than mis-differentiating;
    %  - isnan/isinf/isfinite are derivative-free (usable in masks) and leave
    %    the surrounding derivative unchanged.

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
            rng(0);
        end
    end

    methods (Test)
        function vectorNormGradients(tc)
            n = 5;
            specs = {'2','1','Inf','''fro'''};   % literal inserted into norm(x,<spec>)
            for s = 1:numel(specs)
                spec = specs{s};
                fname = sprintf('adigator_norm_%d',s);
                writeFun(fname, sprintf('y = norm(x,%s);',spec));
                dname = [fname,'_dx'];
                ax = adigatorCreateDerivInput([n 1],'x');
                adigator(fname,{ax},dname,adigatorOptions('overwrite',1,'echo',0));
                rehash;
                for t = 1:5
                    xv = randn(n,1); xv = sign(xv).*(abs(xv)+0.5); % away from kinks
                    g_ad = adGrad(dname, xv, n);
                    g_fd = fdGrad(fname, xv, n);
                    tc.verifyLessThan(norm(g_ad-g_fd)/(1+norm(g_fd)), 1e-4, ...
                        sprintf('norm(x,%s): gradient vs FD mismatch',spec));
                end
            end
        end

        function rowVectorNorm(tc)
            n = 4;
            writeFun('adigator_norm_row','y = norm(x,2);');
            ax = adigatorCreateDerivInput([1 n],'x');
            adigator('adigator_norm_row',{ax},'adigator_norm_row_dx', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;
            xv = sign(randn(1,n)).*(abs(randn(1,n))+0.5);
            g_ad = adGrad('adigator_norm_row_dx', xv, n);
            g_fd = xv(:)/norm(xv);                 % d/dx ||x||_2 = x/||x||
            tc.verifyLessThan(norm(g_ad-g_fd)/(1+norm(g_fd)), 1e-4, ...
                'row-vector norm(x,2): gradient vs analytic mismatch');
        end

        function matrixNormErrors(tc)
            specs = {'', '2', '1', 'Inf', '-Inf'};   % '' -> norm(X) default
            for s = 1:numel(specs)
                fname = 'adigator_norm_mat';
                if isempty(specs{s})
                    writeFun(fname,'y = norm(X);','X');
                else
                    writeFun(fname,sprintf('y = norm(X,%s);',specs{s}),'X');
                end
                aX = adigatorCreateDerivInput([3 3],'X');
                gen = @() adigator(fname,{aX},[fname,'_dx'], ...
                    adigatorOptions('overwrite',1,'echo',0));
                tc.verifyTrue(raisesMatrixNorm(gen), ...
                    sprintf('matrix norm (p=%s) should raise adigator:norm:matrixNorm', ...
                    ternary(isempty(specs{s}),'default',specs{s})));
            end
        end

        function vectorizedMatrixNormErrors(tc)
            % M13: a VECTORIZED matrix ([Inf n], variable rows + n>1 fixed
            % columns) is a matrix, not a vector - the p-norm rewrite would be
            % wrong, so it must raise adigator:norm:matrixNorm. Pre-fix the
            % `any(isinf(xsize))` classifier let any Inf dim pass as a "vector",
            % bypassing the C-5 error; it then died later with a cryptic
            % "Cannot sum over vectorized dimension".
            % (p=-Inf omitted: MATLAB rejects -Inf matrix norms itself with
            % MATLAB:norm:unknownNorm before adigator's C-5 check is reached.)
            specs = {'', '2', '1', 'Inf'};
            for s = 1:numel(specs)
                fname = 'adigator_norm_vecmat';
                if isempty(specs{s})
                    writeFun(fname,'y = norm(X);','X');
                else
                    writeFun(fname,sprintf('y = norm(X,%s);',specs{s}),'X');
                end
                aX = adigatorCreateDerivInput([Inf 3],'X');   % vectorized MATRIX
                gen = @() adigator(fname,{aX},[fname,'_dx'], ...
                    adigatorOptions('overwrite',1,'echo',0));
                tc.verifyError(gen, 'adigator:norm:matrixNorm', ...
                    sprintf('vectorized matrix norm (p=%s) must raise adigator:norm:matrixNorm', ...
                    ternary(isempty(specs{s}),'default',specs{s})));
            end
            % (Real vectors [n 1]/[1 n]/scalar/empty still classify as vectors
            % and keep the p-norm rewrite - covered by vectorNormGradients,
            % rowVectorNorm and emptyNormIsNotAMatrix, which stay green with the
            % fix. A *vectorized* vector [Inf 1] is a separate unsupported case:
            % its p-norm would sum over the vectorized dimension, unrelated to
            % this matrix-vs-vector classification.)
        end

        function predicatesAreDerivativeFree(tc)
            n = 4;
            writeFun('adigator_pred','y = x.^2;\ny(isnan(x) | isinf(x) | ~isfinite(x)) = 0;');
            ax = adigatorCreateDerivInput([n 1],'x');
            adigator('adigator_pred',{ax},'adigator_pred_dx', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;
            xv = randn(n,1);
            g_ad = adGrad('adigator_pred_dx', xv, n);
            tc.verifyLessThan(norm(g_ad - 2*xv)/(1+norm(2*xv)), 1e-8, ...
                'isnan/isinf/isfinite mask changed the derivative of x.^2');
        end

        function emptyNormIsNotAMatrix(tc)
            % An empty operand (func.size == [0 0]) must NOT be treated as a
            % matrix: norm of an empty is 0, so generation must succeed (no
            % adigator:norm:matrixNorm) and the value must drop out of the
            % gradient. Here norm(x([])) == 0, so y == x(1) and dy/dx == e_1.
            n = 4;
            writeFun('adigator_norm_empty','y = x(1) + norm(x([]));');
            ax = adigatorCreateDerivInput([n 1],'x');
            adigator('adigator_norm_empty',{ax},'adigator_norm_empty_dx', ...
                adigatorOptions('overwrite',1,'echo',0));   % must not raise matrixNorm
            rehash;
            xv = randn(n,1);
            g_ad = adGrad('adigator_norm_empty_dx', xv, n);
            g_fd = fdGrad('adigator_norm_empty', xv, n);
            tc.verifyLessThan(norm(g_ad-g_fd)/(1+norm(g_fd)), 1e-4, ...
                'empty-operand norm should contribute 0 and leave the gradient unchanged');
        end
    end
end

% ============================ helpers ============================ %
function writeFun(name, body, argname)
if nargin < 3; argname = 'x'; end
fid = fopen([name,'.m'],'w');
assert(fid > 0, 'could not create %s', name);
fprintf(fid,'function y = %s(%s)\n',name,argname);
fprintf(fid,[body,'\n']);
fprintf(fid,'end\n');
fclose(fid);
rehash;
end

function g = adGrad(dname, xv, n)
xx.f = xv; xx.dx = ones(n,1);
yy = feval(dname, xx);
g = zeros(n,1);
if isfield(yy,'dx_location') && ~isempty(yy.dx_location)
    g(yy.dx_location(:,1)) = yy.dx;
else
    g(:) = yy.dx;
end
end

function g = fdGrad(fname, xv, n)
ee = 1e-6; g = zeros(n,1); f0 = feval(fname, xv);
for j = 1:n
    xp = xv; xp(j) = xp(j) + ee;
    g(j) = (feval(fname, xp) - f0)/ee;
end
end

function tf = raisesMatrixNorm(fn)
% A matrix-norm case must be rejected by a *specific* error, not merely any
% error whose message happens to contain "matrix". Accept adigator's
% contractual C-5 error, or MATLAB's own rejection of an unsupported matrix-norm
% spec (e.g. p=-Inf), which fires before adigator's check is reached.
tf = false;
try
    fn();
catch ME
    tf = any(strcmp(ME.identifier, ...
        {'adigator:norm:matrixNorm', 'MATLAB:norm:unknownNorm'}));
end
end

function out = ternary(cond, a, b)
if cond; out = a; else; out = b; end
end
