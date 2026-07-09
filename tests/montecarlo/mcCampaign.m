function report = mcCampaign(varargin)
%MCCAMPAIGN  Run the randomized Monte-Carlo V&V campaign (issue #38, ADR-0007).
%
% Opt-in, non-gating battery: each iteration draws a randomized fixture from
% a generator, generates its derivative, and checks it with the tolerance-
% free oracles. Failures are shrunk (mcShrink) and promoted (mcPromote) into
% deterministic regression reproducers. Iteration i is seeded from seed+i, so
% any failure replays exactly via mcCampaign('seed', S, 'nIters', i, ...).
%
%   report = mcCampaign('Name', value, ...)
%
% Options (defaults in brackets):
%   nIters     [100]  number of cases.
%   seed       [0]    base RNG seed (>= 0); iteration i uses seed+i.
%   generators [affine, quadratic, shapefuzz, elementwise, scalarSum,
%              paramDelivery]  generator function names, cycled.
%   oracles    [knownDeriv, finiteDiff, sparsitySuperset, crossMode,
%              hessSymmetry, fwdRev, paramDeliveryInvariance,
%              derOutputInvariance]  oracle names. finiteDiff is the FD secondary
%              value oracle (#145): it value-checks the closed-form-free cases
%              (e.g. shapefuzz) that knownDeriv skips.
%   stopOnFail [false] stop at the first failing case.
%   promote    [true]  write a regression reproducer per failure.
%   reportPath ['']    also write the summary to this file.
%   verbose    [true]  print progress and the summary.
%
% Returns a report struct (see mcReport).
p = inputParser; p.FunctionName = 'mcCampaign';
p.addParameter('nIters', 100, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter('seed', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('generators', ...
    {'mcGenAffine','mcGenQuadratic','mcGenShapeFuzz','mcGenElementwise','mcGenScalarSum', ...
     'mcGenParamDelivery'}, @iscellstr);
p.addParameter('oracles', ...
    {'oracleKnownDeriv','oracleFiniteDiff','oracleSparsitySuperset','oracleCrossMode', ...
     'oracleHessSymmetry','oracleFwdRev','oracleParamDeliveryInvariance', ...
     'oracleDerOutputInvariance'}, @iscellstr);
p.addParameter('stopOnFail', false, @(x) islogical(x) && isscalar(x));
p.addParameter('promote', true, @(x) islogical(x) && isscalar(x));
p.addParameter('reportPath', '', @(x) ischar(x) || isstring(x));
p.addParameter('verbose', true, @(x) islogical(x) && isscalar(x));
p.parse(varargin{:});
o = p.Results;

cleanup = mcAddPaths(); %#ok<NASGU>  % idempotent; path restored on exit

nPass = 0; nFail = 0;
oracleStats = struct();
for k = 1:numel(o.oracles)
    oracleStats.(o.oracles{k}) = struct('pass',0,'fail',0,'skip',0);
end
failures = struct('seed',{},'gen',{},'message',{});
promoted = {};
tagsList = cell(1, o.nIters);

for i = 1:o.nIters
    s = o.seed + i;
    rng(s);
    gen = o.generators{1 + mod(i-1, numel(o.generators))};
    c = feval(gen, i);
    tagsList{i} = c.tags;

    res = mcRunCase(c, o.oracles);

    for k = 1:numel(res.results)
        % Key by the oracle FUNCTION name (positionally — mcRunCase preserves
        % oracle order), not the oracle's self-reported short name, so the
        % counts land in the same fields MCSmokeTest / mcReport read.
        rr = res.results(k); nm = o.oracles{k};
        if ~isfield(oracleStats, nm)
            oracleStats.(nm) = struct('pass',0,'fail',0,'skip',0);
        end
        if rr.skipped
            oracleStats.(nm).skip = oracleStats.(nm).skip + 1;
        elseif rr.pass
            oracleStats.(nm).pass = oracleStats.(nm).pass + 1;
        else
            oracleStats.(nm).fail = oracleStats.(nm).fail + 1;
        end
    end

    if res.pass
        nPass = nPass + 1;
    else
        nFail = nFail + 1;
        failures(end+1) = struct('seed', s, 'gen', gen, ...
            'message', firstFailMsg(res.results)); %#ok<AGROW>
        if o.promote
            cmin = mcShrink(c, o.oracles);
            promoted{end+1} = mcPromote(cmin, s, res.results, []); %#ok<AGROW>
        end
        if o.stopOnFail, break; end
    end

    if o.verbose && mod(i, max(1, round(o.nIters/10))) == 0
        fprintf('  ... %d/%d (pass %d, fail %d)\n', i, o.nIters, nPass, nFail);
    end
end

report = struct();
report.matlabRelease = version('-release');
report.seed = o.seed;
report.nIters = o.nIters;
report.nPass = nPass;
report.nFail = nFail;
report.oracleStats = oracleStats;
report.failures = failures;
report.promoted = promoted;
report.coverage = mcCoverage(tagsList(~cellfun(@isempty, tagsList)));

if o.verbose || ~isempty(o.reportPath)
    mcReport(report, o.reportPath);
end
end

function m = firstFailMsg(results)
m = 'unknown failure';
for k = 1:numel(results)
    if ~results(k).pass && ~results(k).skipped
        m = sprintf('%s: %s', results(k).name, results(k).message);
        return;
    end
end
end
