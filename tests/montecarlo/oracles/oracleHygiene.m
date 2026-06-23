function r = oracleHygiene(c)
%ORACLEHYGIENE  Malformed fixtures must fail cleanly and leave no state.
%
% For a NEGATIVE case (a deliberately malformed fixture, tags.negative = true),
% derivative generation must raise an error AND leave the session hygienic
% (REQ-T-07 / B16): no stray transformation-state globals, the MATLAB path
% restored, and no adigator-owned file handles left open. This pins the
% adigator.m onCleanup error-path release. Run it as its own campaign --
% negative cases must never be fed to the value oracles:
%   mcCampaign('generators',{'mcGenNegative'},'oracles',{'oracleHygiene'})
r = struct('name','hygiene','pass',true,'skipped',false,'message','');

if ~(isfield(c.tags,'negative') && c.tags.negative)
    r.skipped = true; r.message = 'not a negative case'; return;
end

% Snapshot the session state that generation must restore.
globals0 = who('global');
path0    = path;
fids0    = openFidsPortable();

% Generation MUST error on a malformed fixture.
errored = false;
try
    mcGenClassic(c);
catch
    errored = true;
end
if ~errored
    r.pass = false;
    r.message = 'malformed fixture did not raise an error during generation';
    return;
end

% ... and must not leave live transformation-state globals behind. (The runtime
% data global ADiGator_<name> is only created on the success path, so it can
% never leak from a failed generation; we still check the four explicitly.) A
% stray NAME is only a B16 violation if it carries live state -- reading one of
% adigator's returned cada objects re-registers an EMPTY transformation global
% (every @cada method opens with `global ADIGATOR`), which holds no state and
% cannot poison a later transform. The error path never touches a cada output so
% this leg sees no re-registration, but the predicate matches UCoreErrorHygiene-
% Test's so both legs assert the same invariant. See issue #54 for the @cada fix.
transformGlobals = {'ADIGATOR','ADIGATORFORDATA','ADIGATORDATA','ADIGATORVARIABLESTORAGE'};
stray = intersect(setdiff(who('global'), globals0), transformGlobals);
populated = stray(cellfun(@(n) ~isempty(globalValue(n)), stray));
if ~isempty(populated)
    r.pass = false;
    r.message = sprintf('leaked populated transformation globals: %s', strjoin(populated, ', '));
    return;
end

% ... the MATLAB path must be restored ...
if ~strcmp(path, path0)
    r.pass = false;
    r.message = 'MATLAB path not restored after generation failure';
    return;
end

% ... and no file handles may be left open.
fidsNew = setdiff(openFidsPortable(), fids0);
if ~isempty(fidsNew)
    r.pass = false;
    r.message = sprintf('%d file handle(s) left open after generation failure', numel(fidsNew));
    for k = 1:numel(fidsNew)   % best-effort: don't poison the rest of the campaign
        try, fclose(fidsNew(k)); catch, end
    end
    return;
end
end

function fids = openFidsPortable()
% Portable open-file-identifier list: fopen('all') is being removed (errors on
% recent MATLAB); openedFiles is the replacement but is absent on R2022a..
if exist('openedFiles','builtin') == 5 || exist('openedFiles','file') == 2
    fids = openedFiles();
else
    fids = fopen('all');
end
end

function v = globalValue(name)
% Read a global's current value by name in this disposable helper frame. The
% name is already present in who('global') here, so declaring it global just
% binds the existing value -- the read itself re-registers nothing new.
eval(['global ',name]);
v = eval(name);
end
