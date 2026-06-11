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

if isstring(mode); mode = char(mode); end
if ~ischar(mode) || isempty(mode)
    error('adigator:embedMode', ...
        'EMBED_MODE must be ''c''/''classic'', ''l''/''coderload'', or ''i''/''inline''');
end
mode = lower(mode(1));
if ~any(mode == 'cli')
    error('adigator:embedMode', ...
        'unknown EMBED_MODE ''%s'' (use ''c''/''classic'', ''l''/''coderload'', ''i''/''inline'')', mode);
end
end
