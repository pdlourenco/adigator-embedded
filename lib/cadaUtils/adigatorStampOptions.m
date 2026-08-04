function sopts = adigatorStampOptions(opts)
%ADIGATORSTAMPOPTIONS  The option subset a generation stamp signs (issue #200).
%
% Emission-affecting options only. `echo`, `overwrite`, `keyboard` and `path`
% are excluded deliberately: they do not change the generated artifact, and
% signing them would move the generation id for reasons a reader cannot see in
% the file - which would make the id useless for exactly the job it has, namely
% telling a maintainer whether a committed derivative still matches its source.
%
% Missing fields default rather than error, so an older or partially-populated
% options struct still yields a stamp.
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

g = @(name, dflt) getfielddefault(opts, name, dflt);
sopts = struct( ...
    'unroll',       g('unroll',       0), ...
    'embed_mode',   g('embed_mode',   'c'), ...
    'slim_embed',   g('slim_embed',   0), ...
    'loopbound',    loopboundSig(g('loopbound', [])), ...
    'der_output',   g('der_output',   'matrix'), ...
    'der_levels',   levelsSig(g('der_levels', [])), ...
    'complex',      g('complex',      0), ...
    'maxwhileiter', g('maxwhileiter', 0), ...
    'comments',     g('comments',     1));
end

function v = getfielddefault(s, name, dflt)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = dflt;
end
end

function s = loopboundSig(lb)
% `loopbound` is a name, a cellstr of names, or a struct array of name/value
% pairs depending on how it was declared. Only the NAMES affect emission (the
% values are the analysed trip counts, already reflected in the source), so
% sign a sorted name list.
if isempty(lb);            s = '';                       return; end
if ischar(lb);             s = lb;                       return; end
if iscell(lb);             s = strjoin(sort(lb(:).'), '+'); return; end
if isstruct(lb) && isfield(lb, 'name')
    s = strjoin(sort({lb.name}), '+');                   return
end
s = class(lb);
end

function s = levelsSig(lv)
if isempty(lv);   s = '';                      return; end
if ischar(lv);    s = lv;                      return; end
if iscell(lv);    s = strjoin(sort(lv(:).'), '+'); return; end
s = mat2str(lv);
end
