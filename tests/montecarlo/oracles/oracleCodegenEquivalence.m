function r = oracleCodegenEquivalence(c)
%ORACLECODEGENEQUIVALENCE  Compiled-C == MATLAB over a random case (ADR-0014, R15).
%
% The codegen-equivalence oracle for the #38 Monte-Carlo campaign (issue #64).
% For case c it generates the embedded inline ('i') wrapper, then:
%   - born ERT (R20c): builds it through Embedded Coder
%     (coder.config('lib','ecoder',true)) to prove it code-generates under the
%     STRICT target -- the same target the campaign must clear, not plain Coder
%     which tolerates ERT-illegal patterns and masked real gaps;
%   - builds a MEX and asserts the compiled result equals the MATLAB
%     (interpreted) wrapper over c.x0 plus a few perturbations.
%
% This adds compiled-C == MATLAB over the RANDOMIZED battery -- the
% embedded-target trust #38 exists to build. The cross-mode oracle only compares
% embed modes interpreter-only (never invokes Coder), so before this the only
% place generated C was exercised was the single pipg fixture in TS-S-02.
%
% Skip-clean (mirrors oracleCrossMode's coder.* discipline): skips when MATLAB
% Coder is unavailable; the born-ERT lib build additionally needs Embedded Coder
% (a Coder-only machine still checks the MEX equivalence). EXPENSIVE (one or two
% codegen builds), so this is a SAMPLED / release-checklist oracle -- opt in
% explicitly (it is NOT in the mcCampaign default oracle set), never on every
% seed.
r = struct('name','codegenEquiv','pass',true,'skipped',false,'message','');

if ~license('test','MATLAB_Coder') || isempty(which('codegen'))
    r.skipped = true; r.message = 'skipped (no MATLAB Coder)'; return;
end

switch c.deriv
    case 'jacobian', suffix = '_Jac'; nout = 2;
    case 'gradient', suffix = '_Grd'; nout = 2;
    case 'hessian',  suffix = '_Hes'; nout = 3;
    otherwise
        error('oracleCodegenEquivalence:deriv','unsupported deriv "%s"', c.deriv);
end
wrapperName = [c.name suffix];

% generate the embedded inline wrapper in the (fresh, fixture-holding) cwd
ax = adigatorCreateDerivInput(c.xsize, 'x');
opts = struct('embed_mode','i','path',pwd,'echo',0,'overwrite',1);
adigatorGenDerFile_embedded(c.deriv, c.name, {ax}, opts);
rehash;
if ~isfile([wrapperName '.m'])
    r.pass = false;
    r.message = sprintf('inline wrapper %s not generated', wrapperName);
    return;
end

args = {zeros(c.xsize)};

% --- born ERT: prove it code-generates under strict Embedded Coder --- %
% Gate on license('checkout',...), NOT license('test',...): the latter misreports
% (returns 0) for a checkout-required product inside a test-method body -- the
% SCodegenTest M16 trap -- which would silently skip the born-ERT proof and pass
% MEX-only. 'checkout' is reliable in a body (and codegen checks the license out
% anyway); the whole point of this oracle is the strict ERT target, so a false
% skip must not go unnoticed.
if license('checkout','RTW_Embedded_Coder')
    try
        cfg = coder.config('lib','ecoder',true);
        cfg.GenerateReport = false;
        codegen(wrapperName, '-config', cfg, '-args', args, '-d', 'cg_ert');
    catch e
        r.pass = false;
        r.message = sprintf('ERT lib codegen failed: %s', e.message);
        return;
    end
    if ~isfolder('cg_ert')
        r.pass = false; r.message = 'ERT lib codegen produced no output'; return;
    end
end

% --- MEX build + execution equivalence: compiled == interpreted --- %
try
    codegen(wrapperName, '-args', args, '-d', 'cg_mex');
catch e
    r.pass = false;
    r.message = sprintf('MEX codegen failed: %s', e.message);
    return;
end
rehash;
mexName = [wrapperName '_mex'];
releaseMex = onCleanup(@() clear(mexName));   % unlock the MEX before teardown

% test points: c.x0 plus a few perturbations (kept near the generator's valid
% point so domain-restricted random functions do not leave their domain). A
% LOCAL stream is used so this oracle does not clobber the global RNG for a
% later RNG-dependent oracle in a multi-oracle release sweep.
rs = RandStream('twister','Seed',20240709);
pts = {c.x0, c.x0 + 0.1*randn(rs, c.xsize), c.x0 - 0.1*randn(rs, c.xsize)};
for p = 1:numel(pts)
    xv = pts{p};
    outM = cell(1,nout); [outM{:}] = feval(wrapperName, xv);   % MATLAB
    outX = cell(1,nout); [outX{:}] = feval(mexName, xv);       % compiled
    for j = 1:nout
        a = double(outM{j}); b = double(outX{j});
        % compiled == interpreted: same shape, MATCHING NaN pattern (so two
        % all-NaN outputs from a domain escape cannot mask a divergence), and
        % equal to machine precision on the finite entries (abs + rel).
        if ~isequal(size(a), size(b)) || ~isequal(isnan(a), isnan(b))
            r.pass = false;
            r.message = sprintf('point %d output %d: shape/NaN-pattern differs', p, j);
            return;
        end
        fin = ~isnan(a);
        if any(fin(:))
            d = max(abs(a(fin) - b(fin)));
            if d > 1e-12 + 1e-12*max(abs(b(fin)))
                r.pass = false;
                r.message = sprintf(...
                    'point %d output %d: compiled != MATLAB (max abs %.3g)', p, j, d);
                return;
            end
        end
    end
end
end
