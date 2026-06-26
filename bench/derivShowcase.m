function report = derivShowcase(varargin)
%DERIVSHOWCASE  All-axes derivative showcase + complexity/correctness comparison.
%
% Roadmap R17 (issue #73 item B), MATLAB level (a). Generates one derivative of a
% curated anchor function through every relevant axis cell
%   embed_mode {c,l,i} x slim {0,1} x unroll {0,1}
%     x DerType {jacobian, gradient, hessian, gradient-reverse} x der_levels
% (not a clean cross-product - reverse needs unrolled scalar costs, the Jacobian
% needs a vector output), measures the generated code's MATLAB-level complexity,
% checks that every cell of the same (function, DerType) agrees numerically with
% the analytic derivative, and emits a "which mode should I pick?" markdown table.
%
% The C-level half (Coder: compiled-C size + runtime) is R17b.
%
%   report = derivShowcase('Name',value,...)
% Options (defaults in brackets):
%   n        [6]    problem size for generation/evaluation.
%   reportPath ['']  also write the markdown table here.
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
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorGenDerFile_embedded, IRevEmbedTest, IEmbedModesTest

p = inputParser; p.FunctionName = 'derivShowcase';
p.addParameter('n',6,@(x)isnumeric(x)&&isscalar(x)&&x>=2);
p.addParameter('reportPath','',@(x)ischar(x)||isstring(x));
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

rows = struct('fn',{},'DerType',{},'mode',{},'slim',{},'unroll',{},...
    'derLevels',{},'codeLines',{},'matBytes',{},'idxTables',{},'idxElems',{},...
    'ok',{},'note',{});

for ci = 1:numel(cells)
    c = cells(ci);
    if o.verbose
        fprintf('  [%2d/%2d] %-8s %-16s mode=%s slim=%d unroll=%d dl=[%s]\n',...
            ci,numel(cells),c.fn,c.DerType,c.mode,c.slim,c.unroll,num2str(c.derLevels));
    end
    r = runCell(c, n, xv, ref);
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
mk = @(fn,dt,m,sl,ur,dl) struct('fn',fn,'DerType',dt,'mode',m,'slim',sl,'unroll',ur,'derLevels',dl,'analytic','');
% analytic reference (issue #73): a hand-coded derivative - the "do I even need
% this tool?" baseline + the gold correctness oracle. Not a grid cell (no
% embed/slim/unroll), so mode='ana', the rest sentinel.
mka = @(fn,dt,ana) struct('fn',fn,'DerType',dt,'mode','ana','slim',-1,'unroll',-1,'derLevels',[],'analytic',ana);
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
% analytical references (hand-coded) - the AD-vs-analytical baseline
cells(end+1) = mka('vcostfun','gradient','vcostfun_grad_analytic');
cells(end+1) = mka('vcostfun','hessian','vcostfun_hess_analytic');
cells(end+1) = mka('vvecfun','jacobian','vvecfun_jac_analytic');
end

%% --------------------------------------------------------------------- %%
function r = runCell(c, n, xv, ref)
r = struct('fn',c.fn,'DerType',c.DerType,'mode',c.mode,'slim',c.slim,...
    'unroll',c.unroll,'derLevels',c.derLevels,'codeLines',-1,'matBytes',-1,...
    'idxTables',-1,'idxElems',-1,'ok',false,'note','');
base = pwd; d = tempname; mkdir(d);
restore = onCleanup(@() cd(base));
try
    if ~isempty(c.analytic)
        % analytic reference: a hand-coded file (no ADiGator generation, no
        % static data). Measure its code lines and confirm it evaluates to the
        % reference derivative.
        r.codeLines = countNonComment(which(c.analytic));
        r.matBytes = 0; r.idxTables = 0; r.idxElems = 0;
        [r.ok, r.note] = checkCorrectness(c, xv, ref);
    else
        cd(d);   % generate + evaluate from the cell's own folder (found before path)
        opts = adigatorOptions('overwrite',1,'echo',0,'embed_mode',c.mode,...
            'slim_embed',c.slim,'unroll',c.unroll);
        if ~isempty(c.derLevels); opts.der_levels = c.derLevels; end
        inputs = {adigatorCreateDerivInput([n 1],'x')};
        adigatorGenDerFile_embedded(c.DerType, c.fn, inputs, opts);

        [r.codeLines, r.matBytes, r.idxTables, r.idxElems] = measureComplexity(d);
        [r.ok, r.note] = checkCorrectness(c, xv, ref);
    end
catch e
    r.note = ['GEN/EVAL error: ' e.message];
end
cd(base);
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
function [ok, note] = checkCorrectness(c, xv, ref)
% Evaluate the generated wrapper and compare the derivative to the analytic
% reference. l/i need the coder.* namespace; report 'skip(coder)' if absent.
ok = false;   % note is set on every return path below
key = [c.fn '_' strrep(c.DerType,'-','')];   % gradient-reverse -> gradientreverse
g = ref.(key);
if ~isempty(c.analytic); wrapper = c.analytic; else; wrapper = wrapperName(c); end
clear(wrapper); clear('global',['ADiGator_',wrapper]); rehash;
try
    out = cell(1,abs(nargout(wrapper)));
    [out{:}] = feval(wrapper, xv);
catch e
    % classic mode needs no Coder, so a 'c' failure is always real (never skipped)
    if strcmp(c.mode,'c'); note = ['c eval failed: ' e.message]; return; end
    if contains(e.message,'coder.'); ok = true; note = 'skip(coder)'; return; end
    note = ['eval failed: ' e.message]; return
end
D = out{1};   % C-6: the top derivative is output 1 (Hessian file is [Hes,Grd,Fun])
tol = 1e-9 * max(1,norm(g(:),inf));
if norm(D(:)-g(:),inf) <= tol
    ok = true; note = 'ok';
else
    note = sprintf('MISMATCH (||.||inf=%.1e)', norm(D(:)-g(:),inf));
end
end

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
hdr = "| function | DerType | mode | slim | unroll | der_levels | code lines | .mat bytes | idx tables | idx elems | correct |";
sep = "|---|---|---|---|---|---|---:|---:|---:|---:|---|";
lines = [hdr; sep];
for k = 1:numel(rows)
    r = rows(k);
    dl = '—'; if ~isempty(r.derLevels); dl = ['[' num2str(r.derLevels) ']']; end
    sl = dash(r.slim); ur = dash(r.unroll);   % analytic rows use -1 sentinels
    lines(end+1,1) = string(sprintf("| %s | %s | %s | %s | %s | %s | %d | %d | %d | %d | %s |",...
        r.fn, r.DerType, r.mode, sl, ur, dl, r.codeLines, r.matBytes,...
        r.idxTables, r.idxElems, r.note)); %#ok<AGROW>
end
md = char(strjoin(lines, newline));
end

function s = dash(v); if v < 0; s = '—'; else; s = sprintf('%d',v); end; end

%% --------------------------------------------------------------------- %%
function c = addShowcasePaths()
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
saved = path;
addpath(root, fullfile(root,'lib'), fullfile(root,'lib','cadaUtils'),...
    fullfile(root,'util'), fullfile(root,'embedding'), ...
    fullfile(here,'showcase'), fullfile(here,'showcase','analytic'));
c = onCleanup(@() path(saved));
end
