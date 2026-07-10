function report = loopboundPaddingPenalty(varargin)
%LOOPBOUNDPADDINGPENALTY  Tier-1 Nmax-padding-penalty measurement (R17 item ii).
%
% The quantitative evidence the R6 deep-extension go/no-go is gated on
% (#73 / #6). A `loopbound` derivative is generated ONCE at N = Nmax and may be
% called with any runtime n <= Nmax (padded-program semantics); this measures
% what that padding COSTS versus a file regenerated at the exact n. For a
% subscripted (allocation-shaped) derivative the padded file carries Nmax-sized
% `static const` index tables regardless of n, so the penalty shows up in
% compiled ROM. That penalty is exactly what symbolic-N (Tier 2, #6) would
% remove: a large penalty at n << Nmax argues Tier 2 has value; a penalty that
% is small (or only near Nmax) argues defer.
%
%   report = loopboundPaddingPenalty('Name',value,...)
% Options (defaults in brackets):
%   Nmax    [64]                 generation-time max trip count.
%   nSweep  [[4 8 16 32 64]]     runtime sizes to compare against (<= Nmax).
%   DerType ['gradient']         'gradient' (loopbound Hessian errors at
%                                generation - the 2nd-derivative pass can't
%                                process the loopbound assert guard, #173).
%   reportPath ['']             write the markdown table here.
%   verbose [true]
%
% Returns .padded (the n-independent padded footprint), .rows (per-n exact
% footprint + ROM penalty), .table, .available (false -> everything skip-clean).
%
% Anchored on scostfun_lb (J = sum_{k=1:N} exp(x_k)+2 x_k), inline ('i') / ERT.
% Reuses measureErtFootprint (R17c / ADR-0027). Non-gating, heavyweight (each n
% is a Coder build). Skip-clean without MATLAB Coder / Embedded Coder.
%
% This measures FOOTPRINT only (it does not check numeric equivalence), so a
% green penalty is not a correctness signal - loopbound-gradient correctness is
% pinned separately by tests/integration/ILoopboundTest.m.
%
% Copyright GMV.  2026-07  (roadmap R17 Tier-1 padding penalty; issue #73/#6)
% Distributed under the GNU General Public License version 3.0
%
% see also derivShowcaseC, measureErtFootprint

p = inputParser; p.FunctionName = 'loopboundPaddingPenalty';
p.addParameter('Nmax',64,@(x)isnumeric(x)&&isscalar(x)&&x>=2);
p.addParameter('nSweep',[4 8 16 32 64],@(x)isnumeric(x)&&isvector(x));
p.addParameter('DerType','gradient',@(x)ischar(x)||isstring(x));
p.addParameter('reportPath','',@(x)ischar(x)||isstring(x));
p.addParameter('verbose',true,@(x)islogical(x)&&isscalar(x));
p.parse(varargin{:}); o = p.Results;
o.DerType = char(o.DerType);
o.nSweep  = sort(o.nSweep(o.nSweep <= o.Nmax));

cleanup = addPaths(); %#ok<NASGU>
report = struct('padded',[],'rows',[],'table','','available',true);
if isempty(which('codegen')) || ~license('test','MATLAB_Coder') || ...
        ~license('test','RTW_Embedded_Coder')
    report.available = false;
    if o.verbose; fprintf('loopboundPaddingPenalty: Coder/Embedded Coder absent - skipping.\n'); end
    return
end

wrapper = ['scostfun_lb_', derSuffix(o.DerType)];

% PADDED: generate once at Nmax with the runtime bound; footprint is n-independent
if o.verbose; fprintf('  building padded(Nmax=%d)...\n', o.Nmax); end
report.padded = buildFootprint(o.DerType, wrapper, o.Nmax, true);

% EXACT: regenerate at each n with a fixed bound
rows = struct('n',{},'rom',{},'ram',{},'stack',{},'romPenalty',{});
for n = o.nSweep
    if o.verbose; fprintf('  building exact(n=%d)...\n', n); end
    fp = buildFootprint(o.DerType, wrapper, n, false);
    romPen = NaN;
    if fp.rom > 0 && report.padded.rom > 0; romPen = report.padded.rom / fp.rom; end
    rows(end+1) = struct('n',n,'rom',fp.rom,'ram',fp.ram,'stack',fp.stack, ...
        'romPenalty',romPen); %#ok<AGROW>
end
report.rows  = rows;
report.table = renderTable(report.padded, rows, o);
if o.verbose; fprintf('\n%s\n', report.table); end
if ~isempty(o.reportPath); writelines(string(report.table), char(o.reportPath)); end
end

%% --------------------------------------------------------------------- %%
function fp = buildFootprint(DerType, wrapper, n, padded)
% Generate the derivative (loopbound at Nmax when padded, fixed at n otherwise)
% and measure the compiled ERT footprint of the core object.
fp = struct('rom',-1,'ram',-1,'stack',-1);
base = pwd; d = tempname; mkdir(d);
restore = onCleanup(@() cleanupDir(base,d));
try
    cd(d);
    gx = adigatorCreateDerivInput([n 1],'x');
    if padded
        opts = adigatorOptions('overwrite',1,'echo',0,'embed_mode','i','unroll',0,'loopbound','N');
    else
        opts = adigatorOptions('overwrite',1,'echo',0,'embed_mode','i','unroll',0);
    end
    adigatorGenDerFile_embedded(DerType, 'scostfun_lb', {gx, n}, opts);
    clear(wrapper); rehash;
    cfg = coder.config('lib','ecoder',true); cfg.GenerateReport = false;
    % x is a fixed-size vector; N is a RUNTIME scalar bound (the padded artifact
    % is called with any n at runtime).
    codegen(wrapper,'-config',cfg,'-args',{zeros(n,1), coder.typeof(0)},'-d','clib');
    fp = measureErtFootprint(fullfile(d,'clib'), wrapper);
catch e
    warning('loopboundPaddingPenalty:build','%s (n=%d, padded=%d): %s', ...
        DerType, n, padded, e.message);
end
cd(base);
end

%% --------------------------------------------------------------------- %%
function md = renderTable(padded, rows, o)
L = strings(0,1);
L(end+1) = string(sprintf("Loopbound padding penalty - %s of scostfun_lb (inline 'i', Nmax=%d, MATLAB R2024a + MinGW).", o.DerType, o.Nmax));
L(end+1) = string(sprintf("Padded(Nmax) footprint (n-independent): ROM=%s  RAM=%s  stack=%s bytes.", ...
    fmt(padded.rom), fmt(padded.ram), fmt(padded.stack)));
L(end+1) = "";
L(end+1) = "| n | exact ROM | exact RAM | exact stack | ROM penalty (padded/exact) |";
L(end+1) = "|---:|---:|---:|---:|---:|";
for k = 1:numel(rows)
    r = rows(k);
    pen = '—'; if ~isnan(r.romPenalty); pen = sprintf('%.1fx', r.romPenalty); end
    L(end+1) = string(sprintf("| %d | %s | %s | %s | %s |", ...
        r.n, fmt(r.rom), fmt(r.ram), fmt(r.stack), pen)); %#ok<AGROW>
end
md = char(strjoin(L, newline));
end

function s = fmt(v)
if v < 0; s = '—'; else; s = sprintf('%d', v); end
end

function s = derSuffix(dt)
switch dt
    case 'gradient';         s = 'Grd';
    case 'gradient-reverse'; s = 'RGrd';
    case 'hessian';          s = 'Hes';
    case 'jacobian';         s = 'Jac';
    otherwise; error('loopboundPaddingPenalty:derType','unsupported DerType %s',dt);
end
end

function cleanupDir(base,d)
cd(base);
try
    if isfolder(d); rmdir(d,'s'); end
catch
end
end

function c = addPaths()
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
saved = path;
addpath(root, fullfile(root,'lib'), fullfile(root,'lib','cadaUtils'), ...
    fullfile(root,'util'), fullfile(root,'embedding'), here, fullfile(here,'showcase'));
c = onCleanup(@() path(saved));
end
