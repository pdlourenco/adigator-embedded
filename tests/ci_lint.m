function ci_lint()
%CI_LINT  Phase-0 lint gate (CI plan TS-U-09, REQ-C-10).
%
% Fails (errors) if checkcode reports a parse error in any toolbox source
% folder. Warning-level findings are printed but do not fail the gate yet;
% a warning-count ratchet is planned for CI Phase 4 (see docs/CI_PLAN.md).

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
nfiles = 0;
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
            end
        end
    end
end

if nerr > 0
    error('ci_lint:parseErrors', 'ci_lint: %d parse error(s) found.', nerr);
end
fprintf('ci_lint: %d files checked, no parse errors.\n', nfiles);
end
