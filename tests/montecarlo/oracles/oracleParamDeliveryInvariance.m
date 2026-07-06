function r = oracleParamDeliveryInvariance(c)
%ORACLEPARAMDELIVERYINVARIANCE  R27 Phase 1: same function, param delivered N ways.
%
% For a paramDelivery case (mcGenParamDelivery), re-emit the same bilinear
% function y = M*x + g*x with the parameters (M, g) delivered four ways and
% assert every delivery generates, runs, and yields the *identical* Jacobian
% (and matches the analytic M + g*I):
%   inlineStruct - a body-assigned constant struct   (the B17 shape)
%   auxStruct    - a struct auxiliary input           (R8)
%   auxSeparate  - separate matrix/scalar aux inputs
%   inlineCell   - a body-assigned constant cell      (the B22 shape)
% A delivery that crashes at generation or run time (as B17/B22 did before
% their fixes) breaks the invariant -- so this oracle is the tolerance-free
% backstop for that whole class (issue #103, ROADMAP R27). Classic mode is used
% here; embed modes emit cells/`load`/`global` verbatim and only warn about
% reduced embeddability (ADR-0023 rev 2026-07-04), so they would also generate.
%
% Copyright GMV. Distributed under the GNU General Public License v3.0.

r = struct('name', 'paramDelivery', 'pass', true, 'skipped', false, 'message', '');
if ~isfield(c, 'tags') || ~isfield(c.tags, 'gen') || ~strcmp(c.tags.gen, 'paramDelivery')
    r.skipped = true;
    r.message = 'not a paramDelivery case';
    return;
end

n = c.tags.n; M = c.tags.M; g = c.tags.g; x0 = c.x0;
Mstr = mat2str(M, 17); gstr = mat2str(g, 17);
Jref = M + g*eye(n);
base = pwd;

deliveries = {'inlineStruct', 'auxStruct', 'auxSeparate', 'inlineCell'};
Jfirst = [];
for k = 1:numel(deliveries)
    d = deliveries{k};
    fn = sprintf('%s_%s', c.name, d);
    [body, inputs, args] = buildDelivery(d, fn, Mstr, gstr, n, M, g, x0);
    writeFile(fn, body);
    md = fullfile(base, ['pd_' d]);
    try
        adigatorGenJacFile(fn, inputs, ...
            struct('embed_mode', 'c', 'path', md, 'echo', 0, 'overwrite', 1));
    catch e
        r.pass = false;
        r.message = sprintf('delivery ''%s'': generation failed: %s', d, oneline(e.message));
        return;
    end
    [Jk, ok, msg] = runIn(md, [fn '_Jac'], args);
    if ~ok
        r.pass = false;
        r.message = sprintf('delivery ''%s'': run failed: %s', d, msg);
        return;
    end
    if isempty(Jfirst); Jfirst = Jk; end
    % Bit-exact isequaln is valid because the Phase-1 bilinear body M*x + g*x
    % reorders no arithmetic across deliveries and 17-digit serialization
    % round-trips the inlined literal to the exact double. A future phase that
    % widens mcGenParamDelivery to bodies with summations that can reorder must
    % drop this to a tight tolerance for those cases (issue #103, Phase 2/3).
    if ~isequal(size(Jk), size(Jfirst)) || ~isequaln(Jk, Jfirst)
        r.pass = false;
        r.message = sprintf('delivery ''%s'' Jacobian differs from ''%s''', d, deliveries{1});
        return;
    end
    if max(abs(Jk(:) - Jref(:)), [], 'omitnan') > 1e-10
        r.pass = false;
        r.message = sprintf('delivery ''%s'' Jacobian differs from analytic M+g*I (max %.3g)', ...
            d, max(abs(Jk(:) - Jref(:)), [], 'omitnan'));
        return;
    end
end
end

% ---- helpers ----

function [body, inputs, args] = buildDelivery(which, fn, Mstr, gstr, n, M, g, x0)
switch which
    case 'inlineStruct'
        body = {['function y = ' fn '(x)'], ...
                sprintf('P = struct(''M'', %s, ''g'', %s);', Mstr, gstr), ...
                'y = P.M*x + P.g*x;', 'end'};
        inputs = {adigatorCreateDerivInput([n 1], 'x')};
        args = {x0};
    case 'auxStruct'
        body = {['function y = ' fn '(x, P)'], 'y = P.M*x + P.g*x;', 'end'};
        gp.M = adigatorCreateAuxInput([n n]);
        gp.g = adigatorCreateAuxInput([1 1]);
        inputs = {adigatorCreateDerivInput([n 1], 'x'), gp};
        args = {x0, struct('M', M, 'g', g)};
    case 'auxSeparate'
        body = {['function y = ' fn '(x, M, g)'], 'y = M*x + g*x;', 'end'};
        inputs = {adigatorCreateDerivInput([n 1], 'x'), ...
                  adigatorCreateAuxInput([n n]), adigatorCreateAuxInput([1 1])};
        args = {x0, M, g};
    case 'inlineCell'
        body = {['function y = ' fn '(x)'], ...
                sprintf('C = {%s, %s};', Mstr, gstr), ...
                'y = C{1}*x + C{2}*x;', 'end'};
        inputs = {adigatorCreateDerivInput([n 1], 'x')};
        args = {x0};
    otherwise
        error('oracleParamDeliveryInvariance:delivery', 'unknown delivery %s', which);
end
end

function writeFile(name, lines)
fid = fopen([name '.m'], 'w');
assert(fid > 0, 'could not create fixture %s', name);
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end

function [J, ok, msg] = runIn(md, wrapperName, args)
% Direct feval (not the harness mcEval): mcEval's classic-global-clear dance is
% unnecessary here -- each delivery's wrapper name is unique per delivery and
% per iteration, so its classic-mode data global cannot bleed across calls --
% and mcEval hard-codes a single-argument signature, so it cannot pass the aux
% arguments the auxStruct/auxSeparate deliveries need.
J = []; ok = true; msg = '';
base = pwd; cu = onCleanup(@() cd(base)); cd(md); rehash;
try
    J = feval(wrapperName, args{:});
catch e
    ok = false; msg = oneline(e.message);
end
end

function s = oneline(s)
s = regexprep(char(s), '\s+', ' ');
end
