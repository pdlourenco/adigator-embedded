function msg = ci_gateArmedNotice(hooksPath, isCI)
%CI_GATEARMEDNOTICE  Message warning that the pre-push gate is not armed (#82).
%
%   msg = ci_gateArmedNotice(hooksPath, isCI)
%
% Returns the notice text, or '' when no notice is due. Pure: it decides from
% the two values handed to it and reads nothing itself, so all three states are
% assertable without touching a real `core.hooksPath` or the environment
% (UGateArmedNoticeTest, TS-U-22). `ci_lint` looks the values up and prints
% whatever comes back.
%
% WHY THIS EXISTS. The gate (.githooks/pre-push -> ci_prepush, ADR-0017) is
% opt-in per clone, and an unarmed hook is SILENT - pushes simply succeed.
% Nothing else in the repo can observe that state. #240 reached CI with a
% failure that reproduced perfectly on a plain local run: the gate would have
% caught it, it was never armed, and nothing said so.
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

msg = '';
if isCI
    return    % hooks are irrelevant on a runner
end
if isArmed(hooksPath)
    return
end
msg = [ ...
    'ci_lint: NOTE - the pre-push gate is not armed in this clone.' newline ...
    '         Pushes will not run tests/ci_prepush.m, so a suite that' newline ...
    '         has not been re-run since the last edit can reach CI.' newline ...
    '         Arm it once:  git config core.hooksPath .githooks' newline];
end

%% ---------------------------------------------------------------------- %%
function tf = isArmed(hooksPath)
% Match the path, not a substring of it: `.githooks-disabled` contains
% `.githooks` and is emphatically not armed.
p = strtrim(char(hooksPath));
p = strrep(p, '\', '/');
p = regexprep(p, '/+$', '');          % trailing separator is not significant
[~, name, ext] = fileparts(p);
tf = strcmp([name ext], '.githooks');
end
