function fpath = mcPromote(c, seed, results, regDir)
%MCPROMOTE  Write a failing case as a deterministic regression reproducer.
%
% This is the mechanism that turns a non-deterministic campaign finding into
% permanent, gated coverage (ADR-0007): each failure is serialized as a
% standalone `mcreg_*.m` data function under tests/montecarlo/regressions/,
% which MCRegressionTest discovers and re-checks deterministically.
%
%   fpath = mcPromote(c, seed, results, regDir)
%
% c       - the (ideally shrunk) failing case.
% seed    - the per-iteration RNG seed that produced it (reproducibility).
% results - the 1xN oracle result struct array (for the failure note).
% regDir  - target folder; defaults to tests/montecarlo/regressions.
if nargin < 4 || isempty(regDir)
    regDir = fullfile(fileparts(mfilename('fullpath')), 'regressions');
end
if ~isfolder(regDir); mkdir(regDir); end

fname = sprintf('mcreg_seed%d_%s', seed, c.name);
fname = regexprep(fname, '[^A-Za-z0-9_]', '_');
fpath = fullfile(regDir, [fname '.m']);

% Freeze the closed-form expected derivative at x0 when one exists, so a
% value-correctness regression is guarded by a golden number (not a handle).
expected = []; expectedKind = '';
if strcmp(c.deriv,'hessian') && ~isempty(c.exactHess)
    expected = c.exactHess(c.x0); expectedKind = 'hessian';
elseif ~strcmp(c.deriv,'hessian') && ~isempty(c.exactJac)
    expected = c.exactJac(c.x0); expectedKind = c.deriv;
end

msgs = strtrim(strjoin(arrayfun(@(r) ...
    sprintf('%s:%s', r.name, ternary(r.pass,'ok',r.message)), ...
    results(:).', 'UniformOutput', false), ' | '));

fid = fopen(fpath, 'w');
assert(fid > 0, 'mcPromote:open', 'cannot write %s', fpath);
closer = onCleanup(@() fclose(fid));
fprintf(fid, 'function r = %s()\n', fname);
fprintf(fid, '%% Auto-generated Monte-Carlo regression reproducer (issue #38, ADR-0007).\n');
fprintf(fid, '%% Promoted from seed %d on %s.\n', seed, datestr(now,'yyyy-mm-dd'));
fprintf(fid, '%% Failure: %s\n', msgs);
fprintf(fid, 'r.name  = %s;\n', q(c.name));
fprintf(fid, 'r.body  = %s;\n', cellstr2src(c.body));
fprintf(fid, 'r.xsize = %s;\n', mat2str(c.xsize));
fprintf(fid, 'r.deriv = %s;\n', q(c.deriv));
fprintf(fid, 'r.x0    = %s;\n', mat2str(c.x0, 17));
fprintf(fid, 'r.seed  = %d;\n', seed);
if ~isempty(expected)
    fprintf(fid, 'r.expected     = %s;\n', mat2str(expected, 17));
    fprintf(fid, 'r.expectedKind = %s;\n', q(expectedKind));
end
fprintf(fid, 'end\n');
clear closer
rehash;
end

function s = q(str)
s = ['''' strrep(char(str), '''', '''''') ''''];
end

function s = cellstr2src(b)
if ischar(b) || isstring(b); b = cellstr(b); end
parts = cellfun(@q, b(:).', 'UniformOutput', false);
s = ['{' strjoin(parts, ', ') '}'];
end

function v = ternary(cond, a, b)
if cond; v = a; else; v = b; end
end
