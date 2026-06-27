classdef SDerivShowcaseTest < matlab.unittest.TestCase
    % SDerivShowcaseTest  Guards the R17 all-axes derivative showcase harness
    % (issue #73 item B), MATLAB level. Runs derivShowcase on a small curated
    % grid and asserts (a) every cell's derivative matches the analytic reference
    % (the cross-cell correctness gate), and (b) the headline complexity
    % relationships hold: inline mode emits no .mat, and a vectorized reverse
    % gradient carries zero static data (ANALYSIS §3.5).
    %
    % Non-gating in spirit (the harness is a benchmark), but cheap enough to pin
    % here so the showcase cannot silently rot. l/i evaluation needs MATLAB
    % Coder; cells that can't evaluate report 'skip(coder)' and are not failures.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(root,'bench')));
            tc.applyFixture(PathFixture(fullfile(root,'bench','showcase')));
            tc.applyFixture(PathFixture(fullfile(root,'bench','showcase','analytic')));
        end
    end

    methods (Test)
        function showcaseRunsCorrectAndShowsTheTradeoffs(tc)
            cells = subset();
            report = derivShowcase('n',5,'cells',cells,'verbose',false);

            % (a) correctness: no cell disagreed with the analytic reference
            bad = report.rows(~[report.rows.ok]);
            tc.verifyEmpty(bad, sprintf('cells failed correctness: %s', ...
                strjoin(arrayfun(@(r) sprintf('%s/%s/%s:%s',r.fn,r.DerType,r.mode,r.note), ...
                bad, 'UniformOutput', false), ', ')));

            % (b) invariants — inline emits no .mat. This is a GENERATION
            % property (independent of evaluation), so assert it for every cell
            % that generated (matBytes >= 0), including coder-skipped ones - it
            % holds even on a no-Coder runner.
            for r = report.rows
                if strcmp(r.mode,'i') && r.matBytes >= 0
                    tc.verifyEqual(r.matBytes, 0, ...
                        sprintf('inline cell %s/%s wrote a .mat', r.fn, r.DerType));
                end
            end

            % (b) the §3.5 zero-ROM reverse: vcostfun reverse carries no data
            rev = report.rows(strcmp({report.rows.fn},'vcostfun') & ...
                              strcmp({report.rows.DerType},'gradient-reverse'));
            tc.assertNotEmpty(rev, 'expected a vcostfun reverse cell in the subset');
            tc.verifyEqual([rev.idxElems], zeros(1,numel(rev)), ...
                'vectorized reverse gradient must carry zero index data (§3.5)');
            tc.verifyEqual([rev.matBytes], zeros(1,numel(rev)), ...
                'vectorized reverse gradient must write no .mat (§3.5)');

            % the markdown table is produced
            tc.verifyTrue(contains(report.table,'| function | DerType |'), ...
                'markdown table header missing');
        end

        function analyticReferencesMatchFiniteDifference(tc)
            % The hand-coded analytical derivatives are the showcase's gold
            % correctness oracle, so they must themselves be right - check each
            % once against central finite differences (issue #73 caveat).
            x = 0.4 + (1:5)'/9;  h = 1e-6;
            checks = {
                @vcostfun, @(z) firstOut(@vcostfun_grad_analytic,z), 'vcostfun grad'
                @vvecfun,  @(z) firstOut(@vvecfun_jac_analytic,z),   'vvecfun jac'
                };
            for k = 1:size(checks,1)
                f = checks{k,1}; D = checks{k,2}; name = checks{k,3};
                Dx = D(x);
                % orient the FD Jacobian to the derivative's shape WITHOUT
                % discarding position: a scalar gradient is n x 1 while its FD
                % Jacobian is 1 x n (reshape transposes it); a true Jacobian is
                % n x n and reshapes to itself. (sort() would mask a moved
                % nonzero - per PR #79 review.)
                fd = reshape(fdJacobian(f, x, h), size(Dx));
                tc.verifyEqual(Dx, fd, 'AbsTol',1e-5,'RelTol',1e-5, ...
                    sprintf('analytical %s disagrees with finite differences', name));
            end
            % Hessian: FD of the analytical gradient
            Hfd = fdJacobian(@(z) firstOut(@vcostfun_grad_analytic,z), x, h);
            [Hana,~,~] = vcostfun_hess_analytic(x);
            tc.verifyEqual(Hana, Hfd, 'AbsTol',1e-5,'RelTol',1e-5, ...
                'analytical vcostfun Hessian disagrees with finite differences');
        end
    end
end

% ---- FD helpers ----------------------------------------------------------- %
function y = firstOut(f, x); [y,~] = f(x); end

function J = fdJacobian(f, x, h)
% central-difference Jacobian of f at x (f: R^n -> R^m, returns m x n).
n = numel(x); f0 = f(x); m = numel(f0); J = zeros(m,n);
for j = 1:n
    e = zeros(n,1); e(j) = h;
    fp = f(x+e); fm = f(x-e);
    J(:,j) = (fp(:) - fm(:)) / (2*h);
end
end

% ---- local helper --------------------------------------------------------- %
function cells = subset()
mk = @(fn,dt,m,sl,ur,dl) struct('fn',fn,'DerType',dt,'mode',m,'slim',sl,'unroll',ur,'derLevels',dl,'analytic','');
mka = @(fn,dt,ana) struct('fn',fn,'DerType',dt,'mode','ana','slim',-1,'unroll',-1,'derLevels',[],'analytic',ana);
cells = mk('scostfun','gradient','c',0,0,[]);
cells(end+1) = mk('scostfun','gradient','i',1,0,[]);
cells(end+1) = mk('scostfun','hessian','i',1,0,2);              % der_levels
cells(end+1) = mk('scostfun','gradient-reverse','i',0,1,[]);
cells(end+1) = mk('vfun','jacobian','i',1,0,[]);
cells(end+1) = mk('vcostfun','gradient','l',0,1,[]);            % forward: carries data
cells(end+1) = mk('vcostfun','gradient-reverse','l',0,1,[]);    % reverse: zero data
cells(end+1) = mka('vcostfun','gradient','vcostfun_grad_analytic'); % analytical ref
end
