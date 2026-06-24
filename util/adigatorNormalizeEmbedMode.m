function mode = adigatorNormalizeEmbedMode(mode)
%ADIGATORNORMALIZEEMBEDMODE  Validate/normalize the EMBED_MODE option.
%
% Accepts 'c'/'classic', 'l'/'coderload', 'i'/'inline' in any case, char or
% string, and returns the single lower-case mode character. Errors with a
% clear message otherwise.
%
% Rationale (docs/ANALYSIS.md B11): generator code compares the option with
% scalar chars (opts.embed_mode == 'c'); a multi-character value such as
% 'classic' made those comparisons error inside && conditions. Normalizing
% once at option-parse time makes every downstream comparison safe.
%
% Copyright GMV.
% Changelog:
%   2026-06    Created (B11, PR #8); explicit alias mapping instead of
%              first-letter truncation, which conflated 'coderload' with
%              'classic' (PR #8 follow-up).

if isstring(mode); mode = char(mode); end
if isempty(mode) && ~ischar(mode)
    % Unset sentinel ([] from adigatorOptions): the embed_mode was not chosen.
    % Resolve to the classic default here; the embedded generator
    % (adigatorGenDerFile_embedded) overrides [] -> 'i' BEFORE calling this, so
    % only the classic generators reach this branch. An empty CHAR ('') is a
    % malformed value and still errors below.
    mode = 'c';
    return
end
if ~ischar(mode) || isempty(mode)
    error('adigator:embedMode', ...
        'EMBED_MODE must be ''c''/''classic'', ''l''/''coderload'', or ''i''/''inline''');
end
% NOTE: explicit name mapping -- first-letter truncation would conflate
% 'coderload' with 'classic' (both start with c)
switch lower(mode)
    case {'c','classic'}
        mode = 'c';
    case {'l','coderload'}
        mode = 'l';
    case {'i','inline'}
        mode = 'i';
    otherwise
        error('adigator:embedMode', ...
            'unknown EMBED_MODE ''%s'' (use ''c''/''classic'', ''l''/''coderload'', ''i''/''inline'')', mode);
end
end
