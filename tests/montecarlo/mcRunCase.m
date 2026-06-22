function res = mcRunCase(c, oracles)
%MCRUNCASE  Generate, evaluate and check one case against a set of oracles.
%
% Sets up a fresh temp working folder, writes the case fixture into it, runs
% each named oracle (each oracle generates what it needs in/under the cwd),
% then tears the folder down. Returns:
%   res.pass    - true iff no oracle reported a hard failure (skips are ok)
%   res.results - 1xN struct array of per-oracle results
%
% Assumes the caller has put tests/montecarlo (+ generators/oracles/helpers)
% and the toolbox folders on the path (mcCampaign / MCSmokeTest do this).
work = tempname;
mkdir(work);
old = cd(work);
cleanup = onCleanup(@() teardown(old, work)); %#ok<NASGU>

writeFixtureFile(c.name, c.body);

n = numel(oracles);
results = repmat(struct('name','','pass',true,'skipped',false,'message',''), 1, n);
for k = 1:n
    try
        rk = feval(oracles{k}, c);
        % normalize: tolerate oracles that omit a field
        results(k).name    = getfielddef(rk, 'name', oracles{k});
        results(k).pass    = logical(getfielddef(rk, 'pass', false));
        results(k).skipped = logical(getfielddef(rk, 'skipped', false));
        results(k).message = char(getfielddef(rk, 'message', ''));
    catch e
        results(k).name    = oracles{k};
        results(k).pass    = false;
        results(k).skipped = false;
        results(k).message = sprintf('oracle errored: %s', e.message);
    end
end

res.results = results;
res.pass = all([results.pass]);
end

function v = getfielddef(s, f, d)
if isstruct(s) && isfield(s, f)
    v = s.(f);
else
    v = d;
end
end

function teardown(old, work)
cd(old);
try
    rmdir(work, 's');
catch
    % best-effort cleanup; a leaked temp folder is harmless
end
end
