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
tf = false;
try
    fn();
catch ME
    tf = strcmp(ME.identifier,'adigator:norm:matrixNorm') || ...
         contains(lower(ME.message),'matrix');
end
end

function out = ternary(cond, a, b)
if cond; out = a; else; out = b; end
end
