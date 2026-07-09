function r = oracleFiniteDiff(c)
%ORACLEFINITEDIFF  Central finite-difference VALUE oracle (ADR-0007, R9 Phase C).
%
% The FD secondary value oracle (#145). For a case with NO closed-form
% derivative (c.exactJac / c.exactHess empty -- e.g. mcGenShapeFuzz), generate
% the classic derivative, evaluate it at c.x0, finite-difference the user
% function at the same point, and compare the derivative VALUES.
%
% Why it matters: without it a []-exact case gets no value check at all --
% oracleKnownDeriv skips (no closed form) and every other default oracle is
% structural (cross-mode agreement, sparsity superset, symmetry, topology). So a
% derivative that is WRONG IN VALUE but cross-mode-consistent on a fuzzed shape
% (the historical B7/B10 class) would pass the campaign silently. This oracle
% closes that gap.
%
% Skips cleanly when:
%   - a closed form exists (oracleKnownDeriv is the authoritative, tolerance-free
%     value check there -- no need to also FD it), or
%   - the case is a hessian (an FD-Hessian value oracle is future work; no
%     closed-form-free hessian generator exists in the campaign today, so this
%     skip covers no live case -- it is a guard against a future one).
r = struct('name','finiteDiff','pass',true,'skipped',false,'message','');

needsHess = strcmp(c.deriv,'hessian');
hasClosed = (needsHess && ~isempty(c.exactHess)) || ...
            (~needsHess && ~isempty(c.exactJac));
if hasClosed
    r.skipped = true;
    r.message = 'closed form present (oracleKnownDeriv is the value check)';
    return;
end
if needsHess
    r.skipped = true;
    r.message = 'FD-Hessian value oracle not yet implemented (#145)';
    return;
end

% generate the classic derivative and evaluate it at c.x0
g = mcGenClassic(c);
out = mcEval(g.wrapper, 2, c.x0);
D = out{1};

% finite-difference the user function (its fixture is in the cwd)
Jfd = fdJacobian(c.name, c.x0);      % [numel(f) x numel(x)], output column-major

% shape the FD reference to the derivative convention (C-1): a jacobian is the
% [m x n] matrix as returned; a gradient is the n x 1 column. (The gradient
% branch is defensive - every current gradient generator supplies a closed form,
% so a closed-form-free gradient case does not reach here today.)
if strcmp(c.deriv,'gradient')
    Dex = Jfd(:);
else
    Dex = Jfd;
end

% central FD at h=1e-6 on the campaign's smooth, well-scaled fixtures
atol = 1e-5; rtol = 1e-4;
[r.pass, r.message] = closeEnoughFD(D, Dex, atol, rtol, c.deriv);
end

%% ------------------------------------------------------------------- %%
function J = fdJacobian(fname, x)
% central-difference Jacobian of fname at x, output linearized column-major
h = 1e-6;
f0 = feval(fname, x);
m = numel(f0);
n = numel(x);
J = zeros(m, n);
for j = 1:n
    e = zeros(size(x)); e(j) = h;
    J(:,j) = reshape(feval(fname, x+e) - feval(fname, x-e), [], 1) / (2*h);
end
end

%% ------------------------------------------------------------------- %%
function [ok, msg] = closeEnoughFD(A, B, atol, rtol, what)
ok = isequal(size(A), size(B)) && ...
     all(abs(A(:)-B(:)) <= atol + rtol*abs(B(:)));
if ok
    msg = '';
else
    msg = sprintf('%s FD-value mismatch: max abs err %.3g (size A=%s, B=%s)', ...
        what, max(abs(A(:)-B(:)), [], 'omitnan'), mat2str(size(A)), mat2str(size(B)));
end
end
