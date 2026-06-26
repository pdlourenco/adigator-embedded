function r = oracleFwdRev(c)
%ORACLEFWDREV  Reverse-mode gradient equals forward (ADR-0007 Phase B).
%
% For a scalar-cost case, generate the gradient two independent ways — the
% forward 'Grd' wrapper and the reverse-mode adjoint file
% (adigatorGenRevGradFile, roadmap R4) — and assert they agree (and match the
% closed form when one is supplied). Exercises the reverse path under
% randomization. Skips cleanly for non-scalar cases.
r = struct('name','fwdRev','pass',true,'skipped',false,'message','');

% Applies to any scalar-output cost (the scalar-reduction generator and the
% quadratic generator both tag outShape [1 1]). Skips vector outputs.
isScalar = isfield(c.tags,'outShape') && isequal(c.tags.outShape,[1 1]);
if ~isScalar
    r.skipped = true; r.message = 'not a scalar cost'; return;
end

ax = adigatorCreateDerivInput(c.xsize, 'x');

% Reverse mode (ANALYSIS §3 / adigatorGenRevGradFile) supports only a subset
% of constructs and rejects the rest at GENERATION time from its own builder
% (`adigator:revgrad:*`) or tape parser (`adigator:fwdtape:*`). Treat exactly
% those scope rejections as a SKIP, not a failure, so a tool-scope limit can
% never be promoted as a false regression. Any other error — a different
% `adigator:*` (a genuine generation bug the fuzzer should surface), or a bare
% user-function crash (empty identifier) — propagates and is recorded as a
% finding; a numeric disagreement is caught by the comparison below.
try
    adigatorGenRevGradFile(c.name, {ax}, adigatorOptions('overwrite',1,'echo',0));
catch e
    if startsWith(e.identifier, 'adigator:revgrad') || ...
            startsWith(e.identifier, 'adigator:fwdtape')
        r.skipped = true;
        r.message = sprintf('reverse mode declined this construct (%s): %s', ...
            e.identifier, e.message);
        return;
    end
    rethrow(e);
end

% forward gradient (column, 'Grd' convention)
adigatorGenJacFile(c.name, {ax}, struct('echo',0,'overwrite',1), 'Grd');
outF = mcEval([c.name '_Grd'], 2, c.x0);
gFwd = outF{1}(:);

% reverse gradient: [grad, value] = <name>_RGrd(x)   (C-6: derivative first)
outR = mcEval([c.name '_RGrd'], 2, c.x0);
gRev = outR{1}(:);

% forward vs reverse: different algorithms, so tight tolerance not bit-exact
atol = 1e-8; rtol = 1e-8;
if ~isequal(numel(gFwd), numel(gRev))
    r.pass = false;
    r.message = sprintf('gradient length mismatch: fwd %d, rev %d', numel(gFwd), numel(gRev));
    return;
end
e = max(abs(gFwd - gRev), [], 'omitnan');
if e > atol + rtol*max(abs(gFwd), [], 'omitnan')
    r.pass = false;
    r.message = sprintf('reverse vs forward gradient differ: max abs %.3g', e);
    return;
end

% optional: both against the closed form
if ~isempty(c.exactJac)
    gEx = c.exactJac(c.x0); gEx = gEx(:);
    e2 = max(abs(gRev - gEx), [], 'omitnan');
    if e2 > 1e-8 + 1e-8*max(abs(gEx), [], 'omitnan')
        r.pass = false;
        r.message = sprintf('reverse gradient vs closed form differ: max abs %.3g', e2);
    end
end
end
