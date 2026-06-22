function cmin = mcShrink(c, oracles)
%MCSHRINK  Delta-debug a failing case to a smaller still-failing one.
%
% Turns a random failure into a minimal reproducer (ADR-0007). The reduction
% is greedy entry-dropping on the `y = [e1; e2; ...; ek];` output-vector
% shape (the expression-tree-like generators): each output entry is removed
% in turn and the reduction is kept whenever the case still fails. Cases
% whose body is not an output-vector list (e.g. affine `y = A*x+b`) are
% returned unchanged — the original failing case is still promoted.
cmin = c;
if ~caseFails(cmin, oracles)
    return;   % nothing to shrink (defensive: only called on failures)
end

entries = parseVectorEntries(cmin.body);
if isempty(entries) || numel(entries) < 2
    return;   % not an output-vector list, or already minimal
end

changed = true;
while changed && numel(entries) > 1
    changed = false;
    for k = 1:numel(entries)
        trial = entries; trial(k) = [];
        cand = withEntries(cmin, trial);
        if caseFails(cand, oracles)
            cmin = cand;
            entries = trial;
            changed = true;
            break;   % restart the sweep on the reduced case
        end
    end
end
end

function tf = caseFails(c, oracles)
res = mcRunCase(c, oracles);
tf = ~res.pass;
end

function e = parseVectorEntries(body)
% Return the entries of a single-line `y = [ ... ];` body as a cellstr, or
% {} if the body is not of that shape.
e = {};
if iscell(body)
    if numel(body) ~= 1, return; end
    line = body{1};
else
    line = char(body);
end
tok = regexp(strtrim(line), '^y\s*=\s*\[(.*)\]\s*;?$', 'tokens', 'once');
if isempty(tok), return; end
parts = strsplit(tok{1}, ';');
e = strtrim(parts);
e = e(~cellfun(@isempty, e));
end

function cc = withEntries(c, entries)
% Rebuild a case from a reduced entry list, keeping it consistent.
m = numel(entries);
body = sprintf('y = [%s];', strjoin(entries, '; '));
tags = c.tags;
if isfield(tags, 'outShape'); tags.outShape = [m 1]; end
base = regexprep(c.name, '(_s)+$', '');   % one stable suffix, not _s_s_s...
cc = mcCase('name', [base '_s'], 'body', body, 'xsize', c.xsize, ...
    'deriv', c.deriv, 'x0', c.x0, ...
    'exactJac', c.exactJac, 'exactHess', c.exactHess, 'tags', tags);
end
