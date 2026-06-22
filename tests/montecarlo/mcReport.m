function mcReport(report, reportPath)
%MCREPORT  Print (and optionally save) a Monte-Carlo campaign summary.
%
%   mcReport(report)            prints to the command window.
%   mcReport(report, path)      also writes the same text to a file.
%
% `report` is the struct returned by mcCampaign.
L = {};
L{end+1} = sprintf('Monte-Carlo V&V campaign (issue #38, ADR-0007)');
L{end+1} = sprintf('  MATLAB %s | seed %d | iterations %d', ...
    report.matlabRelease, report.seed, report.nIters);
L{end+1} = sprintf('  cases passed: %d   failed: %d', report.nPass, report.nFail);

if isfield(report,'oracleStats') && ~isempty(fieldnames(report.oracleStats))
    L{end+1} = '  per-oracle (pass/fail/skip):';
    fn = fieldnames(report.oracleStats);
    for i = 1:numel(fn)
        s = report.oracleStats.(fn{i});
        L{end+1} = sprintf('    %-18s %d / %d / %d', fn{i}, s.pass, s.fail, s.skip); %#ok<AGROW>
    end
end

if ~isempty(report.failures)
    L{end+1} = sprintf('  failing seeds (%d):', numel(report.failures));
    for i = 1:numel(report.failures)
        f = report.failures(i);
        L{end+1} = sprintf('    seed %d  [%s]  %s', f.seed, f.gen, f.message); %#ok<AGROW>
    end
    if isfield(report,'promoted') && ~isempty(report.promoted)
        L{end+1} = sprintf('  promoted %d reproducer(s) to tests/montecarlo/regressions/', ...
            numel(report.promoted));
    end
else
    L{end+1} = '  no failures.';
end

txt = strjoin(L, newline);
disp(txt);
if nargin >= 2 && ~isempty(reportPath)
    fid = fopen(reportPath, 'w');
    if fid > 0
        closer = onCleanup(@() fclose(fid));
        fprintf(fid, '%s\n', txt);
    end
end
end
