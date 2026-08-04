function out = adigatorDemoteGeneratedHeader(lines, marker)
%ADIGATORDEMOTEGENERATEDHEADER  Replace a part's full header with a marker (#200).
%
%   out = adigatorDemoteGeneratedHeader(lines, marker)
%
% Inline (`embed_mode='i'`) mode joins the wrapper, the derivative function and
% the static data into ONE file. Each was generated separately and each carried
% a full header, so the joined artifact repeated the licence, the disclaimer and
% the provenance stamp once per part - the licence and disclaimer appeared once
% per joined part before
% this, and the richer #200 header made that worse, not better.
%
% The file keeps ONE header, at the top, from the wrapper. Every part appended
% after it gets its full header replaced by a single line saying what the part
% is. The provenance is not lost: it is stated once for the file, which is the
% only place it was ever true of the whole thing.
%
% Strips the leading run of comment and blank lines, i.e. up to the part's first
% code line. That is exactly the header for a generated part, whose first code
% line is its `function` statement; `%#codegen` is emitted after that line, not
% before it, so it is never caught here.
%
% Conservative by construction: if no code line is found the input is returned
% unchanged rather than emptied, so a part this does not understand keeps its
% header instead of losing its content.
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

out = lines;
if isempty(lines); return; end

wasString = isstring(lines);
L = string(lines);

first = 0;
for k = 1:numel(L)
    t = strtrim(L(k));
    if strlength(t) == 0 || startsWith(t, "%"); continue; end
    first = k; break
end
if first == 0; return; end          % no code line: leave the part alone

kept = [string(['% ' marker]); ""; L(first:end)];
if wasString
    out = kept;
else
    out = cellstr(kept);
end
end
