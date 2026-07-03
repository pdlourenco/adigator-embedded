function adigatorScanEmbedUnsupported(filepath)
%ADIGATORSCANEMBEDUNSUPPORTED  Reject embed-incompatible source constructs.
%   adigatorScanEmbedUnsupported(FILEPATH) statically scans a user function
%   file and raises a clear, actionable error if it uses a construct that
%   cannot be made embeddable in the 'l'/'i' modes: **cell arrays**, **load**,
%   or **global** in the differentiated function.
%
%   In embed modes the generated derivative must be dependency-free and
%   embeddable (DESIGN.md Contract C-4). A user `load`/`global` is a runtime
%   dependency emitted verbatim (B21); a cell array is emitted verbatim and is
%   not an accepted embedded-C construct (B22). Rather than emit code that
%   breaks later at codegen/runtime, this pre-transformation gate fails fast at
%   generation time, naming the file and line. Classic mode ('c') never calls
%   this gate. (ADR-0023; docs/ANALYSIS.md B21/B22.)
%
%   Detection is AST-based (mtree), so occurrences inside comments or strings
%   do not false-trigger. A file that mtree cannot parse is skipped here and
%   left for the core's own error reporting.
%
% Copyright GMV. Distributed under the GNU General Public License v3.0.

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

error('adigator:embed:unsupportedConstruct', ...
    ['Embedded modes (''l''/''i'') do not support cell arrays, ''load'', or ' ...
     '''global'' in the differentiated function, but ''%s%s'' uses:\n%s\n' ...
     'Pass parameters as struct or numeric inputs (pre-load any data and ' ...
     'pass it in as an auxiliary input), or generate in classic mode ' ...
     '(embed_mode=''c'').'], ...
    fname, fext, strjoin(items, newline));
end
