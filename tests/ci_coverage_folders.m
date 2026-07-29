function ci_coverage_folders(mode)
%CI_COVERAGE_FOLDERS  Per-folder full-suite coverage floor (V&V gate).
%
% The V&V-for-release coverage floor. Unlike ci_coverage.m (the fast PR-gate
% ratchet: unit+integration, single aggregate number over lib/util/embedding),
% this runs the FULL deterministic suite (unit + integration + system +
% montecarlo) and enforces a *per-folder* no-regression ratchet, so a drop in
% one folder can never be masked by a rise in another.
%
% The folders are bucketed to separate the derivative-correctness path from
% the downstream emitter (see docs/decisions/ADR-0032 and the reasoning in
% docs/CI_PLAN.md §Coverage floor):
%
%   lib/@cada        per-operation forward/reverse derivative rules  <- correctness
%   lib/@cadastruct  struct / remap / union layer                    <- correctness
%   lib/cadaUtils    shared derivative utilities                     <- correctness
%   lib              source-transformation orchestration (top-level) <- correctness
%   util             host-side generators & helpers (CSC, loopbound) <- fork
%   embedding        embed-mode emitter (serialises an already-       <- fork
%                    computed derivative object)
%
% A wrong derivative originates in the @cada / @cadastruct rules, not in the
% emitter; the buckets keep that path visible. The floor here is a *ratchet*
% (nothing may drop) — the correctness-path targets are RAISED as the #38 /
% #103 oracle campaigns land tests. Coverage alone is necessary, not
% sufficient: a covered line can still return a wrong value, which is why the
% floor is paired with those value oracles.
%
% Usage:
%   ci_coverage_folders          measure + ratchet against the baseline
%   ci_coverage_folders('write') measure + (over)write the baseline file
%
% Determinism: montecarlo is included but every MCSmokeTest campaign fixes its
% seed and nIters (see tests/montecarlo/MCSmokeTest.m), so coverage is
% reproducible within a MATLAB release. The baseline is authoritative for the
% release the Extended job runs (`latest`); TOL absorbs cross-release jitter.

if nargin < 1; mode = 'check'; end
mode = validatestring(mode, {'check','write'});

TOL = 0.01;   % per-bucket tolerance (post-merge job; absorbs release/RNG jitter)

thisDir = fileparts(mfilename('fullpath'));
root    = fileparts(thisDir);

import matlab.unittest.TestRunner
import matlab.unittest.plugins.CodeCoveragePlugin
import matlab.unittest.plugins.codecoverage.CoberturaFormat

suite = [testsuite(fullfile(thisDir,'unit')), ...
         testsuite(fullfile(thisDir,'integration')), ...
         testsuite(fullfile(thisDir,'system')), ...
         testsuite(fullfile(thisDir,'montecarlo'))];

resdir = fullfile(root,'results');
if ~isfolder(resdir); mkdir(resdir); end
covfile = fullfile(resdir,'coverage_folders.xml');

runner = TestRunner.withTextOutput;
runner.addPlugin(CodeCoveragePlugin.forFolder( ...
    {fullfile(root,'lib'), fullfile(root,'util'), fullfile(root,'embedding')}, ...
    'IncludingSubfolders', true, 'Producing', CoberturaFormat(covfile)));
runner.run(suite);

measured = bucketCoverage(covfile, root);

basefile = fullfile(thisDir,'coverage_baseline_folders.txt');

if strcmp(mode,'write')
    writeBaseline(basefile, measured);
    fprintf('ci_coverage_folders: wrote baseline %s\n', basefile);
    printTable(measured, []);
    return
end

if ~isfile(basefile)
    error('ci_coverage_folders:noBaseline', ...
        'no baseline (%s); run ci_coverage_folders(''write'') to create it.', ...
        basefile);
end
base = readBaseline(basefile);

printTable(measured, base);

% Ratchet: every baselined bucket must hold within TOL. A new (unbaselined)
% bucket is reported but not gated — regen the baseline to adopt it.
names = fieldnames(base);
regressed = {};
for i = 1:numel(names)
    b = names{i};
    if ~isfield(measured, b)
        error('ci_coverage_folders:missingBucket', ...
            'baselined bucket %s produced no coverage data', bucketLabel(b));
    end
    if measured.(b).rate < base.(b) - TOL
        regressed{end+1} = sprintf('%s %.4f < %.4f', ...
            bucketLabel(b), measured.(b).rate, base.(b)); %#ok<AGROW>
    end
