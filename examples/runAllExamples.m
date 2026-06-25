function results = runAllExamples()
%RUNALLEXAMPLES  Headless, mechanical smoke sweep of every shipped example.
%
% Runs every example entry point discovered by tests/helpers/discoverExamples
% (a recursive examples/**/main*.m glob + a manifest of non-main entries), each
% in an isolated workspace, and prints a pass / skip / fail tally (issue #69).
% Replaces the old hand-maintained, interactive list, which had rotted (missing
% the fork's R1-R8 feature examples) and could not run headlessly.
%
% Behaviour:
%   * Discovery is mechanical - adding examples/**/main*.m is picked up with no
%     edit here (the manifest in discoverExamples covers non-main entries and
%     per-example toolbox/solver requirements).
%   * Each example whose required capability is absent (Optimization Toolbox,
%     the coder.* namespace, IPOPT) is SKIPPED cleanly - not a failure.
%   * Each example runs in its own function workspace, cd'd to its folder under
%     an onCleanup restore, with rng(0); a script's `clear` cannot kill the loop
%     and one failing example does not abort the rest.
%   * Generated derivative files land in each example's ./generated subdir
%     (gitignored, issue #67), so the sweep leaves the tree clean.
%   * Returns a struct array of per-example {id,status,message} and ERRORS at
%     the end if any example genuinely failed, so it is usable as a gate.
%
% Copyright GMV. Distributed under the GNU General Public License version 3.0.

exDir = fileparts(mfilename('fullpath'));   % examples/
root  = fileparts(exDir);
% the repo root holds the top-level entry points (adigator, adigatorOptions,
% adigatorCreateDerivInput, ...); lib/util/embedding hold the rest.
addpath(root, fullfile(root, 'lib'), fullfile(root, 'lib', 'cadaUtils'), ...
        fullfile(root, 'util'), fullfile(root, 'embedding'), ...
        fullfile(root, 'tests', 'helpers'));

E = discoverExamples();
results = struct('id', {}, 'status', {}, 'message', {});
nPass = 0; nSkip = 0; nFail = 0;
home = pwd;

for k = 1:numel(E)
  e = E(k);
  missing = e.requires(~cellfun(@capabilityAvailable, e.requires));
  if ~isempty(missing)
    nSkip = nSkip + 1;
    results(end+1) = entry(e.id, 'skip', ['missing: ', strjoin(missing, ', ')]); %#ok<AGROW>
    fprintf('SKIP : %-58s (needs %s)\n', e.id, strjoin(missing, ', '));
    continue
  end
  [ok, msg] = runOneExample(e.dir, e.script);
  cd(home);
  if ok
    nPass = nPass + 1;
    results(end+1) = entry(e.id, 'pass', ''); %#ok<AGROW>
    fprintf('PASS : %s\n', e.id);
  else
    nFail = nFail + 1;
    results(end+1) = entry(e.id, 'fail', msg); %#ok<AGROW>
    fprintf('FAIL : %-58s -> %s\n', e.id, msg);
  end
  close all force
end

fprintf('\n==== examples: %d pass, %d skip, %d fail (of %d discovered) ====\n', ...
  nPass, nSkip, nFail, numel(E));
if nFail > 0
  error('runAllExamples:failures', '%d example(s) failed - see the FAIL lines above.', nFail);
end
end

%% --------------------------------------------------------------------- %%
function [ok, msg] = runOneExample(d, stem)
% Run one example script in this function's own workspace, cd'd to its folder.
% The cwd is NOT restored here (the caller does `cd(home)` after) - a restore
% held in a local onCleanup would be wiped by a script's `clear`, firing mid-run
% and cd'ing away while the script still needs its own folder. ok/msg are
% assigned in both branches AFTER run() returns, so a `clear` cannot leave ok
% unassigned.
cd(d);
rng(0);   % example mains use rand/randn; make the sweep reproducible
try
  run(fullfile(d, [stem, '.m']));
  ok = true;  msg = '';
catch e
  ok = false; msg = e.message;
end
end

%% --------------------------------------------------------------------- %%
function tf = capabilityAvailable(key)
% Is a manifest capability key satisfied on this machine? Used to skip-clean.
switch key
  case 'optim'
    tf = license('test', 'Optimization_Toolbox') && ~isempty(which('fmincon'));
  case 'coder'
    tf = ~isempty(which('coder.load'));   % the coder.* namespace for eval
  case 'ipopt'
    tf = exist('ipopt', 'file') == 3;     % the IPOPT MEX
  otherwise
    tf = false;                           % unknown key -> treat as unavailable
end
end

%% --------------------------------------------------------------------- %%
function s = entry(id, status, message)
s = struct('id', id, 'status', status, 'message', message);
end
