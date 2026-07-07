function r = oracleCrossMode(c)
%ORACLECROSSMODE  Embed-mode invariants + exact cross-mode equality (ADR-0007).
%
% Generates case c in embed_mode 'c'/'l'/'i' (assumed: cwd is a fresh working
% dir holding the fixture), checks the static embeddability invariants of
% REQ-T-04 on the 'l'/'i' source, and asserts the three modes return
% bit-identical results. The static checks run on base MATLAB; the numeric
% cross-comparison of 'l'/'i' needs the coder.* namespace (MATLAB Coder) and
% is skipped cleanly when it is unavailable (then only 'c' is evaluated and
% the static invariants still gate).
r = struct('name','crossMode','pass',true,'skipped',false,'message','');

switch c.deriv
    case 'jacobian', suffix = '_Jac'; nout = 2;
    case 'gradient', suffix = '_Grd'; nout = 2;
    case 'hessian',  suffix = '_Hes'; nout = 3;
    otherwise, error('oracleCrossMode:deriv', 'unsupported deriv "%s"', c.deriv);
end
wrapperFile = [c.name suffix '.m'];
wrapperName = [c.name suffix];

base = pwd;
modes = {'c','l','i'};
dirOf = struct();
for k = 1:numel(modes)
    md = fullfile(base, ['mode_' modes{k}]);
    dirOf.(modes{k}) = md;
    ax = adigatorCreateDerivInput(c.xsize, 'x');
    opts = struct('embed_mode', modes{k}, 'path', md, 'echo', 0, 'overwrite', 1);
    adigatorGenDerFile_embedded(c.deriv, c.name, {ax}, opts);
    if ~isfile(fullfile(md, wrapperFile))
        r.pass = false;
        r.message = sprintf('mode %s: wrapper %s not generated', modes{k}, wrapperFile);
        return;
    end
end

% ---- static embeddability invariants (REQ-T-04), base MATLAB ---- %
txtL = readlines(fullfile(dirOf.l, wrapperFile));
[r.pass, r.message] = checkAll(r, ...
    any(contains(txtL,'persistent ADiGator_')), 'mode l: persistent missing', ...
    any(contains(txtL,'coder.load(')),          'mode l: coder.load missing', ...
    ~any(startsWith(strtrim(txtL),'global ')),   'mode l: global left in', ...
    ~any(contains(txtL,'ADiGator_LoadData')),    'mode l: runtime loader left in', ...
    ... % M15 (REQ-T-04): a bare load( (not coder.load) is a runtime dependency
    ~any(~cellfun(@isempty, regexp(txtL,'(?<!coder\.)\<load\(','once'))), 'mode l: bare load( survives');
if ~r.pass, return; end

txtI = readlines(fullfile(dirOf.i, wrapperFile));
[r.pass, r.message] = checkAll(r, ...
    any(contains(txtI,'coder.const(')),       'mode i: coder.const missing', ...
    ~any(startsWith(strtrim(txtI),'global ')), 'mode i: global left in', ...
    ~any(contains(txtI,'ADiGator_LoadData')),  'mode i: runtime loader left in', ...
    ~any(contains(txtI,'coder.load(')),        'mode i: coder.load present (data not inlined)', ...
    isempty(dir(fullfile(dirOf.i,'*.mat'))),   'mode i: .mat left behind');
if ~r.pass, return; end

% ---- numeric cross-mode equality (exact); 'c' always, 'l'/'i' Coder-gated ---- %
outC = evalIn(dirOf.c, wrapperName, nout, c.x0);   % classic must run
for k = 2:numel(modes)
    m = modes{k};
    try
        outM = evalIn(dirOf.(m), wrapperName, nout, c.x0);
    catch e
        if strcmp(e.identifier,'MATLAB:UndefinedFunction') && contains(e.message,'coder.')
            r.skipped = true;   % static invariants passed; numeric needs Coder
            r.message = 'l/i numeric check skipped (no MATLAB Coder)';
            continue;
        end
        rethrow(e);
    end
    for j = 1:nout
        if ~isequaln(outM{j}, outC{j})
            r.pass = false;
            r.message = sprintf('mode %s output %d differs from classic (max abs %.3g)', ...
                m, j, maxAbs(outM{j}, outC{j}));
            return;
        end
    end
end
end

function out = evalIn(d, wrapperName, nout, x)
old = cd(d); restore = onCleanup(@() cd(old)); %#ok<NASGU>
out = mcEval(wrapperName, nout, x);
end

function v = maxAbs(a, b)
if isequal(size(a), size(b))
    v = max(abs(a(:)-b(:)), [], 'omitnan');
else
    v = NaN;
end
end

function [ok, msg] = checkAll(r, varargin)
% varargin: cond1, msg1, cond2, msg2, ...  -> first failing message
ok = r.pass; msg = r.message;
for i = 1:2:numel(varargin)
    if ~varargin{i}
        ok = false; msg = varargin{i+1}; return;
    end
end
end
