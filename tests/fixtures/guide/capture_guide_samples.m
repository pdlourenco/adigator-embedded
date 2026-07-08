function capture_guide_samples()
% capture_guide_samples  Producer for the user-guide code-sample golden
% fixtures (ADR-0025, issue #139). It lives next to the golden output it
% produces so the generator and the fixture stay in sync.
%
% ADiGator generates the fixture; this script then inserts the paired
% `% BEGIN-<tag>` / `% END-<tag>` line-comment markers that the guide's
% \lstinputlisting keys off (the guide loads a marker *range*, not line
% numbers, so the excerpt survives regeneration as long as the markers are
% re-emitted here). The markers are plain MATLAB comments -- inert to MATLAB,
% adigator, and MATLAB Coder -- and are stripped from the printed listing by
% the guide's `includerangemarker=false` option.
%
% Currently produces:
%   lse_cost_RGrd.m  - the reverse-mode (adjoint) gradient of the log-sum-exp
%                      cost, marked `rgrd-core` around the forward + reverse
%                      sweep (guide Section 5, adigatorGenRevGradFile sample).
%
% ADiGator uses classdef heavily, so generation must run in MATLAB. Run from
% anywhere in the repo:
%       >> run tests/fixtures/guide/capture_guide_samples.m
% then commit the regenerated fixture:
%       git add tests/fixtures/guide
%       git commit -m "docs(userguide): regenerate guide code-sample fixtures"

orig = pwd;
savedPath = path;
here = fileparts(mfilename('fullpath'));          % tests/fixtures/guide
root = fileparts(fileparts(fileparts(here)));     % repo root
tmp  = tempname; mkdir(tmp);
% restore cwd + path and remove the scratch dir on any exit (success or error)
cleanup = onCleanup(@() restoreEnv(orig, savedPath, tmp));
addpath(root, fullfile(root,'lib'), fullfile(root,'lib','cadaUtils'), ...
    fullfile(root,'util'), fullfile(root,'examples','gradients','logsumexp'));
fprintf('MATLAB version: %s\n', version);

% --- reverse-mode gradient of the log-sum-exp cost (small n for a compact,
%     illustrative excerpt; the adjoint structure is independent of n) --------
n = 4;
cd(tmp);
gx = adigatorCreateDerivInput([n 1], 'x');
gw = adigatorCreateAuxInput([n 1]);
adigatorGenRevGradFile('lse_cost', {gx, gw}, ...
    adigatorOptions('overwrite',1,'echo',0));
txt = readlines('lse_cost_RGrd.m');
cd(orig);

% mark the forward + reverse sweep core (the illustrative adjoint algorithm,
% without the global/load boilerplate)
txt = insertMarkers(txt, 'rgrd-core', ...
    '% ----------------- forward', 'Grd = ');
outfile = fullfile(here, 'lse_cost_RGrd.m');
writelines(txt, outfile);
fprintf('wrote %s\n', outfile);
end

% ---------------------------------------------------------------------------
function txt = insertMarkers(txt, tag, beginAnchor, endAnchor)
% Insert `% BEGIN-<tag>` before the first line starting with beginAnchor and
% `% END-<tag>` after the first (>=begin) line starting with endAnchor.
s = strip(txt);
b = find(startsWith(s, beginAnchor), 1);
e = find(startsWith(s, endAnchor) & (1:numel(s)).' >= b, 1);
assert(~isempty(b) && ~isempty(e), ...
    'capture_guide_samples: anchors for tag ''%s'' not found', tag);
txt = [ txt(1:b-1); ...
        "% BEGIN-" + tag; ...
        txt(b:e); ...
        "% END-" + tag; ...
        txt(e+1:end) ];
end

% ---------------------------------------------------------------------------
function restoreEnv(orig, savedPath, tmp)
cd(orig);
path(savedPath);
if isfolder(tmp); rmdir(tmp,'s'); end
end
