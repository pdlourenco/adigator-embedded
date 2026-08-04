function lines = adigatorReconstructCall(userFunName, derFileName, opts, entryPoint, nameAppendix)
%ADIGATORRECONSTRUCTCALL  "Reconstruct with:" lines for a generated header (#200).
%
%   lines = adigatorReconstructCall(userFun, derFile, opts)
%   lines = adigatorReconstructCall(userFun, derFile, opts, 'adigatorGenJacFile', 'Grd')
%   lines = adigatorReconstructCall(userFun, derFile, opts, ...
%                                   {'adigatorGenDerFile_embedded','gradient'})
%
% Answers the question a hash cannot: not *whether* a generated file matches its
% source, but *how* it was produced - so a maintainer holding an unfamiliar
% artifact can regenerate it rather than reverse-engineer the options.
%
% THE LINE MUST REPRODUCE THE FILE IT IS PRINTED IN. That is the whole value of
% it, and it is easy to get subtly wrong in two ways this function exists to
% prevent:
%
%   NAME. adigatorGenJacFile's 4th argument selects the output name and role -
%   with 'Grd' it emits <fn>_Grd (a gradient, output name Grd), without it
%   <fn>_Jac. Printing the call without the appendix names a DIFFERENT file with
%   a different signature, which is worse than printing nothing.
%
%   ENTRY POINT. In embed_mode 'l'/'i' the artifact is produced by
%   adigatorGenDerFile_embedded - prune, data inlining, %#codegen patch, join.
%   adigatorGenJacFile does none of that; it only forwards opts to adigator. So
%   the wrapper generators cannot name themselves for an embedded file even
%   though they wrote it, and the embedded driver passes its own identity down.
%
% The caller must therefore say who it really is. When it does not, and the
% options say the file went through the embed pipeline, the reconstruct block is
% OMITTED rather than guessed: a recipe that silently produces a different file
% is worse than no recipe (REVIEW_CONTEXT principle 1, applied to claims).
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

if nargin < 4 || isempty(entryPoint);   entryPoint   = 'adigator'; end
if nargin < 5;                          nameAppendix = '';         end

derType = '';
if iscell(entryPoint)
    if numel(entryPoint) > 1; derType = entryPoint{2}; end
    entryPoint = entryPoint{1};
end

optStr = nonDefaultOptions(opts);
optArg = '';
if ~isempty(optStr); optArg = sprintf('adigatorOptions(%s)', optStr); end

switch entryPoint
    case 'adigatorGenDerFile_embedded'
        % Options are the LAST argument here, and the derivative type the first.
        if isempty(derType); lines = {}; return; end
        head = sprintf('adigatorGenDerFile_embedded(''%s'', ''%s'', <inputs>', ...
            derType, userFunName);
        lines = closeCall(head, forceOverwrite(optStr));
    case {'adigatorGenJacFile','adigatorGenHesFile'}
        if embeddedArtifact(opts)
            % See ENTRY POINT above: these did not produce the final file.
            lines = {}; return
        end
        head = sprintf('%s(''%s'', <inputs>', entryPoint, userFunName);
        optArg = forceOverwrite(optStr);
        tail = '';
        % The appendix is positional and follows the options, so it can only be
        % printed when the options are.
        if strcmp(entryPoint,'adigatorGenJacFile') && ~isempty(nameAppendix) ...
                && ~strcmp(nameAppendix,'Jac')
            if isempty(optArg); optArg = 'adigatorOptions()'; end
            tail = sprintf(', ''%s''', nameAppendix);
        end
        lines = closeCall(head, optArg, tail);
    otherwise
        head = sprintf('adigator(''%s'', <inputs>, ''%s''', userFunName, derFileName);
        lines = closeCall(head, optArg);
end

lines{end+1} = '';
lines{end+1} = 'where <inputs> is the cell of adigatorCreateDerivInput /';
lines{end+1} = 'adigatorCreateAuxInput arguments the function was differentiated at.';
end

%% ---------------------------------------------------------------------- %%
function optArg = forceOverwrite(optStr)
% Print `'overwrite',1`, which is what the wrapper and embedded entry points
% actually use. They force it only when the caller passes NO overwrite field -
% and a printed adigatorOptions(...) always has one, defaulted to 0 - so a
% recipe echoing the resolved options back would refuse to run with "the file
% already exists", right next to the file that printed it.
if isempty(optStr)
    optArg = 'adigatorOptions(''overwrite'',1)';
else
    optArg = sprintf('adigatorOptions(%s, ''overwrite'',1)', optStr);
end
end

function lines = closeCall(head, optArg, tail)
% Render the call, wrapping onto a second line only when there are options.
if nargin < 3; tail = ''; end
if isempty(optArg)
    lines = {[head tail ')']};
else
    lines = {[head ', ...'], sprintf('    %s%s)', optArg, tail)};
end
end

function tf = embeddedArtifact(opts)
% True when the options say this file MAY have been finished by the embed
% pipeline, in which case naming a plain wrapper generator could misdescribe it.
%
% Deliberately over-broad, and worth being honest about: calling
% adigatorGenJacFile directly with embed_mode='i' is a real path
% (ICscOutputTest does it) and is NOT post-processed, so there the generator
% really is the entry point and the recipe would have been correct. We suppress
% it anyway, because from here the two cases are indistinguishable and the costs
% are not symmetric - a missing recipe is an inconvenience, a recipe that
% rebuilds a different file is the failure this whole header exists to avoid.
%
% WHICH WAY THIS FAILS IS THE POINT. An earlier version defaulted to FALSE when
% it could not canonicalise the mode - i.e. "not embedded, print the recipe" -
% and that is the wrong direction for exactly the reason above. It also fired:
% adigatorNormalizeEmbedMode lives in util/, a caller reached this with util/
% off the path, the catch swallowed it, and an embedded artifact got a recipe
% naming a generator that does not produce it. Silence is the safe default
% here; printing is the one that can mislead.
if ~isstruct(opts) || ~isfield(opts,'embed_mode'); tf = false; return; end
m = opts.embed_mode;
try
    m = adigatorNormalizeEmbedMode(m);
catch
    % Cannot establish the mode - suppress rather than guess. Bare 'c' is the
    % single exception: it is unambiguous without the canonicaliser.
    tf = ~(ischar(m) && strcmp(m, 'c'));
    return
end
tf = ischar(m) && any(strcmp(m, {'l','i'}));
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
    if any(strcmp(name, {'echo','overwrite','path'}))
        continue    % cannot shape the artifact; same exclusions the generation
                    % id uses, and the two lists must not drift - an option
                    % that is SIGNED but not PRINTED makes the recipe rebuild a
                    % different file (auxdata switches auxiliary inputs between
                    % fixed-value and fixed-pattern, so omitting it silently
                    % constant-folds them). `overwrite` is the one deliberate
                    % asymmetry, forced below.
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
% Render a flag the same way whichever type it arrived as: a user's 1 and an
% entry point's resolved `true` are the same option, and printing them
% differently would make two identical generations look different.
if islogical(v) && isscalar(v); v = double(v); end
if ischar(v)
    lit = ['''' v ''''];
elseif isstring(v) && isscalar(v)
    lit = ['''' char(v) ''''];
elseif isnumeric(v) && isscalar(v) && isfinite(v)
    lit = num2str(v);
elseif iscellstr(v) && ~isempty(v)
    lit = ['{''' strjoin(v(:).', ''',''') '''}'];
end
end
