function adigatorScanEmbedUnsupported(filepath)
%ADIGATORSCANEMBEDUNSUPPORTED  Warn on embed-incompatible source constructs.
%   adigatorScanEmbedUnsupported(FILEPATH) statically scans a user function
%   file and raises a WARNING if it uses a construct that reduces the
%   embeddability of the 'l'/'i' output: **cell arrays**, **load**, or
%   **global** in the differentiated function. It does not stop
%   differentiation -- the construct is emitted verbatim into the derivative
%   file exactly as classic mode does.
%
%   Embed modes aim for dependency-free, embeddable output (DESIGN.md Contract
%   C-4), but embed is *no more restrictive than classic*: a user may use a
%   `load`/`global`/cell provisionally and make both the original and the
%   derivative embeddable later. So this gate only flags the reduced
%   embeddability (the generated file is not self-contained and may not
%   code-generate until the construct is removed), naming the file and line,
%   and lets generation proceed. Constructs that classic itself rejects (bare
%   `load(...)`, unsupported cell patterns) still error from the core
%   downstream, unchanged -- this scan neither adds a gate beyond classic's nor
%   suppresses classic's own errors. Classic mode ('c') never calls this scan.
%   (ADR-0023 rev 2026-07-04; docs/ANALYSIS.md B21/B22.)
%
%   Detection is AST-based (mtree), so occurrences inside comments or strings
%   do not false-trigger. A file that mtree cannot parse is skipped here and
%   left for the core's own error reporting.
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public License v3.0.

try
    t = mtree(filepath, '-file');
catch
    return  % unparseable here; let the core parser report it
end
if count(t) == 0 || ~isempty(indices(mtfind(t, 'Kind', 'ERR')))
    return
end

lines = zeros(0, 1);
kinds = cell(0, 1);

% Cell arrays: literal `{...}` (LC) or index `x{i}` (CELL).
cn = mtfind(t, 'Kind', {'LC', 'CELL'});
for i = indices(cn)
    lines(end+1, 1) = lineno(select(cn, i)); %#ok<AGROW>
    kinds{end+1, 1} = 'cell array';          %#ok<AGROW>
end

% `global` statements.
gn = mtfind(t, 'Kind', 'GLOBAL');
for i = indices(gn)
    lines(end+1, 1) = lineno(select(gn, i)); %#ok<AGROW>
    kinds{end+1, 1} = 'global';              %#ok<AGROW>
end

% `load`: function call `load(...)` (CALL) or command form `load ...` (DCALL),
% identified by the leftmost identifier being `load`.
ln = mtfind(t, 'Kind', {'CALL', 'DCALL'});
for i = indices(ln)
    nd = select(ln, i);
    L  = Left(nd);
    if ~isempty(L) && strcmp(kind(L), 'ID') && strcmp(string(L), 'load')
        lines(end+1, 1) = lineno(nd);  %#ok<AGROW>
        kinds{end+1, 1} = 'load';      %#ok<AGROW>
    end
end

if isempty(lines)
    return
end

[lines, order] = sort(lines);
kinds = kinds(order);
[~, fname, fext] = fileparts(filepath);
items = cell(numel(lines), 1);
for k = 1:numel(lines)
    items{k} = sprintf('    %s (line %d)', kinds{k}, lines(k));
end

warning('adigator:embed:unsupportedConstruct', ...
    ['Embedded modes (''l''/''i'') emit cell arrays, ''load'', and ''global'' ' ...
     'verbatim (as classic mode), so the derivative generated from ''%s%s'' is ' ...
     'not self-contained and may not code-generate until these are removed:\n%s\n' ...
     'To make it embeddable, pass parameters as struct or numeric inputs ' ...
     '(pre-load any data and pass it in as an auxiliary input). Generation ' ...
     'continues.'], ...
    fname, fext, strjoin(items, newline));
end
