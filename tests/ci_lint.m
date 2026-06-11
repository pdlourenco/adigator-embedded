function ci_lint()
%CI_LINT  Lint gate (CI plan TS-U-09 / REQ-C-10, Phase 4 ratchet).
%
% Fails (errors) if checkcode reports a parse error in any toolbox source
% folder, or if the total number of checkcode findings exceeds the
% committed baseline in tests/lint_baseline.txt (warning-count ratchet:
% legacy findings are tolerated, new ones are not). Without a baseline
% file the count is reported but not gated.

thisDir = fileparts(mfilename('fullpath'));
root = fileparts(thisDir);

folders = { ...
    root, ...
    fullfile(root,'lib'), ...
    fullfile(root,'lib','cadaUtils'), ...
    fullfile(root,'lib','@cada'), ...
    fullfile(root,'lib','@cada','private'), ...
    fullfile(root,'lib','@cadastruct'), ...
    fullfile(root,'util'), ...
    fullfile(root,'embedding'), ...
    fullfile(root,'tests'), ...
    fullfile(root,'tests','unit'), ...
    fullfile(root,'tests','integration'), ...
    fullfile(root,'tests','system')};

nerr = 0;
nwarn = 0;
nfiles = 0;
findings = cell(0,1);
for f = folders
    if ~isfolder(f{1}), continue; end
    files = dir(fullfile(f{1}, '*.m'));
    for k = 1:numel(files)
        fp = fullfile(files(k).folder, files(k).name);
        nfiles = nfiles + 1;
        msgs = checkcode(fp);
        for m = 1:numel(msgs)
            if contains(msgs(m).message, 'Parse error', 'IgnoreCase', true)
                fprintf(2, '%s:%d: %s\n', fp, msgs(m).line, msgs(m).message);
                nerr = nerr + 1;
            else
                nwarn = nwarn + 1;
                findings{end+1,1} = sprintf('%s:%d: %s', ...
                    fp, msgs(m).line, msgs(m).message); %#ok<AGROW>
            end
        end
    end
end

if nerr > 0
    error('ci_lint:parseErrors', 'ci_lint: %d parse error(s) found.', nerr);
end
fprintf('ci_lint: %d files checked, no parse errors, %d checkcode finding(s).\n', ...
    nfiles, nwarn);

% ---- warning-count ratchet (CI plan Phase 4) ---- %
basefile = fullfile(thisDir, 'lint_baseline.txt');
if isfile(basefile)
    base = str2double(strtrim(fileread(basefile)));
    if nwarn > base
        % print every finding so the new ones are identifiable in the log
        fprintf(2, '%s\n', findings{:});
        error('ci_lint:ratchet', ...
            ['ci_lint: checkcode findings increased to %d (baseline %d). ', ...
             'Fix the new findings (all findings listed above), or ', ...
             'consciously raise tests/lint_baseline.txt.'], ...
            nwarn, base);
    elseif nwarn < base
        fprintf(['ci_lint: findings below baseline (%d < %d); consider ', ...
            'tightening tests/lint_baseline.txt.\n'], nwarn, base);
    end
else
    fprintf(['ci_lint: no baseline committed (tests/lint_baseline.txt); ', ...
        'reporting only.\n']);
end
end

