function lines = adigatorReconstructCall(userFunName, derFileName, opts, entryPoint)
%ADIGATORRECONSTRUCTCALL  "Reconstruct with:" lines for a generated header (#200).
%
%   lines = adigatorReconstructCall(userFun, derFile, opts)
%   lines = adigatorReconstructCall(userFun, derFile, opts, 'adigatorGenJacFile')
%
% Answers the question a hash cannot: not *whether* a generated file matches its
% source, but *how* it was produced - so a maintainer holding an unfamiliar
% artifact can regenerate it rather than reverse-engineer the options.
%
% The input specification is deliberately NOT reproduced. It can be a struct or
% cell of arbitrary depth, and a half-rendered version would be worse than an
% honest placeholder: it would look copy-pasteable and not be. The line names
% what has to be supplied instead.
%
% Only NON-DEFAULT options are printed, so the call stays readable and every
% option shown is one that actually shaped this file.
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

if nargin < 4 || isempty(entryPoint); entryPoint = 'adigator'; end

optStr = nonDefaultOptions(opts);

switch entryPoint
    case 'adigatorGenJacFile'
        head = sprintf('adigatorGenJacFile(''%s'', <inputs>', userFunName);
    case 'adigatorGenHesFile'
        head = sprintf('adigatorGenHesFile(''%s'', <inputs>', userFunName);
    otherwise
        head = sprintf('adigator(''%s'', <inputs>, ''%s''', userFunName, derFileName);
end

if isempty(optStr)
    lines = {[head ')']};
else
    lines = {[head ', ...'], sprintf('    adigatorOptions(%s))', optStr)};
end

lines{end+1} = '';
lines{end+1} = 'where <inputs> is the cell of adigatorCreateDerivInput /';
lines{end+1} = 'adigatorCreateAuxInput arguments the function was differentiated at.';
end

%% ---------------------------------------------------------------------- %%
function s = nonDefaultOptions(opts)
% Compare against adigatorOptions' own defaults, so "non-default" tracks the
% tool rather than a duplicated list that would drift.
s = '';
if ~isstruct(opts); return; end
try
    dflt = adigatorOptions();
catch
    return
end
parts = {};
for f = sort(fieldnames(opts)).'
    name = f{1};
    if ~isfield(dflt, name); continue; end
    if any(strcmp(name, {'echo','overwrite','keyboard','path','auxdata'}))
        continue    % do not shape the artifact; see adigatorStampOptions
    end
    v = opts.(name); d = dflt.(name);
    % Compare canonical forms where a canonicaliser exists. adigatorOptions
    % leaves embed_mode EMPTY by default and it is normalised to 'c' later, so
    % a raw comparison reports the default as non-default and prints
    % embed_mode,'c' into every classic header.
    if strcmp(name, 'embed_mode')
        try
            v = adigatorNormalizeEmbedMode(v);
            d = adigatorNormalizeEmbedMode(d);
        catch
        end
    end
    if isequaln(v, d); continue; end
    lit = literal(v);
    if isempty(lit); continue; end
    parts{end+1} = sprintf('''%s'',%s', name, lit); %#ok<AGROW>
end
s = strjoin(parts, ', ');
end

function lit = literal(v)
% Only render what round-trips as a MATLAB literal. Anything else is omitted
% rather than approximated - an option shown wrong is worse than one absent,
% because the header claims to be a reconstruction recipe.
lit = '';
if ischar(v)
    lit = ['''' v ''''];
elseif isstring(v) && isscalar(v)
    lit = ['''' char(v) ''''];
elseif islogical(v) && isscalar(v)
    lit = mat2str(v);
elseif isnumeric(v) && isscalar(v) && isfinite(v)
    lit = num2str(v);
elseif iscellstr(v) && ~isempty(v)
    lit = ['{''' strjoin(v(:).', ''',''') '''}'];
end
end
