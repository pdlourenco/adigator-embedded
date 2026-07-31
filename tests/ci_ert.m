function results = ci_ert()
%CI_ERT  Run the embeddability gates and print a release attestation.
%
%   matlab -batch "addpath('tests'); ci_ert"
%
% Hosted CI licenses neither MATLAB Coder nor Embedded Coder, so *every*
% codegen property this project claims is verified only by a local run
% (docs/CI_PLAN.md §3.2, binding). `ci_local` runs these classes among ~370
% others; this entry point runs **only** them and prints what was actually
% established, so a release can record the claim rather than assert it.
%
% Runs the four codegen/embeddability classes:
%   SCodegenTest            REQ-T-05  compiled-output equivalence
%   SCodegenShowcaseTest    REQ-T-05  the showcase cells compile and match
%   SRolledErtCodegenTest   REQ-T-10  strict ERT acceptance (exit-success)
%   SStackScalingTest       REQ-T-10  stack overhead vs hand-written (ADR-0035)
%
% Reads *per class*, not by a total: an aggregate incomplete count cannot
% distinguish "this machine lacks Embedded Coder" (nothing verified) from a
% `KnownIssue` pin firing as designed (everything verified, one documented gap).
% Both are Filtered. The summary below says which.
%
% Exit is non-zero on a genuine failure only; a Filtered class is reported and
% does not fail, because a machine without the licenses must be able to run this
% and get an honest "not established" rather than a red herring.
%
% Copyright Pedro Lourenço and GMV.  2026-07  (#80a-2, ADR-0035)
% Distributed under the GNU General Public License version 3.0
%
% see also ci_local, measureStackScaling, adigatorCoderConfig

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

% Result names that are EXPECTED to filter: documented KnownIssue pins. Anything
% else filtering means a case did not run - a missing toolchain, a renamed
% fixture, a broken build - and must not be reported as a pin firing by design.
%
% Empty since #217 closed (ADR-0036): its self-healing pin,
% SStackScalingTest/subscriptedHessianStackOverhead, was the only entry and is
% now an ordinary parity assertion. With no pins listed, ANY filter in these
% classes reads as PARTIAL - which is the correct, stricter reading.
knownPins = {};

classes = { ...
    'SCodegenTest',          'REQ-T-05  compiled-output equivalence'; ...
    'SCodegenShowcaseTest',  'REQ-T-05  showcase cells compile and match'; ...
    'SRolledErtCodegenTest', 'REQ-T-10  strict ERT acceptance'; ...
    'SStackScalingTest',     'REQ-T-10  stack overhead vs hand-written'};

files = cellfun(@(c) fullfile(thisDir,'system',[c '.m']), classes(:,1), ...
    'UniformOutput', false);
results = runtests(files);

fprintf('\n================ ERT / embeddability attestation ================\n');
fprintf('%-24s %-42s %s\n','class','requirement','verdict');
anyEstablished = false;
for k = 1:size(classes,1)
    sel = startsWith({results.Name}, [classes{k,1} '/']);
    r   = results(sel);
    if isempty(r)
        verdict = 'ABSENT (class did not run)';
    elseif any([r.Failed])
        verdict = sprintf('FAILED (%d of %d)', nnz([r.Failed]), numel(r));
    elseif all([r.Incomplete])
        % Every method filtered: the licences/toolchain are absent, so this
        % class established nothing. NOT a pass.
        verdict = 'NOT ESTABLISHED (all filtered - licences/toolchain absent)';
    elseif any([r.Incomplete])
        filtered  = {r([r.Incomplete]).Name};
        unexpected = filtered(~ismember(filtered, knownPins));
        if isempty(unexpected)
            verdict = sprintf('established, %d KnownIssue pin(s) filtered', numel(filtered));
        else
            verdict = sprintf('PARTIAL - %d unexpected filter(s): %s', ...
                numel(unexpected), strjoin(unexpected, ', '));
        end
        anyEstablished = true;
    else
        verdict = sprintf('established (%d)', nnz([r.Passed]));
        anyEstablished = true;
    end
    fprintf('%-24s %-42s %s\n', classes{k,1}, classes{k,2}, verdict);
end
fprintf('=================================================================\n');
if ~anyEstablished
    fprintf(['NOTHING was established on this machine. Embedded Coder and a C\n', ...
             'compiler are required; footprint/stack additionally need a\n', ...
             'standalone gcc/size toolchain. See CI_PLAN.md §3.2.\n']);
end
fprintf(['Record this output in the release checklist / PR: hosted CI cannot\n', ...
         'reproduce any of it (CI_PLAN.md §3.2).\n\n']);

assertSuccess(results);
end
