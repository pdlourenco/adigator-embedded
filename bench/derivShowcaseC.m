function report = derivShowcaseC(varargin)
%DERIVSHOWCASEC  C-level half of the all-axes derivative showcase (R17b, #73).
%
% Compiles the embeddable derivative cells through Embedded Coder (ERT) and
% measures the compiled artifact: the honest on-target footprint - ROM
% (.text+.rdata), static RAM (.data+.bss) via `size -A`, and max stack via
% `gcc -fstack-usage` (R17c) - plus MEX-vs-MATLAB numeric equivalence, MEX
% runtime, and compile time. (The generated-C source-byte sum is retained only
% as a labelled secondary column - it is boilerplate-dominated and a poor ROM
% proxy; see R17c / ADR-0027.) Complements the MATLAB-level complexity table of
% derivShowcase (R17a) with the on-target numbers, and can emit a
% compiled-ROM-vs-n scaling figure for the headline forward-vs-reverse contrast.
%
%   report = derivShowcaseC('Name',value,...)
% Options (defaults in brackets):
%   n        [8]    problem size for the fixed-size cell table.
%   sweepN   [[256 1024 4096]]  sizes for the forward-vs-reverse scaling figure
%                   ([] to skip the figure).
%   figPath  ['']   write the scaling figure (PNG) here.
%   reportPath ['']  write the markdown table here.
%   texPath  ['']   write the ADR-0025 user-guide LaTeX fragment here
%                   (docs/userguide/bench_compare.tex): a deterministic C-size
%                   table + AD-vs-analytic ratios, stamped with the environment.
%   timeReps [1]    number of timeit passes to average the MEX/MATLAB runtimes
%                   over (1 = single sample). Pass >1 (e.g. 9) when emitting
%                   texPath so the committed runtime ratios are noise-reduced.
%   verbose  [true]
%
% Returns .rows (per-cell C-level results), .table, .sweep (n-sweep data),
% .nFail, .available (false if MATLAB Coder / Embedded Coder is absent ->
% everything skip-clean).
%
% The embeddable (i) cells build through Embedded Coder (ERT) - the strict target
% (#80 R20b); plain MATLAB Coder was masking ERT-only gaps. Non-gating, heavyweight
% (each cell is a Coder build, seconds to a minute). On a machine without Coder /
% Embedded Coder this returns immediately with .available = false.
%
% Copyright GMV.  2026-06  PEDRO LOURENÇO (PADL) (roadmap R17b, issue #73)
% Distributed under the GNU General Public License version 3.0
%
% see also derivShowcase, SCodegenTest, IRevEmbedTest

p = inputParser; p.FunctionName = 'derivShowcaseC';
p.addParameter('n',8,@(x)isnumeric(x)&&isscalar(x)&&x>=2);
p.addParameter('sweepN',[256 1024 4096],@(x)isnumeric(x));
p.addParameter('figPath','',@(x)ischar(x)||isstring(x));
p.addParameter('reportPath','',@(x)ischar(x)||isstring(x));
p.addParameter('texPath','',@(x)ischar(x)||isstring(x));   % ADR-0025 guide fragment
p.addParameter('timeReps',1,@(x)isnumeric(x)&&isscalar(x)&&x>=1); % runtime averaging passes (1 = single timeit; pass >1 when emitting texPath)
p.addParameter('verbose',true,@(x)islogical(x)&&isscalar(x));
p.parse(varargin{:}); o = p.Results;

cleanup = addShowcaseCPaths(); %#ok<NASGU>

report = struct('rows',[],'table','','sweep',[],'nFail',0,'available',true);
if isempty(which('codegen')) || ~license('test','MATLAB_Coder') || ...
        ~license('test','RTW_Embedded_Coder')
    report.available = false;
    if o.verbose; fprintf('derivShowcaseC: MATLAB Coder + Embedded Coder not available - skipping.\n'); end
    return
end

% embeddable cells (inline mode; c can't codegen - global/load). Vectorized
% anchors + one ROLLED Jacobian (vfun unroll=0) so the rolled-vs-unrolled axis
% reaches C. (Rolled scalar-cost gradient/Hessian now ERT-codegen too since #80
% Path A - pinned by SRolledErtCodegenTest - but are not yet added as C showcase
% cells here; that is a coverage follow-up. The MATLAB-level R17a table covers
% them.)
% Each AD cell is followed by the hand-coded ANALYTICAL reference for the same
% DerType (issue #73): the "do I even need this tool?" baseline + the gold
% correctness oracle. Analytic is a reference, not a grid cell - no
% embed/slim/unroll variants (unroll shown as -1 / '—').
mk = @(fn,dt,ur,impl,ana) struct('fn',fn,'DerType',dt,'unroll',ur,'impl',impl,'analytic',ana);
cells = [ mk('vcostfun','gradient',         1, 'AD',      ''), ...
          mk('vcostfun','gradient-reverse', 1, 'AD',      ''), ...
          mk('vcostfun','gradient',        -1, 'analytic','vcostfun_grad_analytic'), ...
          mk('vcostfun','hessian',          1, 'AD',      ''), ...
          mk('vcostfun','hessian',         -1, 'analytic','vcostfun_hess_analytic'), ...
          mk('vvecfun','jacobian',          1, 'AD',      ''), ...
          mk('vfun','jacobian',             0, 'AD',      ''), ...
          mk('vvecfun','jacobian',         -1, 'analytic','vvecfun_jac_analytic') ];
rows = struct('fn',{},'DerType',{},'impl',{},'unroll',{},...
    'romBytes',{},'ramBytes',{},'stackBytes',{},'cBytes',{},'mexErr',{},...
    'mexMs',{},'matMs',{},'compileS',{},'ok',{},'note',{});
for ci = 1:numel(cells)
    if o.verbose; fprintf('  building %-8s %-16s %-9s (n=%d)...\n',cells(ci).fn,cells(ci).DerType,cells(ci).impl,o.n); end
    rows(end+1) = buildCell(cells(ci), o.n, o.timeReps); %#ok<AGROW>
end
report.rows  = rows;
report.nFail = sum(~[rows.ok] & ~strcmp({rows.note},'skip'));
report.table = renderCTable(rows, o.n);
if o.verbose; fprintf('\n%s\n', report.table); end
if ~isempty(o.reportPath); writelines(string(report.table), o.reportPath); end
% ADR-0025: emit the committed, \input-able LaTeX fragment for the user guide
% (deterministic C-size table + averaged AD-vs-analytic ratios + env stamp).
if ~isempty(o.texPath); emitTexFragment(rows, o.n, o.timeReps, char(o.texPath)); end

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
function r = buildCell(c, n, timeReps)
if nargin < 3; timeReps = 1; end   % sweep callers time once; the fragment averages
impl = 'AD'; if isfield(c,'impl'); impl = c.impl; end
analytic = ''; if isfield(c,'analytic'); analytic = c.analytic; end
r = struct('fn',c.fn,'DerType',c.DerType,'impl',impl,'unroll',c.unroll,...
    'romBytes',-1,'ramBytes',-1,'stackBytes',-1,'cBytes',-1,'mexErr',-1,...
    'mexMs',-1,'matMs',-1,'compileS',-1,'ok',false,'note','');
base = pwd; d = tempname; mkdir(d);
restore = onCleanup(@() cleanupBuild(base, d));
xv = 0.3 + (1:n)'/10;
ga = analyticRef(c.fn, c.DerType, xv);
try
    cd(d);
    if ~isempty(analytic)
        wrapper = analytic;   % hand-coded reference; no ADiGator generation
    else
        wrapper = wrapperNameC(c);
        adigatorGenDerFile_embedded(c.DerType, c.fn, ...
            {adigatorCreateDerivInput([n 1],'x')}, ...
            adigatorOptions('overwrite',1,'echo',0,'embed_mode','i','unroll',c.unroll));
    end
    clear(wrapper); rehash;
    wf = str2func(wrapper);
    % average several timeit passes (each already a robust median) so the
    % committed ratios in the guide fragment are not a single noisy sample
    r.matMs = 1e3*mean(arrayfun(@(k) timeit(@() wf(xv)), 1:timeReps));

    t0 = tic;
    codegen(wrapper,'-args',{zeros(n,1)});
    r.compileS = toc(t0);
    mexf = str2func([wrapper '_mex']);
    D = mexf(xv);
    r.mexErr = norm(D(:)-ga(:),inf);
    r.mexMs  = 1e3*mean(arrayfun(@(k) timeit(@() mexf(xv)), 1:timeReps));
    clear([wrapper '_mex']);

    cfg = coder.config('lib','ecoder',true); cfg.GenerateReport = false;  % Embedded Coder / ERT (#80 R20b)
    codegen(wrapper,'-config',cfg,'-args',{zeros(n,1)},'-d','clib');
    r.cBytes = sumCBytes(fullfile(d,'clib'));
    % R17c (#73): the HONEST footprint - compile the ERT-generated C and read the
    % compiled object (ROM = .text+.rdata, static RAM = .data+.bss via `size -A`;
    % max stack via `gcc -fstack-usage`). Skip-clean (fields stay -1) when the
    % standalone gcc/size toolchain is absent; cBytes above is the source-byte
    % proxy kept only as a secondary column.
    fp = coreFootprint(fullfile(d,'clib'), wrapper);
    r.romBytes = fp.rom; r.ramBytes = fp.ram; r.stackBytes = fp.stack;

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
% Forward AD vs reverse AD vs hand-coded analytical gradient (vcostfun, inline):
% compiled-C size + MEX runtime vs n - the AD-vs-analytical crossover (#73).
% R17c: the size panel tracks compiled ROM (.text+.rdata), not source bytes.
sweep = struct('n',ns,'fwdRom',nan(size(ns)),'revRom',nan(size(ns)),'anaRom',nan(size(ns)),...
    'fwdMs',nan(size(ns)),'revMs',nan(size(ns)),'anaMs',nan(size(ns)));
for i = 1:numel(ns)
    if verbose; fprintf('  sweep n=%d ...\n',ns(i)); end
    f  = buildCell(struct('fn','vcostfun','DerType','gradient','unroll',1,'impl','AD','analytic',''), ns(i));
    rv = buildCell(struct('fn','vcostfun','DerType','gradient-reverse','unroll',1,'impl','AD','analytic',''), ns(i));
    an = buildCell(struct('fn','vcostfun','DerType','gradient','unroll',-1,'impl','analytic','analytic','vcostfun_grad_analytic'), ns(i));
    if f.ok  && f.romBytes  >= 0; sweep.fwdRom(i)=f.romBytes;  end
    if rv.ok && rv.romBytes >= 0; sweep.revRom(i)=rv.romBytes; end
    if an.ok && an.romBytes >= 0; sweep.anaRom(i)=an.romBytes; end
    if f.ok;  sweep.fwdMs(i)=f.mexMs;  end
    if rv.ok; sweep.revMs(i)=rv.mexMs; end
    if an.ok; sweep.anaMs(i)=an.mexMs; end
end
end

function makeFigure(s, figPath)
% Forward AD vs reverse AD vs hand-coded analytical gradient (vcostfun, inline)
% across a size range - the AD-vs-analytical crossover (#73):
%  left  - compiled ROM (.text+.rdata, Embedded Coder + `size`): the honest
%          footprint (R17c). For this vectorized cost the embeddable forms carry
%          ~0 static data, so forward/reverse/analytical CONVERGE and stay n-flat.
%  right - MEX runtime: all O(n) and essentially COMPARABLE - for this simple
%          cost the difference is neither code size nor speed.
fig = figure('Visible','off','Position',[100 100 820 340]);
subplot(1,2,1);
plot(s.n,s.fwdRom,'-o', s.n,s.revRom,'-s', s.n,s.anaRom,'-^','LineWidth',1.6,'MarkerSize',6);
grid on; set(gca,'XScale','log'); xlabel('n'); ylabel('compiled ROM (bytes)');
title('Compiled ROM (ERT)'); legend('forward AD','reverse AD','analytical','Location','northwest');
mx = max([s.fwdRom s.revRom s.anaRom]);   % all-NaN when the footprint toolchain is absent
if isfinite(mx) && mx > 0; ylim([0 mx*1.15]); end
subplot(1,2,2);
loglog(s.n,s.fwdMs,'-o', s.n,s.revMs,'-s', s.n,s.anaMs,'-^','LineWidth',1.6,'MarkerSize',6);
grid on; xlabel('n'); ylabel('MEX eval (ms)');
title('Compiled runtime (O(n), comparable)'); legend('forward AD','reverse AD','analytical','Location','northwest');
sgtitle('vcostfun gradient: AD vs analytical, inline mode (R17b)');
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

%% --------------------------------------------------------------------- %%
function fp = coreFootprint(clibDir, wrapper)
% R17c (#73, showcase-memory-metrics): the honest compiled footprint of the
% derivative FUNCTION - ROM (.text+.rdata), static RAM (.data+.bss) via
% `size -A`, and max stack frame via `gcc -Os -fstack-usage` (.su). Measures the
% CORE derivative object(s) only - `<wrapper>.c` and `<wrapper>_data.c` (the
% static index tables, where the ROM that differs between modes/forms actually
% lives) - deliberately EXCLUDING the lifecycle stubs (`_initialize`/`_terminate`),
% the `examples/` main and the `interface/` MEX gateway, none of which deploy to
% the embedded target. Why the compiled object and not the codegen report: the
% ERT static-code-metrics tables silently do not populate for generated AD code
% (a ~574 B stub vs a full report for a hand function) and GlobalVariables is
% empty for inline mode (const tables are .rdata, not globals) - so `size` /
% stack on the object is the reliable source (ADR-0027). rom/ram/stack stay -1
% (rendered as an em dash, treated as skip) when the standalone toolchain is
% absent - a Coder machine without gcc/size on disk still runs the rest.
fp = struct('rom',-1,'ram',-1,'stack',-1);
mingw = getenv('MW_MINGW64_LOC');
if isempty(mingw); mingw = fullfile(matlabroot,'bin',computer('arch'),'mingw64'); end
gcc  = fullfile(mingw,'bin','gcc.exe');
sizx = fullfile(mingw,'bin','size.exe');
if ~isfile(gcc) || ~isfile(sizx); return; end
inc  = fullfile(matlabroot,'extern','include');   % tmwtypes.h etc.
want = {[wrapper '.c'], [wrapper '_data.c']};
rom = 0; ram = 0; stack = 0; got = false;
for w = want
    cpath = fullfile(clibDir, w{1});
    if ~isfile(cpath); continue; end
    obj = [cpath '.o']; su = regexprep(obj,'\.o$','.su');
    % compile from the clib dir so the generated headers resolve and the .su
    % lands predictably next to the object
    cmd = sprintf('cd /d "%s" && "%s" -Os -fstack-usage -c "%s" -I"%s" -I"%s" -o "%s"', ...
        clibDir, gcc, w{1}, clibDir, inc, obj);
    % A hard toolchain failure below surfaces as a warning + an unmeasured (-1)
    % cell, never a wrong number - but on a non-gating bench it does NOT redden
    % the test (the footprint asserts skip on romBytes<0). Honest-or-nothing.
    [st, out] = system(cmd);
    if st ~= 0
        warning('derivShowcaseC:footprint','gcc failed on %s: %s', w{1}, strtrim(out));
        return   % partial measure would be misleading; report unmeasured
    end
    [sz, so] = system(sprintf('"%s" -A "%s"', sizx, obj));
    if sz ~= 0
        warning('derivShowcaseC:footprint','size failed on %s: %s', w{1}, strtrim(so));
        return   % symmetric with the gcc path: unmeasured, not a silent 0
    end
    got = true;
    rom = rom + sectBytes(so,{'.text','.rdata'});   % MinGW COFF: read-only is .rdata
    ram = ram + sectBytes(so,{'.data','.bss'});
    if isfile(su)
        T = string(splitlines(fileread(su)));
        for i = 1:numel(T)
            m = regexp(T(i),'\t(\d+)\t','tokens','once');
            if ~isempty(m); stack = max(stack, str2double(m(1))); end
        end
    end
end
if got; fp.rom = rom; fp.ram = ram; fp.stack = stack; end
end

function b = sectBytes(sizeOut, sects)
% sum the size column of the named sections from `size -A` output
b = 0; L = splitlines(sizeOut);
for i = 1:numel(L)
    p = regexp(strtrim(L{i}), '\s+', 'split');
    if numel(p) >= 2 && any(strcmp(p{1}, sects))
        v = str2double(p{2}); if ~isnan(v); b = b + v; end
    end
end
end

function g = analyticRef(fn, dt, xv)
switch [fn '_' strrep(dt,'-','')]
    case 'vcostfun_gradient';        g = exp(xv)+2;
    case 'vcostfun_gradientreverse'; g = exp(xv)+2;
    case 'vcostfun_hessian';         g = diag(exp(xv));
    case 'vvecfun_jacobian';         g = diag(cos(xv)+2*xv);
    case 'vfun_jacobian';            g = diag(cos(xv)+2*xv);
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
% R17c: lead with the compiled footprint (ROM/RAM/stack); the source-byte proxy
% is retained only as a trailing, explicitly-labelled column.
hdr = sprintf("| function | DerType | impl | unroll | ROM (B, n=%d) | RAM (B) | stack (B) | MEX≡analytic | MEX (ms) | MATLAB (ms) | compile (s) | C src (B) |",n);
sep = "|---|---|---|---:|---:|---:|---:|---|---:|---:|---:|---:|";
lines = [hdr; sep];
for k = 1:numel(rows)
    r = rows(k);
    eq = '—'; if r.mexErr>=0; eq = ternstr(r.ok,'yes',sprintf('NO (%.0e)',r.mexErr)); end
    ur = '—'; if r.unroll>=0; ur = sprintf('%d',r.unroll); end
    lines(end+1,1) = string(sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |",...
        r.fn, r.DerType, r.impl, ur, fmt(r.romBytes,'%d'), fmt(r.ramBytes,'%d'), ...
        fmt(r.stackBytes,'%d'), eq, fmt(r.mexMs,'%.3f'), fmt(r.matMs,'%.3f'), ...
        fmt(r.compileS,'%.1f'), fmt(r.cBytes,'%d'))); %#ok<AGROW>
end
md = char(strjoin(lines, newline));
end

function s = fmt(v, f)
if v < 0; s = '—'; else; s = sprintf(f, v); end
end

%% --------------------------------------------------------------------- %%
function emitTexFragment(rows, n, timeReps, texPath)
% ADR-0025: write the committed, \input-able user-guide fragment. The C-size
% column is a deterministic build artifact; the C/analytic and MEX/analytic
% columns are AD-vs-hand-coded ratios (runtime averaged over timeReps timeit
% passes, so a machine-dependent but noise-reduced figure). Stamped with the
% environment (incl. processor). No timestamps (ADR-0025 constraint 4).
st = envStamp();
L = strings(0,1);
L(end+1) = "% !!! GENERATED by bench/derivShowcaseC.m - DO NOT EDIT BY HAND !!!";
L(end+1) = string(sprintf("%% Regenerate: addpath bench; derivShowcaseC('n',%d,'sweepN',[],'timeReps',%d,'texPath','docs/userguide/bench_compare.tex')", n, timeReps));
L(end+1) = string(sprintf("%% Measured on: %s | %s | %s | %s | %s.", st.machine, st.processor, st.matlab, st.coder, st.compiler));
L(end+1) = string(sprintf("%% C size (kB, n=%d) is a near-deterministic build artifact (raw .c bytes vary by <=2 across rebuilds; kB at 1 decimal is stable) - this is the RELIABLE comparison. C/ana is the deterministic size ratio. MEX/ana is the AD-vs-analytic runtime ratio, averaged over %d timeit passes but MACHINE-DEPENDENT and NOISY (~+/-40%% run-to-run: the compiled evals are microseconds, overhead-bound) - read as an order-of-magnitude, not a precise figure.", n, timeReps));
L(end+1) = "\begin{tabular}{@{}lllrrr@{}}";
L(end+1) = "\hline";
L(end+1) = string(sprintf("function & derivative & impl & C (kB, $n{=}%d$) & C\\,/\\,ana & MEX\\,/\\,ana \\\\", n));
L(end+1) = "\hline";
for k = 1:numel(rows)
    r = rows(k);
    if r.cBytes < 0; continue; end                 % skip un-built / skipped cells
    isAna = strcmp(r.impl,'analytic');
    [cr, mr] = ratioVsAnalytic(r, rows);
    if isAna
        implLbl = 'analytic';
    elseif contains(r.DerType,'reverse')
        implLbl = 'AD (rev)';
    elseif strcmp(r.DerType,'gradient')
        implLbl = 'AD (fwd)';
    else
        implLbl = 'AD';
    end
    L(end+1) = string(sprintf("%s & %s & %s & %.1f & %s & %s \\\\", ...
        texEsc(r.fn), texEsc(r.DerType), implLbl, r.cBytes/1000, ...
        ratioStr(cr, isAna, '%.2f'), ratioStr(mr, isAna, '%.1f'))); %#ok<AGROW>
end
L(end+1) = "\hline";
L(end+1) = "\end{tabular}";
writelines(L, texPath);
end

function [cr, mr] = ratioVsAnalytic(row, rows)
% AD cell / its hand-coded analytic counterpart (same function, same DerType;
% gradient-reverse compares against the analytic *gradient*). -1 when there is
% no analytic cell for that function (e.g. the rolled vfun Jacobian).
cr = -1; mr = -1;
if strcmp(row.impl,'analytic'); return; end
normDT = strrep(row.DerType,'-reverse','');
for k = 1:numel(rows)
    a = rows(k);
    if strcmp(a.impl,'analytic') && strcmp(a.fn,row.fn) && strcmp(a.DerType,normDT)
        if a.cBytes > 0 && row.cBytes > 0; cr = row.cBytes / a.cBytes; end
        if a.mexMs  > 0 && row.mexMs  > 0; mr = row.mexMs  / a.mexMs;  end
        return;
    end
end
end

function s = ratioStr(v, isAnalytic, fmt)
if nargin < 3; fmt = '%.2f'; end
if isAnalytic; s = sprintf(fmt, 1); elseif v < 0; s = '\textemdash{}'; else; s = sprintf(fmt, v); end
end

function t = texEsc(s)
% minimal LaTeX escaping for the controlled label strings used here
t = strrep(char(s), '_', '\_');
end

function st = envStamp()
% environment provenance for the committed fragment (ADR-0025 constraint 3).
% `version` (not ver('matlab')) gives e.g. "24.1.0.2537033 (R2024a)".
st = struct('machine',computer, 'processor',cpuName, ...
    'matlab',['MATLAB ' version], 'coder','', 'compiler','');
try
    v = ver;
    cn = {v.Name};
    ci = find(strcmp(cn,'MATLAB Coder') | strcmp(cn,'Embedded Coder'));  % the two used here
    if ~isempty(ci)
        st.coder = strjoin(arrayfun(@(k) sprintf('%s %s', v(k).Name, v(k).Version), ...
            ci, 'UniformOutput', false), ', ');
    end
catch
end
if isempty(st.coder); st.coder = 'Coder ?'; end
try
    cc = mex.getCompilerConfigurations('C','Selected');
    if ~isempty(cc)
        st.compiler = strtrim(sprintf('%s %s', cc(1).Name, cc(1).Version));
    end
catch
end
if isempty(st.compiler); st.compiler = 'compiler ?'; end
end

function proc = cpuName()
% friendly CPU name where available (the maintainer asked for the processor in
% the stamp); fall back to the coarse identifier / arch.
proc = '';
if ispc
    try
        proc = strtrim(winqueryreg('HKEY_LOCAL_MACHINE', ...
            'HARDWARE\DESCRIPTION\System\CentralProcessor\0', 'ProcessorNameString'));
    catch
    end
end
if isempty(proc); proc = getenv('PROCESSOR_IDENTIFIER'); end
if isempty(proc); proc = computer('arch'); end
end

%% --------------------------------------------------------------------- %%
function c = addShowcaseCPaths()
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
saved = path;
addpath(root, fullfile(root,'lib'), fullfile(root,'lib','cadaUtils'),...
    fullfile(root,'util'), fullfile(root,'embedding'), ...
    fullfile(here,'showcase'), fullfile(here,'showcase','analytic'));
c = onCleanup(@() path(saved));
end
