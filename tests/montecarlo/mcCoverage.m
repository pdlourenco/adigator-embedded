function cov = mcCoverage(tagsList)
%MCCOVERAGE  Summarize which (gen × shapes × density × order) tuples a campaign
%            exercised (ADR-0007 Phase B; ANALYSIS coverage of the test axes).
%
%   cov = mcCoverage(tagsList)  where tagsList is a cell array of case .tags
%   structs (mcCampaign collects one per iteration). Returns:
%     cov.keys      - 1xK cellstr of the distinct axis tuples seen
%     cov.counts    - 1xK hit count per tuple
%     cov.nDistinct - K
%     cov.total     - numel(tagsList)
%
% The axis tuple is gen | order | density | inShapeClass | outShapeClass, so a
% campaign report shows whether the generators are actually spreading across
% the dimension space rather than re-drawing the same shape.
if nargin < 1 || isempty(tagsList)
    cov = struct('keys',{{}}, 'counts',[], 'nDistinct',0, 'total',0);
    return;
end

keys = cellfun(@coverageKey, tagsList, 'UniformOutput', false);
[u, ~, ic] = unique(keys);
counts = accumarray(ic(:), 1).';

cov = struct();
cov.keys = u(:).';
cov.counts = counts;
cov.nDistinct = numel(u);
cov.total = numel(tagsList);
end

function k = coverageKey(t)
gen     = field(t, 'gen', 'unknown');
order   = field(t, 'order', NaN);
density = field(t, 'density', 'unknown');
inCls   = shapeClass(field(t, 'inShape', []));
outCls  = shapeClass(field(t, 'outShape', []));
k = sprintf('%s|ord%g|%s|in:%s|out:%s', gen, order, density, inCls, outCls);
end

function v = field(s, f, d)
if isstruct(s) && isfield(s, f) && ~isempty(s.(f)); v = s.(f); else; v = d; end
end

function cls = shapeClass(sz)
if numel(sz) ~= 2
    cls = 'unknown'; return;
end
r = sz(1); c = sz(2);
if r == 1 && c == 1
    cls = 'scalar';
elseif c == 1
    cls = 'col';
elseif r == 1
    cls = 'row';
else
    cls = 'matrix';
end
end
