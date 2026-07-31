function report = measureStackScaling(varargin)
%MEASURESTACKSCALING  Generated-derivative stack, against the hand-written cost.
%
%   report = measureStackScaling('Name',value,...)
%
% The missing half of REQ-T-10. ERT code generation succeeding is *necessary but
% not sufficient* for embeddability: `EnableDynamicMemoryAllocation=false`
% rejects only *unbounded* sizes, so a **bounded-but-large** derivative
% code-generates cleanly and then overflows the target's stack at run time (the
% "hollow milestone", ADR-0019 / ADR-0033).
%
% The property measured is **generated stack ÷ the stack a hand-written
% derivative of the same function needs** (ADR-0035), across a size sweep.
%
% Why a ratio against hand-written code, and not "the stack must be flat":
% *a growing stack is normal*. A Hessian's answer is n×n; even the optimal
% hand-written `Hes = diag(exp(x))` grows (measured exponent ≈0.6), because
% temporaries scale even when the output goes to the caller's buffer. A flatness
% gate would fail correct, optimal code. And not an absolute byte ceiling
% either: this project declares no target device, so any ceiling would be
% invented and would quietly become policy.
%
% The ratio isolates what this project is actually responsible for — the
% overhead the *generator* adds over what the derivative's own shape costs —
% and is target-independent.
%
% Options (defaults in brackets):
%   Anchor    ['scostfun']       function to differentiate (on bench/showcase).
%   DerType   ['gradient']       'gradient' | 'hessian' | 'jacobian' | 'gradient-reverse'.
%   Reference ['']               hand-written derivative of the SAME MATHS
%                                (bench/showcase/analytic). Empty -> absolute
%                                scaling only, no overhead verdict.
%   Sizes     [[8 16 32]]        problem sizes; >= 2 required.
%   Unroll    [0]                0 = rolled (the embeddable form).
%   Tol       [4]                max allowed generated/reference stack ratio.
%   verbose   [true]
%
% Returns .sizes/.stack/.refStack/.rom (bytes, -1 unmeasured), .overhead
% (per-size ratio), .maxOverhead, .trend ('converging'|'diverging'|'flat'),
% .ok, .available (false -> Coder absent, skip-clean).
%
% **.trend is reported, not asserted.** A ratio that is high but *shrinking*
% with n is a constant-factor cost; one that is low but *growing* is an
% asymptotic gap that will matter at a size nobody has measured yet. The gate
% asserts the value; a human reads the direction.
%
% Reuses measureErtFootprint (ADR-0027) and the strict shared config
% (adigatorCoderConfig, ADR-0033), so the artifact measured is the artifact the
% gate demands. LOCAL ONLY - hosted CI licenses neither Coder nor Embedded
% Coder (CI_PLAN.md §3.2). The gate is tests/system/SStackScalingTest.m.
%
% Copyright Pedro Lourenço and GMV.  2026-07  (#80a-2, ADR-0035)
% Distributed under the GNU General Public License version 3.0
%
% see also measureErtFootprint, adigatorCoderConfig, derivShowcaseC

p = inputParser; p.FunctionName = 'measureStackScaling';
p.addParameter('Anchor','scostfun',@(x)ischar(x)||isstring(x));
p.addParameter('DerType','gradient',@(x)ischar(x)||isstring(x));
p.addParameter('Reference','',@(x)ischar(x)||isstring(x));
p.addParameter('Sizes',[8 16 32],@(x)isnumeric(x)&&numel(x)>=2);
p.addParameter('Unroll',0,@(x)isnumeric(x)&&isscalar(x));
p.addParameter('Tol',4,@(x)isnumeric(x)&&isscalar(x)&&x>=1);
p.addParameter('verbose',true,@(x)islogical(x)&&isscalar(x));
p.parse(varargin{:}); o = p.Results;
o.Anchor = char(o.Anchor); o.DerType = char(o.DerType); o.Reference = char(o.Reference);
o.Sizes  = sort(o.Sizes(:).');

cleanup = addPaths(); %#ok<NASGU>
nS = numel(o.Sizes);
report = struct('sizes',o.Sizes,'stack',-ones(1,nS),'refStack',-ones(1,nS), ...
    'rom',-ones(1,nS),'overhead',nan(1,nS),'maxOverhead',NaN,'trend','', ...
    'ok',false,'available',true,'anchor',o.Anchor,'derType',o.DerType, ...
    'reference',o.Reference);

if isempty(which('codegen')) || ~license('test','MATLAB_Coder') || ...
        ~license('test','RTW_Embedded_Coder')
    report.available = false;
    if o.verbose; fprintf('measureStackScaling: Coder/Embedded Coder absent - skipping.\n'); end
    return
end

wrapper = [o.Anchor '_' derSuffix(o.DerType)];
for k = 1:nS
    n = o.Sizes(k);
    if o.verbose; fprintf('  %s %s n=%d...\n', o.Anchor, o.DerType, n); end
    fp = buildGenerated(o.Anchor, o.DerType, wrapper, n, o.Unroll);
    report.stack(k) = fp.stack; report.rom(k) = fp.rom;
    if ~isempty(o.Reference)
        report.refStack(k) = buildPlain(o.Reference, n).stack;
    end
end

good = report.stack > 0;
if nnz(good) < 2
    % Toolchain present but the artifact did not build/measure. Not a pass and
    % not a clean skip - say so rather than returning a vacuous ok.
    if o.verbose
        fprintf('measureStackScaling: <2 sizes measured for %s %s - no verdict.\n', ...
            o.Anchor, o.DerType);
    end
    return
end

if isempty(o.Reference)
    % No reference: report absolute scaling only, no embeddability verdict.
    report.trend = 'n/a (no reference)';
    if o.verbose
        fprintf('\n%s %s: stack %s over n = %s (no reference given)\n', ...
            o.Anchor, o.DerType, mat2str(report.stack), mat2str(o.Sizes));
    end
    return
end

pair = good & report.refStack > 0;
if nnz(pair) < 2
    if o.verbose
        fprintf('measureStackScaling: reference %s did not measure - no verdict.\n', o.Reference);
    end
    return
end
report.overhead(pair) = report.stack(pair) ./ report.refStack(pair);
report.maxOverhead    = max(report.overhead(pair));
report.ok             = report.maxOverhead <= o.Tol;
report.trend          = overheadTrend(report.overhead(pair));

if o.verbose
    fprintf('\n%s %s (unroll=%d) vs %s, n = %s\n', ...
        o.Anchor, o.DerType, o.Unroll, o.Reference, mat2str(o.Sizes));
    fprintf('  generated stack : %s\n', mat2str(report.stack));
    fprintf('  hand-written    : %s\n', mat2str(report.refStack));
    fprintf('  overhead        : %s   (max %.2fx, tolerance %gx)\n', ...
        mat2str(round(report.overhead,2)), report.maxOverhead, o.Tol);
    fprintf('  verdict         : %s, %s\n', ...
        ternary(report.ok,'WITHIN TOLERANCE','OVER TOLERANCE'), report.trend);
    if strcmp(report.trend,'diverging')
        fprintf(['  NOTE: the ratio GROWS with n - a constant-factor gap would ', ...
                 'shrink or hold.\n        This is an asymptotic gap; the value ', ...
                 'passing today says little about larger n.\n']);
    end
end
end

%% --------------------------------------------------------------------- %%
function t = overheadTrend(v)
% Direction of the ratio across the sweep - reported, never asserted.
if numel(v) < 2 || v(1) <= 0; t = 'flat'; return; end
r = v(end)/v(1);
if     r > 1.15; t = 'diverging';
elseif r < 0.87; t = 'converging';
else;            t = 'flat';
end
end

function fp = buildGenerated(anchor, DerType, wrapper, n, unroll)
fp = struct('rom',-1,'ram',-1,'stack',-1);
base = pwd; d = tempname; mkdir(d);
restore = onCleanup(@() cleanupDir(base,d)); %#ok<NASGU>
try
    cd(d);
    adigatorGenDerFile_embedded(DerType, anchor, ...
        {adigatorCreateDerivInput([n 1],'x')}, ...
        adigatorOptions('overwrite',1,'echo',0,'embed_mode','i', ...
                        'unroll',unroll,'slim_embed',1));
    clear(wrapper); rehash;
    fp = ertFootprint(wrapper, n, d);
catch e
    warning('measureStackScaling:build','%s %s n=%d: %s', anchor, DerType, n, e.message);
end
cd(base);
end

function fp = buildPlain(fn, n)
% the hand-written reference: an ordinary MATLAB function, same pipeline
fp = struct('rom',-1,'ram',-1,'stack',-1);
base = pwd; d = tempname; mkdir(d);
restore = onCleanup(@() cleanupDir(base,d)); %#ok<NASGU>
try
    cd(d);
    fp = ertFootprint(fn, n, d);
catch e
    warning('measureStackScaling:reference','%s n=%d: %s', fn, n, e.message);
end
cd(base);
end

function fp = ertFootprint(fn, n, d)
cfg = adigatorCoderConfig();      % strict shared ERT profile (ADR-0033)
cfg.GenerateReport = false;
codegen(fn,'-config',cfg,'-args',{zeros(n,1)},'-d','clib');
fp = measureErtFootprint(fullfile(d,'clib'), fn);
end

function s = derSuffix(dt)
switch dt
    case 'gradient';         s = 'Grd';
    case 'gradient-reverse'; s = 'RGrd';
    case 'hessian';          s = 'Hes';
    case 'jacobian';         s = 'Jac';
    otherwise; error('measureStackScaling:derType','unsupported DerType %s',dt);
end
end

function out = ternary(c,a,b)
if c; out = a; else; out = b; end
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
    fullfile(root,'util'), fullfile(root,'embedding'), ...
    here, fullfile(here,'showcase'), fullfile(here,'showcase','analytic'));
c = onCleanup(@() path(saved));
end
