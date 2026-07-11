function r = oracleDerOutputInvariance(c)
%ORACLEDEROUTPUTINVARIANCE  R27 Phase 2: der_output {matrix,nonzeros} identity.
%
% For a jacobian case, generate the wrapper in the default dense-matrix form and
% in the jac_output='nonzeros' form, then assert that scattering the returned
% nonzero vector into output.JacobianLocs reconstructs the *exact* dense
% Jacobian (and the function values agree). This covers the der_output option
% axis -- a real option the body-only Monte-Carlo battery never swept (issue
% #103, ROADMAP R27 Phase 2). Interpreter-only (classic wrappers), no Coder.
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public License v3.0.

r = struct('name', 'derOutput', 'pass', true, 'skipped', false, 'message', '');
if ~strcmp(c.deriv, 'jacobian')
    r.skipped = true;
    r.message = 'derOutput invariance: jacobian only';
    return;
end

base = pwd;
mdM = fullfile(base, 'do_matrix');
mdN = fullfile(base, 'do_nz');
fnN = [c.name '_nz'];
% Identical body, distinct name -> distinct classic-mode data global, so the
% two wrappers do not clobber each other (mirrors IOutputModesTest's two files).
writeFixtureFile(fnN, c.body);

try
    adigatorGenJacFile(c.name, {adigatorCreateDerivInput(c.xsize, 'x')}, ...
        struct('overwrite', 1, 'echo', 0, 'path', mdM));
    outN = adigatorGenJacFile(fnN, {adigatorCreateDerivInput(c.xsize, 'x')}, ...
        struct('overwrite', 1, 'echo', 0, 'path', mdN, 'jac_output', 'nonzeros'));
catch e
    r.pass = false;
    r.message = sprintf('generation failed: %s', oneline(e.message));
    return;
end

[JM, FM, okM, mM] = runIn(mdM, [c.name '_Jac'], c.x0);
[vals, FN, okN, mN] = runIn(mdN, [fnN '_Jac'], c.x0);
if ~okM
    r.pass = false; r.message = sprintf('matrix wrapper run failed: %s', mM); return;
end
if ~okN
    r.pass = false; r.message = sprintf('nonzeros wrapper run failed: %s', mN); return;
end

% the two forms are the same computation, so the function value must agree
if ~isequaln(FM, FN)
    r.pass = false;
    r.message = 'function value differs between matrix and nonzeros forms';
    return;
end

JM = full(JM);
locs = outN.JacobianLocs;
if size(locs, 1) ~= numel(vals)
    r.pass = false;
    r.message = sprintf('nonzeros count %d ~= JacobianLocs rows %d', numel(vals), size(locs, 1));
    return;
end
JS = zeros(size(JM));
if ~isempty(vals)
    JS(sub2ind(size(JM), locs(:, 1), locs(:, 2))) = vals(:);
end
if ~isequaln(JS, JM)   % isequaln also fails on a size mismatch
    r.pass = false;
    r.message = sprintf('nonzeros reconstruction differs from matrix form (max %.3g)', ...
        maxAbsDiff(JS, JM));
    return;
end
end

% ---- helpers ----

function [d, fun, ok, msg] = runIn(md, wrapperName, x)
% Direct feval into the mode dir (distinct wrapper/global names per form, so no
% classic-global bleed); cwd restored on every path. Returns the derivative
% output (dense Jacobian or nonzero vector) and the function value.
d = []; fun = []; ok = true; msg = '';
base = pwd; cu = onCleanup(@() cd(base)); cd(md); rehash;
try
    [d, fun] = feval(wrapperName, x);
catch e
    ok = false; msg = oneline(e.message);
end
end

function v = maxAbsDiff(a, b)
if isequal(size(a), size(b))
    v = max(abs(a(:) - b(:)), [], 'omitnan');
else
    v = NaN;
end
end

function s = oneline(s)
s = regexprep(char(s), '\s+', ' ');
end
