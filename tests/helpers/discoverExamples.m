function E = discoverExamples()
%DISCOVEREXAMPLES  Mechanical discovery of every runnable example entry point.
%
% Single source of truth for the example set (issue #69), shared by
% examples/runAllExamples.m (the headless smoke sweep) and
% tests/system/SExamplesTest.m (curated numeric assertions + completeness
% guard), so neither carries a hand-maintained list that can rot.
%
% Discovery is a recursive glob of examples/**/main*.m, plus a MANIFEST of
% non-main entry points (issue #69 decision: add ipoptEx's gl2main via the
% manifest). Each entry also carries its dependency requirements from the
% manifest (issue #69 decision: explicit per-example requirements), so a
% caller can skip-clean an example whose toolbox/solver is unavailable rather
% than reporting a red failure.
%
% ------------------------------ Output --------------------------------- %
%   E - struct array, one element per entry, sorted by .id:
%         .id       - stable identifier, the example path relative to
%                     examples/ with the script stem, e.g.
%                     'jacobians/arrowhead/main' or
%                     'optimization/ipoptEx/gl2main'
%         .dir      - absolute path of the example folder
%         .script   - the script stem to run there (no extension)
%         .requires - cellstr of capability keys this example needs to RUN
%                     ({} for base MATLAB); interpreted by the caller. Keys:
%                       'optim' - Optimization Toolbox (fmincon/fminunc/fsolve)
%                       'coder' - the coder.* namespace (inline/coderload eval)
%                       'ipopt' - the IPOPT MEX (+ its Fortran)
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public License version 3.0.

helpersDir = fileparts(mfilename('fullpath'));     % tests/helpers
root       = fileparts(fileparts(helpersDir));     % repo root
exRoot     = fullfile(root, 'examples');

E = struct('id', {}, 'dir', {}, 'script', {}, 'requires', {});

% --------------------- mechanical discovery: main*.m ------------------- %
files = dir(fullfile(exRoot, '**', 'main*.m'));
for k = 1:numel(files)
  [~, stem] = fileparts(files(k).name);
  E(end+1) = makeEntry(exRoot, files(k).folder, stem); %#ok<AGROW>
end

% ------- manifest: non-main entry points (issue #69 decision) ---------- %
% ipoptEx has no main.m; its entry is gl2main.m (backed by dgl2fg.f + IPOPT).
ipoptDir = fullfile(exRoot, 'optimization', 'ipoptEx');
if isfile(fullfile(ipoptDir, 'gl2main.m'))
  E(end+1) = makeEntry(exRoot, ipoptDir, 'gl2main');
end

% stable, deterministic order
[~, ord] = sort({E.id});
E = E(ord);
end

%% --------------------------------------------------------------------- %%
function e = makeEntry(exRoot, folder, stem)
relDir = strrep(erase(folder, [exRoot, filesep]), '\', '/');
e.id       = [relDir, '/', stem];
e.dir      = folder;
e.script   = stem;
e.requires = exampleRequires(relDir);
end

%% --------------------------------------------------------------------- %%
function req = exampleRequires(relDir)
% Per-example requirements manifest. Keyed by the example folder relative to
% examples/ (forward-slash). Everything not listed runs on base MATLAB ({}).
optim = { ...
  'optimization/fminconEx', 'optimization/fminuncEx', 'optimization/fsolveEx', ...
  'optimization/vectorized/brachistochrone', 'optimization/vectorized/minimumclimb'};
% evaluate an inline embedded wrapper, which references coder.const (the
% coder.* namespace) - so they need MATLAB Coder to run interpreted
coder = {'optimization/pipg', 'hessians/logsumexp'};
ipopt = {'optimization/ipoptEx'};   % gl2main solves with the IPOPT MEX

req = {};
if any(strcmp(relDir, optim)), req{end+1} = 'optim'; end
if any(strcmp(relDir, coder)), req{end+1} = 'coder'; end
if any(strcmp(relDir, ipopt)), req{end+1} = 'ipopt'; end
end
