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

% ... and must not leave any transformation-state global behind. (The runtime
% data global ADiGator_<name> is only created on the success path, so it can
% never leak from a failed generation; we still check the four explicitly.)
% Strict name-absence, matching UCoreErrorHygieneTest after R11/#54 (ADR-0015):
% the @cada read paths now declare the transformation globals only where they
% use them, so no stray name -- empty or populated -- may survive. (On this leg
% the distinction was always moot: the error path never touches a returned cada
% object, so it could not re-register an empty global even before R11.)
transformGlobals = {'ADIGATOR','ADIGATORFORDATA','ADIGATORDATA','ADIGATORVARIABLESTORAGE'};
stray = intersect(setdiff(who('global'), globals0), transformGlobals);
if ~isempty(stray)
    r.pass = false;
    r.message = sprintf('leaked transformation globals: %s', strjoin(stray, ', '));
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