end

if ~isempty(regressed)
    error('ci_coverage_folders:regression', ...
        'per-folder coverage regressed:\n  %s', strjoin(regressed, sprintf('\n  ')));
end
fprintf('ci_coverage_folders: all %d folders hold their floor (tol %.3f).\n', ...
    numel(names), TOL);
end

% ------------------------------------------------------------------------
function cov = bucketCoverage(covfile, root)
% Parse the Cobertura XML and aggregate covered/total lines into the 6
% buckets. Returns a struct keyed by canonical bucket id, each with fields
% .cov .tot .rate. `root` is the repo root, used to relativize filenames so
% bucketing does not depend on whether MATLAB emitted repo-relative or
% absolute Cobertura paths (or on the caller's cwd).
doc = xmlread(covfile);
classes = doc.getElementsByTagName('class');
acc = containers.Map('KeyType','char','ValueType','any');
for c = 0:classes.getLength-1
    cls = classes.item(c);
    fn = char(cls.getAttribute('filename'));
    key = bucketOf(fn, root);
    if isempty(key); continue; end
    % Count only the class-level <lines>'s direct <line> children. Scoping to
    % the direct child (not a getElementsByTagName('line') descendant query)
    % keeps the count correct even if a future MATLAB release populated
    % method-nested <lines> (which would otherwise be double-counted).
    linesEl = directChild(cls, 'lines');
    if isempty(linesEl); continue; end
    lineNodes = linesEl.getChildNodes;
    tot = 0; covered = 0;
    for l = 0:lineNodes.getLength-1
        ln = lineNodes.item(l);
        if ~strcmp(char(ln.getNodeName), 'line'); continue; end
        tot = tot + 1;
        if str2double(char(ln.getAttribute('hits'))) > 0
            covered = covered + 1;
        end
    end
    if tot == 0; continue; end
    if isKey(acc, key); v = acc(key); else; v = [0 0]; end
    acc(key) = v + [covered tot];
end
if isempty(keys(acc))
    % Every file bucketed to '' — the Cobertura filenames did not have the
    % expected lib/util/embedding shape (absolute path we failed to relativize,
    % or a wrong cwd). Name the real cause rather than surfacing later as a
    % misleading "baselined bucket X produced no coverage data".
    error('ci_coverage_folders:noMatch', ...
        'no coverage rows matched lib/util/embedding under %s (unexpected Cobertura filename shape or cwd)', root);
end
cov = struct();
ks = keys(acc);
for i = 1:numel(ks)
    v = acc(ks{i});
    cov.(ks{i}) = struct('cov',v(1),'tot',v(2),'rate',v(1)/v(2));
end
end

% ------------------------------------------------------------------------
function el = directChild(node, name)
% First direct child element of `node` whose tag is `name`, or [] if none.
el = [];
kids = node.getChildNodes;
for i = 0:kids.getLength-1
    k = kids.item(i);
    if strcmp(char(k.getNodeName), name)
        el = k; return
    end
end
end

% ------------------------------------------------------------------------
function key = bucketOf(fn, root)
% Map a Cobertura filename to a canonical bucket id (a valid struct
% fieldname), or '' if outside the measured tree. Relativizes against `root`
% first, so an absolute filename (`<root>/lib/@cada/x.m`) buckets the same as
% a repo-relative one (`lib\@cada\x.m`) — the code does not depend on which
% shape MATLAB emits.
fn = strrep(fn, '\', '/');
fn = erase(fn, strrep([root filesep], '\', '/'));  % absolute -> relative; no-op if already relative
if startsWith(fn, 'lib/@cada/')
    key = 'lib_cada';
elseif startsWith(fn, 'lib/@cadastruct/')
    key = 'lib_cadastruct';
elseif startsWith(fn, 'lib/cadaUtils/')
    key = 'lib_cadaUtils';
elseif startsWith(fn, 'lib/')
    key = 'lib_orchestration';
elseif startsWith(fn, 'util/')
    key = 'util';
elseif startsWith(fn, 'embedding/')
    key = 'embedding';
else
    key = '';   % outside the measured tree; ignore
end
end

% ------------------------------------------------------------------------
function lbl = bucketLabel(key)
% Human-facing folder path for a canonical bucket id (display only). NOTE:
% the orchestration bucket reads 'lib (orchestration)' here but is written to
% the baseline file as plain 'lib' by bucketLabel2key; key2bucket inverts
% that, so the two spellings are round-trip-safe — do not unify them naively.
switch key
    case 'lib_cada';           lbl = 'lib/@cada';
    case 'lib_cadastruct';     lbl = 'lib/@cadastruct';
    case 'lib_cadaUtils';      lbl = 'lib/cadaUtils';
    case 'lib_orchestration';  lbl = 'lib (orchestration)';
    otherwise;                 lbl = key;
end
end

% ------------------------------------------------------------------------
function printTable(measured, base)
order = {'embedding','util','lib_cadaUtils','lib_orchestration', ...
         'lib_cada','lib_cadastruct'};
fprintf('\n===== per-folder coverage (full suite) =====\n');
fprintf('%-22s %8s %8s   %s\n','folder','rate','floor','lines');
gc = 0; gt = 0;
for i = 1:numel(order)
    k = order{i};
    if ~isfield(measured, k); continue; end
    m = measured.(k); gc = gc + m.cov; gt = gt + m.tot;
    if isempty(base) || ~isfield(base, k); bs = '   -   ';
    else; bs = sprintf('%.4f', base.(k)); end
    fprintf('%-22s %8.4f %8s   (%d/%d)\n', bucketLabel(k), m.rate, bs, m.cov, m.tot);
end
if gt > 0
    fprintf('%-22s %8.4f %8s   (%d/%d)\n','AGGREGATE',gc/gt,'',gc,gt);
end
end

% ------------------------------------------------------------------------
function writeBaseline(basefile, measured)
order = {'embedding','util','lib_cadaUtils','lib_orchestration', ...
         'lib_cada','lib_cadastruct'};
fid = fopen(basefile,'w');
if fid < 0
    error('ci_coverage_folders:cannotWrite', 'could not open %s for writing', basefile);
end
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Per-folder full-suite line-coverage FLOOR (ci_coverage_folders.m).\n');
fprintf(fid, '# No-regression ratchet: each folder must hold its baselined rate within a\n');
fprintf(fid, '# single tolerance TOL (in the script). Values are the exact measured rate on\n');
fprintf(fid, '# the pinned release; one TOL (not a rounded floor *and* a tolerance) absorbs\n');
fprintf(fid, '# the ~0.3-0.6pp run-to-run jitter on the correctness-path buckets (lib/@cada,\n');
fprintf(fid, '# lib/@cadastruct, lib) — their instrumented-line set shifts with which\n');
fprintf(fid, '# overloads a run touches. Regenerate with: ci_coverage_folders(''write'').\n');
fprintf(fid, '# Correctness-path rates are RAISED as the #38/#103 value oracles land.\n');
for i = 1:numel(order)
    k = order{i};
    if ~isfield(measured, k); continue; end
    fprintf(fid, '%-18s %.4f\n', bucketLabel2key(k), measured.(k).rate);
end
end

% ------------------------------------------------------------------------
function base = readBaseline(basefile)
base = struct();
txt = fileread(basefile);
rows = regexp(txt, '\r\n|\n|\r', 'split');
for i = 1:numel(rows)
    row = strtrim(rows{i});
    if isempty(row) || row(1) == '#'; continue; end
    tok = regexp(row, '^(\S+)\s+([0-9.]+)$', 'tokens', 'once');
    if isempty(tok)
        error('ci_coverage_folders:badBaseline', 'unparseable baseline row: %s', row);
    end
    base.(key2bucket(tok{1})) = str2double(tok{2});
end
end

% ------------------------------------------------------------------------
function s = bucketLabel2key(key)
% On-disk baseline token for a canonical bucket id (stable, path-like).
switch key
    case 'lib_cada';           s = 'lib/@cada';
    case 'lib_cadastruct';     s = 'lib/@cadastruct';
    case 'lib_cadaUtils';      s = 'lib/cadaUtils';
    case 'lib_orchestration';  s = 'lib';
    otherwise;                 s = key;
end
end

% ------------------------------------------------------------------------
function key = key2bucket(tok)
% Inverse of bucketLabel2key: on-disk token -> canonical bucket id.
switch tok
    case 'lib/@cada';        key = 'lib_cada';
    case 'lib/@cadastruct';  key = 'lib_cadastruct';
    case 'lib/cadaUtils';    key = 'lib_cadaUtils';
    case 'lib';              key = 'lib_orchestration';
    case {'embedding','util'}; key = tok;
    otherwise
        error('ci_coverage_folders:badBaseline', 'unknown baseline folder token: %s', tok);
end
end
