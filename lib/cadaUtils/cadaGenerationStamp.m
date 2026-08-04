function stamp = cadaGenerationStamp(versionStr, opts, sourcePaths)
%CADAGENERATIONSTAMP  Provenance stamp for a generated file (issue #200).
%
%   stamp = cadaGenerationStamp(version, opts, sourcePaths)
%
% Returns a struct with
%   .id       16 hex digits identifying this generation
%   .when     ISO 8601 UTC timestamp
%   .version  the tool version it was generated with
%
% WHAT THE ID COVERS, and why each part is there:
%   the tool version         - a different engine emits different code
%   emission-affecting opts  - the same source with different options is a
%                              different artifact
%   the CONTENT of every source file in the dependency closure - so the stamp
%                              moves when the differentiated function does
%
% Every file of one generation carries the same id, so a mismatch across a
% derivative / .mat / data-function triplet means mixed vintages - the failure
% mode ANALYSIS §2.4(10) names, which bites once generated files are committed
% into a firmware repository.
%
% Three design points that are not obvious:
%
%   CONTENT, NEVER PATHS. Two users generating from the same sources on
%   different machines must get the same id, or it certifies nothing about a
%   file committed into a repository. Absolute paths differ per machine.
%
%   NORMALISED AND SORTED. Line endings and trailing whitespace are stripped
%   and the closure is sorted, so the id does not move for reasons that do not
%   change the derivative. Line endings especially: the tree is LF since #212,
%   but a contributor's editor is not a reason to invalidate a stamp.
%
%   PURE MATLAB. FNV-1a below, not Java, not a toolbox, not an undocumented
%   internal - so the id is identical on the R2022a floor and on latest. It is
%   a staleness fingerprint, not a security digest; collision resistance beyond
%   "different inputs look different" is not required.
%
% WHAT IT DOES NOT DETECT: hand-edits to the generated file itself. That needs
% a self-hash of the file minus its own stamp line. "GENERATED FILE - do not
% edit" is therefore advisory, not checkable; do not read the id as a tamper
% seal.
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

if nargin < 3 || isempty(sourcePaths); sourcePaths = {}; end
if ischar(sourcePaths); sourcePaths = {sourcePaths}; end

parts = {char(versionStr), optionsSignature(opts)};

src = cell(1, numel(sourcePaths));
for k = 1:numel(sourcePaths)
    src{k} = normaliseSource(readIfPossible(sourcePaths{k}));
end
src = src(~cellfun(@isempty, src));

stamp = struct( ...
    'id',      cadaFnv1a64(strjoin([parts, sort(src)], char(31))), ...
    'when',    isoNowUTC(), ...
    'version', char(versionStr));
end

%% ---------------------------------------------------------------------- %%
function s = readIfPossible(p)
% A source that cannot be read contributes nothing rather than throwing: the
% stamp is provenance, and failing a generation over it would be the wrong
% trade. It still changes the id, because the file's content is then absent
% from the input.
s = '';
try
    if ~isempty(p) && isfile(p); s = fileread(p); end
catch
end
end

function s = normaliseSource(s)
if isempty(s); return; end
s = regexprep(s, sprintf('\r\n?'), newline);   % endings
s = regexprep(s, '[ \t]+\n', newline);         % trailing whitespace
s = regexprep(s, '[ \t]+$', '');               % ...including on a file with no
                                               % final newline, which the line
                                               % rule above cannot reach
end

function sig = optionsSignature(opts)
% Deterministic key=value over the option fields, sorted by name. Verbosity
% and path settings are excluded by the caller, not here - this function
% signs whatever it is handed.
if isempty(opts) || ~isstruct(opts); sig = ''; return; end
f  = sort(fieldnames(opts));
kv = cell(1, numel(f));
for k = 1:numel(f)
    v = opts.(f{k});
    % Sign the VALUE, not how it was spelled. A flag reaches us as numeric 1
    % when a user set it and as logical true when an entry point resolved a
    % default, and mat2str renders those '1' and 'true' - which would move the
    % generation id between two runs that produce byte-identical code. The id
    % must move when the artifact changes, and only then.
    if islogical(v); v = double(v); end
    if ischar(v) || isstring(v)
        vs = char(v);
    elseif isnumeric(v)
        vs = mat2str(v);
    elseif iscell(v)
        vs = sprintf('cell%d', numel(v));
    else
        vs = class(v);
    end
    kv{k} = [f{k} '=' vs];
end
sig = strjoin(kv, ',');
end

function t = isoNowUTC()
% ISO 8601 UTC. IReproTest (TS-I-03) compares generated files modulo timestamp
% lines - its own comment says the strip exists so "a future timestamp header
% would not make this fail" - so a wall-clock stamp does not break REQ-T-06.
try
    t = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'uuuu-MM-dd''T''HH:mm:ss''Z'''));
catch
    t = [datestr(now, 'yyyy-mm-ddTHH:MM:SS') 'Z'];   %#ok<DATST,TNOW1> pre-datetime fallback
end
end
