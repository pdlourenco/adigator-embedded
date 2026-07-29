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
% For a closed-form-free HESSIAN case (e.g. mcGenExprTree, #38 Phase C) it runs
% two tight first-order central-FD checks that together validate the Hessian
% against the raw function (principle 1 -- no reference is trusted blindly):
%   (1) generated gradient G  ~=  central-FD of the user function f
%   (2) generated Hessian  H  ~=  central-FD of the generated gradient G
% If G is wrong, (1) fails independently; if G is right, (2)'s FD-of-G reference
% is trustworthy and validates H. Chained, they check H against f transitively
% with first-order (tight) FD accuracy, which is why this beats a single loose
% second-order FD of f directly.
%
% Skips cleanly when a closed form exists (oracleKnownDeriv is the authoritative,
% tolerance-free value check there -- no need to also FD it).
r = struct('name','finiteDiff','pass',true,'skipped',false,'message','');

needsHess = strcmp(c.deriv,'hessian');
hasClosed = (needsHess && ~isempty(c.exactHess)) || ...
            (~needsHess && ~isempty(c.exactJac));
if hasClosed
    r.skipped = true;
    r.message = 'closed form present (oracleKnownDeriv is the value check)';
    return;
end

% generate the classic derivative
g = mcGenClassic(c);

% central FD tolerances (h=1e-6 on the campaign's smooth, well-scaled fixtures)
atol = 1e-5; rtol = 1e-4;

if needsHess
    [r.pass, r.message, r.skipped] = fdHessianCheck(c, g, atol, rtol);
    return;
end

% ---- first-derivative (jacobian/gradient) FD value check ---- %
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

[r.pass, r.message] = closeEnoughFD(D, Dex, atol, rtol, c.deriv);
end

%% ------------------------------------------------------------------- %%
function [pass, msg, skipped] = fdHessianCheck(c, g, atol, rtol)
% FD-Hessian value oracle (#38 Phase C). Two first-order central-FD checks for
% a closed-form-free scalar-objective hessian case:
%   (1) generated gradient G ~= central-FD of the user function f
%   (2) generated Hessian  H ~= central-FD of the generated gradient G
% See the header for why the pair is principle-1-sound. h=1e-6 first-order
% central FD is ~1e-10 accurate on the campaign's smooth well-scaled fixtures,
% so the atol/rtol here are comfortably loose relative to the truncation error.
skipped = false; msg = ''; pass = true;
h = 1e-6;
x0 = c.x0(:);
n  = numel(x0);

% generated H, G at x0
out0 = mcEval(g.wrapper, 3, x0);
H = out0{1}; G = out0{2};
f0 = feval(c.name, x0);

% guard (principle 1: never assert on a degenerate case). A hessian case must
% be a scalar objective with finite output; if not, skip loudly in the message
% rather than FD a garbage reference.
if ~isscalar(f0) || ~all(isfinite(H(:))) || ~all(isfinite(G(:)))
    skipped = true;
    msg = 'non-scalar or non-finite generated H/G/f; FD-Hessian skipped';
    return;
end

% (1) gradient vs central-FD of f
Gfd = zeros(n, 1);
for j = 1:n
    e = zeros(n, 1); e(j) = h;
    Gfd(j) = (feval(c.name, x0 + e) - feval(c.name, x0 - e)) / (2*h);
end
[ok1, m1] = closeEnoughFD(G(:), Gfd, atol, rtol, 'gradient (vs f)');

% (2) Hessian vs central-FD of the generated gradient G(x)
Hfd = zeros(n, n);
for j = 1:n
    e = zeros(n, 1); e(j) = h;
    op = mcEval(g.wrapper, 3, x0 + e); Gp = op{2};
    om = mcEval(g.wrapper, 3, x0 - e); Gm = om{2};
    Hfd(:, j) = (Gp(:) - Gm(:)) / (2*h);
end
% Guard the FD reference itself: a non-finite Hfd (e.g. an overflow at a
% perturbed point) would make closeEnoughFD's `Inf <= Inf` compare pass
% vacuously -- a false pass on a principle-1 oracle. Skip such a (degenerate,
% ill-conditioned) case rather than trust the reference.
if ~all(isfinite(Hfd(:)))
    skipped = true;
    msg = 'non-finite FD-Hessian reference (ill-conditioned); skipped';
    return;
end
[ok2, m2] = closeEnoughFD(H, Hfd, atol, rtol, 'hessian (vs grad)');

pass = ok1 && ok2;
if ~ok1, msg = m1; elseif ~ok2, msg = m2; end
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
