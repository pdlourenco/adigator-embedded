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
    'id',      fnv1a64(strjoin([parts, sort(src)], char(31))), ...
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
    if ischar(v) || isstring(v)
        vs = char(v);
    elseif islogical(v) || isnumeric(v)
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

function h = fnv1a64(str)
% FNV-1a, 64-bit. Deterministic across releases and platforms, which is the
% whole requirement.
b  = uint64(double(unicode2native(str, 'UTF-8')));
hv = uint64(14695981039346656037);
pr = uint64(1099511628211);
for k = 1:numel(b)
    hv = bitxor(hv, b(k));
    hv = mul64(hv, pr);
end
h = lower(dec2hex(hv, 16));
end

function z = mul64(a, b)
% 64-bit multiply with wraparound, in 32-bit halves: MATLAB saturates uint64
% arithmetic rather than wrapping it, so a*b directly would peg at intmax.
lo = bitand(a, uint64(4294967295)); hi = bitshift(a, -32);
lb = bitand(b, uint64(4294967295)); hb = bitshift(b, -32);
z0 = lo*lb;
z1 = bitand(lo*hb + hi*lb + bitshift(z0, -32), uint64(4294967295));
z  = bitor(bitshift(z1, 32), bitand(z0, uint64(4294967295)));
end
