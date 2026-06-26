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

            % (b) invariants — inline emits no .mat
            for r = report.rows
                if strcmp(r.mode,'i') && ~startsWith(r.note,'skip')
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
    end
end

% ---- local helper --------------------------------------------------------- %
function cells = subset()
mk = @(fn,dt,m,sl,ur,dl) struct('fn',fn,'DerType',dt,'mode',m,'slim',sl,'unroll',ur,'derLevels',dl);
cells = mk('scostfun','gradient','c',0,0,[]);
cells(end+1) = mk('scostfun','gradient','i',1,0,[]);
cells(end+1) = mk('scostfun','hessian','i',1,0,2);              % der_levels
cells(end+1) = mk('scostfun','gradient-reverse','i',0,1,[]);
cells(end+1) = mk('vfun','jacobian','i',1,0,[]);
cells(end+1) = mk('vcostfun','gradient','l',0,1,[]);            % forward: carries data
cells(end+1) = mk('vcostfun','gradient-reverse','l',0,1,[]);    % reverse: zero data
end
