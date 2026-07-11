function report = derivShowcase(varargin)
%DERIVSHOWCASE  All-axes derivative showcase + complexity/correctness/runtime.
%
% Roadmap R17 (issue #73 item B), MATLAB level (a) - the UN-GATED interpreted
% harness. Generates one derivative of a curated anchor function through every
% relevant axis cell
%   embed_mode {c,l,i} x slim {0,1} x unroll {0,1}
%     x DerType {jacobian, gradient, hessian, gradient-reverse} x der_levels
% (not a clean cross-product - reverse needs unrolled scalar costs, the Jacobian
% needs a vector output), across the four METHODS the "which method?" question
% weighs - AD forward, AD reverse, finite differences (FD), and a hand-coded
% analytical reference - and measures, for every cell, on any machine (no Coder):
%   - complexity: generated code lines, .mat data bytes, Index* table count/size
%   - interpreted RUNTIME: timeit of the derivative evaluation (the no-compile
%     simulation cost - it re-ranks the modes vs compiled C: embed-mode load cost,
%     slim's larger interpreted win, FD's O(n)/O(n^2) eval blow-up)
%   - accuracy: max error vs the analytic reference (0 for AD/analytical; the
%     truncation error is FD's informative, headline column - it is the only
%     inexact method here).
%
% The C-level half (Embedded Coder: compiled ROM/RAM/stack + MEX runtime) is
% R17b/R17c (bench/derivShowcaseC.m). Together they are the 4-methods x
% 2-environments matrix that answers "which method + mode should I pick?".
%
%   report = derivShowcase('Name',value,...)
% Options (defaults in brackets):
%   n        [6]    problem size for generation/evaluation.
%   reportPath ['']  also write the markdown table here.
%   texPath  ['']    also write the committed \input-able guide fragment here
%                    (docs/userguide/bench_interp.tex): a deterministic
%                    complexity table + interpreted-runtime ratios + FD accuracy,
%                    stamped with the environment (ADR-0025).
%   timeReps [1]     number of timeit passes to average the interpreted runtimes
%                    (pass >1 when emitting texPath so the committed ratios are
%                    not a single noisy sample).
%   verbose  [true]  print progress + the table.
%   cells    [all]   restrict to a subset (struct array) for a quick run.
%
% Returns a struct: .rows (per-cell results), .table (the markdown), .nFail.
%
% Each cell generates into its own temp folder (isolated, clean tree - the #67/#69
% discipline). Non-gating; this is a benchmark/teaching harness, not a PR gate.
%
% Copyright GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com  (roadmap R17, issue #73)
%   2026-07  + interpreted runtime + FD method + guide fragment (issue #73)
% Distributed under the GNU General Public License version 3.0
%
% see also derivShowcaseC, fdDeriv, adigatorGenDerFile_embedded, IRevEmbedTest

p = inputParser; p.FunctionName = 'derivShowcase';
p.addParameter('n',6,@(x)isnumeric(x)&&isscalar(x)&&x>=2);
p.addParameter('reportPath','',@(x)ischar(x)||isstring(x));
p.addParameter('texPath','',@(x)ischar(x)||isstring(x));
p.addParameter('timeReps',1,@(x)isnumeric(x)&&isscalar(x)&&x>=1);
p.addParameter('verbose',true,@(x)islogical(x)&&isscalar(x));
p.addParameter('cells',[],@(x)isempty(x)||isstruct(x));
p.parse(varargin{:}); o = p.Results;

cleanup = addShowcasePaths(); %#ok<NASGU>  % restored on exit

cells = o.cells;
if isempty(cells); cells = defaultGrid(); end
n  = o.n;
xv = 0.3 + (1:n)'/10;                 % a fixed positive evaluation point

% analytic references, keyed by 'fn|DerType'
ref = struct();
ref.scostfun_gradient  = exp(xv)+2;                 % d/dx sum(exp(x)+2x)
ref.scostfun_hessian   = diag(exp(xv));             % Hessian
ref.vfun_jacobian      = diag(cos(xv)+2*xv);        % d/dx [sin(x)+x.^2]
ref.scostfun_gradientreverse = ref.scostfun_gradient;
ref.vcostfun_gradient        = exp(xv)+2;           % vectorized (no subscripting)
ref.vcostfun_gradientreverse = exp(xv)+2;
ref.vcostfun_hessian         = diag(exp(xv));
ref.vvecfun_jacobian         = diag(cos(xv)+2*xv);

rows = struct('fn',{},'DerType',{},'method',{},'mode',{},'slim',{},'unroll',{},...
    'derLevels',{},'codeLines',{},'matBytes',{},'idxTables',{},'idxElems',{},...
    'runtimeMs',{},'errAna',{},'ok',{},'note',{});

for ci = 1:numel(cells)
    c = cells(ci);
    if o.verbose
        fprintf('  [%2d/%2d] %-8s %-16s %-9s mode=%s slim=%d unroll=%d dl=[%s]\n',...
            ci,numel(cells),c.fn,c.DerType,c.method,c.mode,c.slim,c.unroll,num2str(c.derLevels));
    end
    r = runCell(c, n, xv, ref, o.timeReps);
    rows(end+1) = r; %#ok<AGROW>
end

report.rows  = rows;
report.nFail = sum(~[rows.ok]);
report.table = renderTable(rows);
if o.verbose; fprintf('\n%s\n', report.table); end
if ~isempty(o.reportPath)
    writelines(string(report.table), o.reportPath);
    if o.verbose; fprintf('report written to %s\n', o.reportPath); end
end
if ~isempty(o.texPath)
    emitTexFragment(rows, n, o.timeReps, char(o.texPath));
    if o.verbose; fprintf('guide fragment written to %s\n', o.texPath); end
end
if o.verbose
    fprintf('\nderivShowcase: %d cells, %d correctness failure(s).\n',...
        numel(rows), report.nFail);
end
end

%% --------------------------------------------------------------------- %%
function cells = defaultGrid()
% The curated, non-orthogonal grid. scostfun (scalar) covers gradient/Hessian/
% reverse; vfun (vector) covers the Jacobian. embed x slim x unroll vary per the
% axis being illustrated; reverse is unrolled-only (R16; rolled reverse is R19).
% method='AD' cells sweep the embed grid; method='analytic'/'FD' are per-(fn,
% DerType) REFERENCE points (a hand-coded file / a finite-difference wrapper),
% not grid cells - no embed/slim/unroll, so those fields are the -1 sentinel.
mk  = @(fn,dt,m,sl,ur,dl) struct('fn',fn,'DerType',dt,'method','AD','mode',m,'slim',sl,'unroll',ur,'derLevels',dl,'refFile','');
mka = @(fn,dt,ref) struct('fn',fn,'DerType',dt,'method','analytic','mode','ana','slim',-1,'unroll',-1,'derLevels',[],'refFile',ref);
mkfd= @(fn,dt,ref) struct('fn',fn,'DerType',dt,'method','FD','mode','fd','slim',-1,'unroll',-1,'derLevels',[],'refFile',ref);
cells = mk('scostfun','gradient','c',0,0,[]);
% gradient (forward): embed x unroll, slim on; + a slim off/on pair at 'i'
cells(end+1) = mk('scostfun','gradient','l',1,0,[]);
cells(end+1) = mk('scostfun','gradient','i',1,0,[]);
cells(end+1) = mk('scostfun','gradient','i',0,0,[]);    % slim off (vs the slim-on 'i' above)
cells(end+1) = mk('scostfun','gradient','i',1,1,[]);    % unrolled
% Hessian (forward): embed; + der_levels=[2] (drop Grd,Fun -> just Hes)
cells(end+1) = mk('scostfun','hessian','c',0,0,[]);
cells(end+1) = mk('scostfun','hessian','i',1,0,[]);
cells(end+1) = mk('scostfun','hessian','i',1,0,2);      % der_levels: Hes only
% gradient-reverse: embed, unrolled (reverse requirement)
cells(end+1) = mk('scostfun','gradient-reverse','c',0,1,[]);
cells(end+1) = mk('scostfun','gradient-reverse','l',0,1,[]);
cells(end+1) = mk('scostfun','gradient-reverse','i',0,1,[]);
% Jacobian (forward, vector output): embed x unroll
cells(end+1) = mk('vfun','jacobian','c',0,0,[]);
cells(end+1) = mk('vfun','jacobian','i',1,0,[]);
cells(end+1) = mk('vfun','jacobian','i',1,1,[]);
% forward-vs-reverse ROM contrast on a vectorized cost (no subscripting), in
% coderload mode so the static data lands in the .mat: the forward gradient
% carries the location index; the reverse carries ZERO static data (§3.5).
cells(end+1) = mk('vcostfun','gradient','l',0,1,[]);
cells(end+1) = mk('vcostfun','gradient-reverse','l',0,1,[]);
% the four-method reference points (issue #73), per (fn, DerType): a hand-coded
% analytical derivative (exact, the gold oracle + "do I even need this tool?"
% baseline) and a finite-difference derivative (the only INEXACT method - its
% accuracy column is the point; cheap to write, O(n)/O(n^2) evals).
cells(end+1) = mka('vcostfun','gradient','vcostfun_grad_analytic');
cells(end+1) = mkfd('vcostfun','gradient','vcostfun_grad_fd');
cells(end+1) = mka('vcostfun','hessian','vcostfun_hess_analytic');
cells(end+1) = mkfd('vcostfun','hessian','vcostfun_hess_fd');
cells(end+1) = mka('vvecfun','jacobian','vvecfun_jac_analytic');
cells(end+1) = mkfd('vvecfun','jacobian','vvecfun_jac_fd');
end

%% --------------------------------------------------------------------- %%
function r = runCell(c, n, xv, ref, timeReps)
r = struct('fn',c.fn,'DerType',c.DerType,'method',c.method,'mode',c.mode,...
    'slim',c.slim,'unroll',c.unroll,'derLevels',c.derLevels,'codeLines',-1,...
    'matBytes',-1,'idxTables',-1,'idxElems',-1,'runtimeMs',-1,'errAna',-1,...
    'ok',false,'note','');
base = pwd; d = tempname; mkdir(d);
restore = onCleanup(@() cd(base));
try
    if ~isempty(c.refFile)
        % a hand-written wrapper (analytical reference or finite-difference
        % method): no ADiGator generation, no static data. Measure its code lines
        % and confirm it evaluates to (analytic) / near (FD) the reference.
        r.codeLines = countNonComment(which(c.refFile));
        r.matBytes = 0; r.idxTables = 0; r.idxElems = 0;
        wrapper = c.refFile;
    else
        cd(d);   % generate + evaluate from the cell's own folder (found before path)
        opts = adigatorOptions('overwrite',1,'echo',0,'embed_mode',c.mode,...
            'slim_embed',c.slim,'unroll',c.unroll);
        if ~isempty(c.derLevels); opts.der_levels = c.derLevels; end
        inputs = {adigatorCreateDerivInput([n 1],'x')};
        adigatorGenDerFile_embedded(c.DerType, c.fn, inputs, opts);
        [r.codeLines, r.matBytes, r.idxTables, r.idxElems] = measureComplexity(d);
        wrapper = wrapperName(c);
    end
    [D, r.runtimeMs, skipNote] = evalAndTime(wrapper, xv, timeReps);
    if ~isempty(skipNote)
        % l/i need the coder.* namespace; a 'c'/analytic/FD wrapper never skips
        if strcmp(c.mode,'c')
            r.note = skipNote; % classic needs no Coder -> a real failure
        else
            r.ok = true; r.note = 'skip(coder)';
        end
    else
        [r.ok, r.errAna, r.note] = judge(c, D, ref);
    end
catch e
    r.note = ['GEN/EVAL error: ' e.message];
end
cd(base);
end

%% --------------------------------------------------------------------- %%
function [D, runtimeMs, skipNote] = evalAndTime(wrapper, xv, timeReps)
% Evaluate the wrapper once (for correctness) and timeit it (interpreted
% runtime). Returns skipNote non-empty when the coder.* namespace is missing
% (embed l/i on a machine without it) so the caller can mark skip(coder).
D = []; runtimeMs = -1; skipNote = '';
clear(wrapper); clear('global',['ADiGator_',wrapper]); rehash;
wf = str2func(wrapper);
try
    out = cell(1,abs(nargout(wrapper)));
    [out{:}] = wf(xv);
catch e
    if contains(e.message,'coder.'); skipNote = 'skip(coder)'; return; end
    rethrow(e);
end
D = out{1};   % C-6: the top derivative is output 1 (Hessian file is [Hes,Grd,Fun])
% interpreted runtime. A single derivative eval at small n is BELOW timeit's
% reliable floor (sub-microsecond for the vectorized analytic reference), which
% makes the ratio-vs-analytic denominator pure timer noise. Time a BATCH of K
% calls (K chosen so the batch clears ~2 ms) and divide - so even the fastest
% method is measured above the floor and the committed ratios are stable.
wf(xv);                                   % warm the JIT
tic; for i = 1:50; wf(xv); end; t1 = toc/50;   % rough estimate (no timeit warning)
K  = min(1e4, max(1, ceil(2e-3/max(t1,1e-9))));
runtimeMs = 1e3*mean(arrayfun(@(r) timeit(@() callK(wf,xv,K))/K, 1:timeReps));
end

function callK(wf, xv, K)
% call the wrapper K times so a fast function's batch clears the timer floor
for i = 1:K; wf(xv); end
end

%% --------------------------------------------------------------------- %%
function [ok, errAna, note] = judge(c, D, ref)
% Compare the derivative to the analytic reference. AD/analytical are exact
% (tol 1e-9); FD is inexact BY DESIGN, so its (larger) truncation error is
% recorded and gated at a loose FD tolerance - a within-tolerance FD result is
% correct, and its error is the informative accuracy column.
key = [c.fn '_' strrep(c.DerType,'-','')];   % gradient-reverse -> gradientreverse
g = ref.(key);
errAna = norm(D(:)-g(:),inf);
scale  = max(1,norm(g(:),inf));
if strcmp(c.method,'FD')
    tol = 1e-4*scale;   % central-difference truncation floor (see fdDeriv)
    ok  = errAna <= tol;
    note = ternstr(ok, sprintf('FD err=%.1e', errAna), sprintf('FD OFF (%.1e)', errAna));
else
    tol = 1e-9*scale;
    ok  = errAna <= tol;
    note = ternstr(ok, 'ok', sprintf('MISMATCH (%.1e)', errAna));
end
end

%% --------------------------------------------------------------------- %%
function nstmt = countNonComment(file)
% non-comment / non-blank line count of a .m file (the hand-code "size").
nstmt = -1;
if isempty(file) || ~isfile(file); return; end
L = strtrim(readlines(file));
L = L(strlength(L)>0 & ~startsWith(L,'%'));
nstmt = numel(L);
end

%% --------------------------------------------------------------------- %%
function [codeLines, matBytes, idxTables, idxElems] = measureComplexity(d)
% Total non-comment/non-blank .m lines (code size), total .mat bytes (data ROM),
% and the Gator*Data.Index* table count/element count (the §3.5 index ROM).
codeLines = 0;
mfiles = dir(fullfile(d,'*.m'));
for k = 1:numel(mfiles)
    L = strtrim(readlines(fullfile(mfiles(k).folder,mfiles(k).name)));
    L = L(strlength(L)>0 & ~startsWith(L,'%'));
    codeLines = codeLines + numel(L);
end
matBytes = 0; idxTables = 0; idxElems = 0;
matfiles = dir(fullfile(d,'*.mat'));
for k = 1:numel(matfiles)
    matBytes = matBytes + matfiles(k).bytes;
    s = load(fullfile(matfiles(k).folder,matfiles(k).name));
    [t,e] = countIndex(s); idxTables = idxTables + t; idxElems = idxElems + e;
end
end

function [t,e] = countIndex(s)
t = 0; e = 0;
if isstruct(s)
    fn = fieldnames(s);
    for k = 1:numel(fn)
        for j = 1:numel(s)
            v = s(j).(fn{k});
            if contains(fn{k},'Index') && (isnumeric(v)||islogical(v))
                % forward Index* and reverse RIndex* index tables
                t = t + 1; e = e + numel(v);
            elseif isstruct(v)
                [tt,ee] = countIndex(v); t = t+tt; e = e+ee;
            end
        end
    end
end
end

%% --------------------------------------------------------------------- %%
function w = wrapperName(c)
switch c.DerType
    case 'jacobian';         w = [c.fn '_Jac'];
    case 'gradient';         w = [c.fn '_Grd'];
    case 'hessian';          w = [c.fn '_Hes'];
    case 'gradient-reverse'; w = [c.fn '_RGrd'];
end
end

%% --------------------------------------------------------------------- %%
function md = renderTable(rows)
hdr = "| function | DerType | method | mode | slim | unroll | der_levels | code lines | .mat bytes | idx tables | idx elems | interp (ms) | max err | correct |";
sep = "|---|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|---|";
lines = [hdr; sep];
for k = 1:numel(rows)
    r = rows(k);
    dl = '—'; if ~isempty(r.derLevels); dl = ['[' num2str(r.derLevels) ']']; end
    sl = dash(r.slim); ur = dash(r.unroll);   % analytic/FD rows use -1 sentinels
    lines(end+1,1) = string(sprintf("| %s | %s | %s | %s | %s | %s | %s | %d | %d | %d | %d | %s | %s | %s |",...
        r.fn, r.DerType, r.method, r.mode, sl, ur, dl, r.codeLines, r.matBytes,...
        r.idxTables, r.idxElems, fmt(r.runtimeMs,'%.3f'), errStr(r.errAna), r.note)); %#ok<AGROW>
end
md = char(strjoin(lines, newline));
end

function s = dash(v); if v < 0; s = '—'; else; s = sprintf('%d',v); end; end
function s = fmt(v, f); if v < 0; s = '—'; else; s = sprintf(f, v); end; end
function s = errStr(v); if v < 0; s = '—'; else; s = sprintf('%.1e', v); end; end
function s = ternstr(c,a,b); if c; s=a; else; s=b; end; end

%% --------------------------------------------------------------------- %%
function emitTexFragment(rows, n, timeReps, texPath)
% ADR-0025: write the committed, \input-able user-guide fragment for the
% INTERPRETED environment (the companion to derivShowcaseC's bench_compare.tex
% for compiled C). Deterministic complexity columns (code lines, index elements)
% + interpreted-runtime ratios vs the analytical reference (machine-dependent,
% averaged over timeReps) + the FD accuracy column. Environment-stamped, no
% timestamps (ADR-0025 constraint 4). Emits one row per (fn, DerType, method)
% reference point plus the AD forward/reverse cells, so it carries all four
% methods side by side.
keep = rows(arrayfun(@(r) wantInTex(r), rows));
if isempty(keep)
    warning('derivShowcase:texFragment', ...
        'no cell qualifies for the interpreted fragment - leaving %s unchanged', texPath);
    return
end
st = envStamp();
L = strings(0,1);
L(end+1) = "% !!! GENERATED by bench/derivShowcase.m - DO NOT EDIT BY HAND !!!";
L(end+1) = string(sprintf("%% Regenerate: addpath bench; derivShowcase('n',%d,'timeReps',%d,'texPath','docs/userguide/bench_interp.tex')", n, timeReps));
L(end+1) = string(sprintf("%% Measured on: %s | %s.", st.machine, st.matlab));
L(end+1) = string(sprintf("%% INTERPRETED-MATLAB environment (no Coder). Code lines are DETERMINISTIC (for AD/analytical the full implementation; for FD the per-anchor wrapper only - it reuses the shared fdDeriv kernel, not counted here, so read FD's figure as the marginal per-function cost). interp/ana is the interpreted derivative-evaluation time vs the hand-coded analytical derivative, averaged over %d timeit passes - MACHINE-DEPENDENT and NOISY: read the trend (finite-difference FD grows with n; slim trims interpreted dead code the compiler would DCE anyway), not the absolute ratio. 'max err' is the derivative error vs the analytical reference - zero for AD/analytical, the truncation error for FD (the only inexact method).", timeReps));
L(end+1) = "\begin{tabular}{@{}lllrrl@{}}";
L(end+1) = "\hline";
L(end+1) = "function & derivative & method & code lines & interp\,/\,ana & max err \\";
L(end+1) = "\hline";
for k = 1:numel(keep)
    r = keep(k);
    rr = runtimeRatio(r, rows);
    L(end+1) = string(sprintf("%s & %s & %s & %d & %s & %s \\\\", ...
        texEsc(r.fn), texEsc(r.DerType), methodLbl(r), r.codeLines, ...
        ratioStr(rr, strcmp(r.method,'analytic')), errTex(r))); %#ok<AGROW>
end
L(end+1) = "\hline";
L(end+1) = "\end{tabular}";
writelines(L, texPath);
end

function tf = wantInTex(r)
% one representative row per method per (fn,DerType): the analytic + FD reference
% points, plus the AD forward and reverse cells on the vectorized cost/output
% anchors that have an analytic counterpart (so ratios resolve).
if ~r.ok; tf = false; return; end
if any(strcmp(r.method,{'analytic','FD'})); tf = true; return; end
% AD: keep the inline (i) or coderload (l) unrolled cell on anchors with a ref
tf = any(strcmp(r.fn,{'vcostfun','vvecfun'})) && ismember(r.mode,{'l','i'});
end

function lbl = methodLbl(r)
if strcmp(r.method,'analytic')
    lbl = 'analytic';
elseif strcmp(r.method,'FD')
    lbl = 'FD (num)';
elseif contains(r.DerType,'reverse')
    lbl = 'AD (rev)';
elseif strcmp(r.DerType,'gradient')
    lbl = 'AD (fwd)';
else
    lbl = 'AD';
end
end

function rr = runtimeRatio(row, rows)
% interpreted runtime of this row vs the analytical reference for the same
% (fn, DerType); gradient-reverse compares against the analytic gradient. -1
% when no analytic counterpart / no runtime measured.
rr = -1; normDT = strrep(row.DerType,'-reverse','');
if row.runtimeMs <= 0; return; end
for k = 1:numel(rows)
    a = rows(k);
    if strcmp(a.method,'analytic') && strcmp(a.fn,row.fn) && ...
            strcmp(a.DerType,normDT) && a.runtimeMs > 0
        rr = row.runtimeMs / a.runtimeMs; return;
    end
end
end

function s = ratioStr(v, isAnalytic)
if isAnalytic; s = '1'; elseif v < 0; s = '\textemdash{}'; else; s = sprintf('%.1f', v); end
end

function s = errTex(r)
if strcmp(r.method,'FD') && r.errAna >= 0
    s = sprintf('%.0e', r.errAna);
else
    s = '$0$';   % AD/analytical are machine-eps exact
end
end

function t = texEsc(s)
t = strrep(char(s), '_', '\_');
end

function st = envStamp()
st = struct('machine',computer, 'matlab',['MATLAB ' version]);
end

%% --------------------------------------------------------------------- %%
function c = addShowcasePaths()
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
saved = path;
addpath(root, fullfile(root,'lib'), fullfile(root,'lib','cadaUtils'),...
    fullfile(root,'util'), fullfile(root,'embedding'), ...
    fullfile(here,'showcase'), fullfile(here,'showcase','analytic'), ...
    fullfile(here,'showcase','fd'));
c = onCleanup(@() path(saved));
end
