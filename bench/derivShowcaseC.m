function report = derivShowcaseC(varargin)
%DERIVSHOWCASEC  C-level half of the all-axes derivative showcase (R17b, #73).
%
% Compiles the embeddable derivative cells through MATLAB Coder and measures the
% compiled artifact: generated-C size (a static-`lib` build), MEX-vs-MATLAB
% numeric equivalence, MEX runtime, and compile time. Complements the MATLAB-
% level complexity table of derivShowcase (R17a) with the on-target numbers, and
% can emit a code-size-vs-n scaling figure for the headline forward-vs-reverse
% gradient contrast.
%
%   report = derivShowcaseC('Name',value,...)
% Options (defaults in brackets):
%   n        [8]    problem size for the fixed-size cell table.
%   sweepN   [[4 8 16 32]]  sizes for the forward-vs-reverse scaling figure
%                   ([] to skip the figure).
%   figPath  ['']   write the scaling figure (PNG) here.
%   reportPath ['']  write the markdown table here.
%   verbose  [true]
%
% Returns .rows (per-cell C-level results), .table, .sweep (n-sweep data),
% .nFail, .available (false if MATLAB Coder is absent -> everything skip-clean).
%
% Non-gating, heavyweight (each cell is a Coder build, seconds to a minute). On a
% machine without Coder this returns immediately with .available = false.
%
% Copyright GMV.  2026-06  PEDRO LOURENÇO (PADL) (roadmap R17b, issue #73)
% Distributed under the GNU General Public License version 3.0
%
% see also derivShowcase, SCodegenTest, IRevEmbedTest

p = inputParser; p.FunctionName = 'derivShowcaseC';
p.addParameter('n',8,@(x)isnumeric(x)&&isscalar(x)&&x>=2);
p.addParameter('sweepN',[4 8 16 32],@(x)isnumeric(x));
p.addParameter('figPath','',@(x)ischar(x)||isstring(x));
p.addParameter('reportPath','',@(x)ischar(x)||isstring(x));
p.addParameter('verbose',true,@(x)islogical(x)&&isscalar(x));
p.parse(varargin{:}); o = p.Results;

cleanup = addShowcaseCPaths(); %#ok<NASGU>

report = struct('rows',[],'table','','sweep',[],'nFail',0,'available',true);
if isempty(which('codegen')) || ~license('test','MATLAB_Coder')
    report.available = false;
    if o.verbose; fprintf('derivShowcaseC: MATLAB Coder not available - skipping.\n'); end
    return
end

% embeddable cells (inline mode; c can't codegen - global/load). Vectorized
% anchors (codegen-friendly); a fixed-n point each: forward grd/hes/jac + the
% reverse gradient. (The rolled-loop axis is the MATLAB-level R17a table;
% rolled-loop codegen is a separate concern - ANALYSIS §2.3(7).)
cells = struct('fn',{'vcostfun','vcostfun','vcostfun','vvecfun'},...
               'DerType',{'gradient','gradient-reverse','hessian','jacobian'},...
               'unroll',{1,1,1,1});
rows = struct('fn',{},'DerType',{},'cBytes',{},'mexErr',{},...
    'mexMs',{},'matMs',{},'compileS',{},'ok',{},'note',{});
for ci = 1:numel(cells)
    if o.verbose; fprintf('  building %-8s %-16s (n=%d)...\n',cells(ci).fn,cells(ci).DerType,o.n); end
    rows(end+1) = buildCell(cells(ci), o.n); %#ok<AGROW>
end
report.rows  = rows;
report.nFail = sum(~[rows.ok] & ~strcmp({rows.note},'skip'));
report.table = renderCTable(rows, o.n);
if o.verbose; fprintf('\n%s\n', report.table); end
if ~isempty(o.reportPath); writelines(string(report.table), o.reportPath); end

% scaling figure: forward vs reverse gradient C size vs n
if ~isempty(o.sweepN)
    report.sweep = runSweep(o.sweepN, o.verbose);
    if ~isempty(o.figPath) && ~isempty(report.sweep)
        makeFigure(report.sweep, o.figPath);
        if o.verbose; fprintf('figure written to %s\n', o.figPath); end
    end
end
if o.verbose
    fprintf('\nderivShowcaseC: %d cells, %d build/equiv failure(s).\n',numel(rows),report.nFail);
end
end

%% --------------------------------------------------------------------- %%
function r = buildCell(c, n)
r = struct('fn',c.fn,'DerType',c.DerType,'cBytes',-1,'mexErr',-1,...
    'mexMs',-1,'matMs',-1,'compileS',-1,'ok',false,'note','');
base = pwd; d = tempname; mkdir(d);
restore = onCleanup(@() cleanupBuild(base, d));
xv = 0.3 + (1:n)'/10;
ga = analyticRef(c.fn, c.DerType, xv);
wrapper = wrapperNameC(c);
try
    cd(d);
    adigatorGenDerFile_embedded(c.DerType, c.fn, ...
        {adigatorCreateDerivInput([n 1],'x')}, ...
        adigatorOptions('overwrite',1,'echo',0,'embed_mode','i','unroll',c.unroll));
    clear(wrapper); rehash;
    matf = @() feval(wrapper, xv);
    r.matMs = 1e3*timeit(matf);

    t0 = tic;
    codegen(wrapper,'-args',{zeros(n,1)});
    r.compileS = toc(t0);
    mexf = str2func([wrapper '_mex']);
    D = mexf(xv);
    r.mexErr = norm(D(:)-ga(:),inf);
    r.mexMs  = 1e3*timeit(@() mexf(xv));
    clear([wrapper '_mex']);

    cfg = coder.config('lib'); cfg.GenerateReport = false;
    codegen(wrapper,'-config',cfg,'-args',{zeros(n,1)},'-d','clib');
    r.cBytes = sumCBytes(fullfile(d,'clib'));

    r.ok = r.mexErr <= 1e-9*max(1,norm(ga(:),inf));
    r.note = ternstr(r.ok,'ok',sprintf('MEX mismatch %.1e',r.mexErr));
catch e
    % availability is already gated above, so only a licence/checkout failure
    % is a genuine 'skip'; an unsupported-construct codegen error must surface
    % as a real build failure (counted in nFail), not be masked.
    if contains(e.message,'License','IgnoreCase',true) || ...
            contains(e.message,'licence','IgnoreCase',true)
        r.note = 'skip';
    else
        r.note = ['build error: ' e.message];
    end
end
cd(base);
end

%% --------------------------------------------------------------------- %%
function sweep = runSweep(ns, verbose)
% Forward vs reverse gradient (vcostfun, inline) C size + MEX runtime vs n.
sweep = struct('n',ns,'fwdC',nan(size(ns)),'revC',nan(size(ns)),...
    'fwdMs',nan(size(ns)),'revMs',nan(size(ns)));
for i = 1:numel(ns)
    if verbose; fprintf('  sweep n=%d ...\n',ns(i)); end
    f = buildCell(struct('fn','vcostfun','DerType','gradient','unroll',1), ns(i));
    rv = buildCell(struct('fn','vcostfun','DerType','gradient-reverse','unroll',1), ns(i));
    if f.ok;  sweep.fwdC(i)=f.cBytes;  sweep.fwdMs(i)=f.mexMs;  end
    if rv.ok; sweep.revC(i)=rv.cBytes; sweep.revMs(i)=rv.mexMs; end
end
end

function makeFigure(s, figPath)
% Compiled-C size vs n, forward vs reverse gradient (vcostfun, inline). For a
% vectorized cost the C is n-flat (n is a runtime array length); the reverse
% gradient is consistently leaner (no nonzero-location map; ANALYSIS §3.5).
% (MEX runtime at these sizes is at the timeit floor, so it is reported in the
% table, not plotted.)
fig = figure('Visible','off','Position',[100 100 520 360]);
plot(s.n, s.fwdC, '-o', s.n, s.revC, '-s', 'LineWidth', 1.6, 'MarkerSize', 7);
grid on; xlabel('n (number of variables)'); ylabel('generated C (bytes)');
title({'vcostfun gradient: compiled-C size','forward vs reverse, inline mode (R17b)'});
legend('forward gradient','reverse gradient','Location','east');
ylim([0 max([s.fwdC s.revC])*1.15]);
try
    exportgraphics(fig, figPath, 'Resolution', 120);
catch
    saveas(fig, figPath);
end
close(fig);
end

%% --------------------------------------------------------------------- %%
function b = sumCBytes(dir0)
b = 0; cf = dir(fullfile(dir0,'**','*.c'));
for k = 1:numel(cf); b = b + cf(k).bytes; end
end

function g = analyticRef(fn, dt, xv)
switch [fn '_' strrep(dt,'-','')]
    case 'vcostfun_gradient';        g = exp(xv)+2;
    case 'vcostfun_gradientreverse'; g = exp(xv)+2;
    case 'vcostfun_hessian';         g = diag(exp(xv));
    case 'vvecfun_jacobian';         g = diag(cos(xv)+2*xv);
    otherwise; error('no ref for %s/%s',fn,dt);
end
end

function w = wrapperNameC(c)
switch c.DerType
    case 'jacobian';         w = [c.fn '_Jac'];
    case 'gradient';         w = [c.fn '_Grd'];
    case 'hessian';          w = [c.fn '_Hes'];
    case 'gradient-reverse'; w = [c.fn '_RGrd'];
end
end

function cleanupBuild(base, d)
cd(base);
% MEX/lib artifacts live under d (the temp folder); best-effort remove
try
    if isfolder(d); rmdir(d,'s'); end
catch
end
end

function s = ternstr(c,a,b); if c; s=a; else; s=b; end; end

%% --------------------------------------------------------------------- %%
function md = renderCTable(rows, n)
hdr = sprintf("| function | DerType | C bytes (n=%d) | MEX≡analytic | MEX (ms) | MATLAB (ms) | compile (s) |",n);
sep = "|---|---|---:|---|---:|---:|---:|";
lines = [hdr; sep];
for k = 1:numel(rows)
    r = rows(k);
    eq = '—'; if r.mexErr>=0; eq = ternstr(r.ok,'yes',sprintf('NO (%.0e)',r.mexErr)); end
    lines(end+1,1) = string(sprintf("| %s | %s | %s | %s | %s | %s | %s |",...
        r.fn, r.DerType, fmt(r.cBytes,'%d'), eq, fmt(r.mexMs,'%.3f'),...
        fmt(r.matMs,'%.3f'), fmt(r.compileS,'%.1f'))); %#ok<AGROW>
end
md = char(strjoin(lines, newline));
end

function s = fmt(v, f)
if v < 0; s = '—'; else; s = sprintf(f, v); end
end

%% --------------------------------------------------------------------- %%
function c = addShowcaseCPaths()
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
saved = path;
addpath(root, fullfile(root,'lib'), fullfile(root,'lib','cadaUtils'),...
    fullfile(root,'util'), fullfile(root,'embedding'), fullfile(here,'showcase'));
c = onCleanup(@() path(saved));
end
