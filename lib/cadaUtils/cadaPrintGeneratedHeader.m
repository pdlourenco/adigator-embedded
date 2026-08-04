function cadaPrintGeneratedHeader(fid, fileName, stamp, reconstruct)
%CADAPRINTGENERATEDHEADER  The header every generated file carries (issue #200).
%
%   cadaPrintGeneratedHeader(fid, fileName, stamp)
%   cadaPrintGeneratedHeader(fid, fileName, stamp, reconstructLines)
%
% `stamp` comes from `cadaGenerationStamp`. `reconstructLines` is a cellstr of
% already-formatted MATLAB source lines showing the call that produced this
% file; omit it where the call cannot be reproduced faithfully.
%
% What changed from the inherited header, and why (issue #200):
%
%   NO CONTACTS. The old text routed users to `mweinstein@ufl.edu` and the
%   sourceforge forums - upstream's support channels, for a fork upstream does
%   not maintain. Questions go to this repository's issues.
%
%   DO NOT EDIT, said once and early. Regeneration is the supported path;
%   an edit is lost silently on the next run, which is worth saying before
%   someone spends an afternoon on one.
%
%   PROVENANCE. Version, ISO 8601 timestamp, generation id, and the call that
%   reconstructs the file - so a generated artifact found in a firmware
%   repository answers "from what, with which options, when" without needing
%   the person who ran it.
%
%   ONE HEADER PER FILE. The inline (`'i'`) mode joins wrapper, derivative and
%   data into a single file, and previously each part brought its own full
%   block: a 58-line generated file was 57% comments, carrying the disclaimer
%   twice and four copyright lines. Parts now carry a one-line marker and the
%   file carries one header.
%
% On licensing: the text states that the TOOL is GPL v3 and the output is
% provided as-is. It deliberately makes NO claim about the licence of the
% generated derivative. Whether generated output can be freed of the GPL is a
% real question, but not this fork's alone to answer - ADiGator is
% © Weinstein and Rao, and an exception over their copyright is not ours to
% grant. Tracked separately.
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

if nargin < 4; reconstruct = {}; end
if ischar(reconstruct); reconstruct = {reconstruct}; end

p = @(varargin) fprintf(fid, varargin{:});

p('%% %s -- GENERATED FILE. Do not edit; regenerate instead.\n', fileName);
p('%% Edits are lost the next time this file is generated.\n');
p('%%\n');
p('%% ADiGator %s (GMV embedded fork) -- generated %s\n', stamp.version, stamp.when);
p('%% Generation id: %s  (tool version + options + source contents)\n', stamp.id);

if ~isempty(reconstruct)
    p('%%\n');
    p('%% Reconstruct with:\n');
    for k = 1:numel(reconstruct)
        if isempty(strtrim(reconstruct{k}))
            p('%%\n');            % a bare '%', not '%' plus trailing spaces
        else
            p('%%   %s\n', reconstruct{k});
        end
    end
end

p('%%\n');
p('%% Issues and questions: https://github.com/pdlourenco/adigator-embedded/issues\n');
p('%%\n');
p('%% Produced by ADiGator, distributed under the GNU General Public License\n');
p('%% version 3.0, in the hope that it is useful but with NO WARRANTIES OF ANY\n');
p('%% KIND and no merchantability or fitness for any purpose or application.\n');
p('%% %s2010-2014 Matthew J. Weinstein and Anil V. Rao\n', char(169));
p('%% %s2025-2026 Pedro Louren%co and GMV (embedded fork additions)\n', char(169), char(231));
p('\n');
end
