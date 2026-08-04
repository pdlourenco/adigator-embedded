function sopts = adigatorStampOptions(opts)
%ADIGATORSTAMPOPTIONS  The option subset a generation stamp signs (issue #200).
%
% SIGN EVERYTHING EXCEPT AN EXPLICIT EXCLUSION LIST. This direction matters more
% than it looks. The first version of this function was an allow-list of nine
% named options, which meant every option added later was unsigned BY DEFAULT -
% and silently, since an unsigned option produces no error, just two materially
% different artifacts sharing one generation id. It had already missed two:
% `auxdata` (adigator.m -> ADIGATOR.OPTIONS.AUXDATA, read in
% adigatorFunctionInitialize) and `optoutput`. Inverting the list makes the
% fail-safe direction "signed": a new option is covered unless someone
% deliberately excludes it, and over-signing is a visible, harmless id churn
% while under-signing is invisible and wrong.
%
% EXCLUDED, deliberately: `echo`, `overwrite` and `path` do not change the
% generated artifact, and signing them would move the id for reasons a reader
% cannot see anywhere in the file - which would defeat the id's only job, namely
% telling a maintainer whether a committed derivative still matches its source.
%
% The field list comes from adigatorOptions() rather than a duplicated literal,
% so it tracks the tool instead of drifting from it. Missing fields default
% rather than error, so an older or partially-populated options struct still
% yields a stamp.
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

EXCLUDED = {'echo','overwrite','path'};

% Canonicalisers for the options whose stored shape varies independently of
% their meaning; everything else is signed as stored.
CANON = struct('loopbound', @loopboundSig, 'der_levels', @levelsSig, ...
               'embed_mode', @embedModeSig);

try
    names = fieldnames(adigatorOptions());
catch
    % Never let provenance be the reason a differentiation fails.
    names = fieldnames(opts);
end

sopts = struct();
for k = 1:numel(names)
    name = names{k};
    if any(strcmp(name, EXCLUDED)); continue; end
    v = getfielddefault(opts, name, defaultFor(name));
    if isfield(CANON, name); v = CANON.(name)(v); end
    sopts.(name) = v;
end
end

function d = defaultFor(name)
% The tool's own default, so an absent field signs identically to one left at
% its default - otherwise a partially-populated struct would get a different id
% from a fully-populated but equivalent one.
d = '';
try
    dflt = adigatorOptions();
    if isfield(dflt, name); d = dflt.(name); end
catch
end
end

function s = embedModeSig(m)
% adigatorOptions leaves embed_mode EMPTY and each entry point resolves it
% later, so sign the canonical form where one is obtainable.
try
    s = adigatorNormalizeEmbedMode(m);
catch
    s = m;
end
if isempty(s); s = ''; end
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
