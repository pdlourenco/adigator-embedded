function result = gap_interproc_equiv()
%GAP_INTERPROC_EQUIV  License-free equivalence guard for issue #44 part 1b.
%
% Runs in BOTH MATLAB and GNU Octave (no license, no classdef, no codegen):
% it only *executes* the committed, already-generated gapfun gradient
% fixtures, it does not regenerate them. Generation still needs MATLAB
% (docs/CI_PLAN.md), so the fixtures are captured on MATLAB and committed
% under tests/fixtures/gen_dialect/ by its capture_gen_dialect.m. This is the
% plain-assert core that consumes them, wrapped for the MATLAB CI gate by
% tests/integration/IInterprocGapEquivTest. See ADR-0008 for the
% committed-fixture / license-free offline-core rationale and ADR-0009 for the
% interprocedural slice the slimmed fixture exercises.
%
% The fixtures are generated in INLINE embed mode (capture_gen_dialect), so
% slim_embed actually runs: the slimmed variant (slim1) is a genuinely sliced
% interprocedural file (the main function's unread f.dz_location/f.dz_size and
% their index table drop), not a byte-copy of slim0. Inline embedding wraps the
% constant data in coder.const(...) (identity outside codegen); this core adds
% a coder.const shim (tests/offline/octave_shims) only where coder.const is
% unavailable, so the fixtures run license-free in Octave and on Coder-less
% MATLAB without ever shadowing a real coder.const.
%
% gapfun (examples/optimization/pipg) is interprocedural: it calls conefun and
% setfun, and conefun itself calls setfun, so the generated derivative is
% multi-subfunction. The maths:
%     setfun(z)  = z
%     conefun(z) = eye(2)*setfun(z) - ones(2,1) = z - 1
%     gapfun(w,z)= w'*conefun(z) + z'*setfun(z) = w'*(z-1) + z'*z
%   =>  grad_z gapfun = w + 2*z     (the analytic oracle)
%
% Checks, for each committed variant tests/fixtures/gen_dialect/{slim0,slim1}:
%   (1) the fixture reproduces the analytic gradient w+2z and value w'(z-1)+z'z
%       (oracle 1, exact up to fp);
%   (2) that analytic oracle agrees with a finite difference of the plain
%       gapfun source (oracle 2, independent of both the generated code and the
%       hand derivation - it guards the oracle itself);
%   (3) the slimmed fixture (slim1) is numerically IDENTICAL to the unslimmed
%       one (slim0) - the interprocedural-equivalence invariant: the slice
%       drops dead code / unread output fields but must not move the numbers.
%       The contract is numeric, not structural, so (3) compares results
%       (AbsTol 0), never bytes or index layout.
%
% The runner is fixture-shape agnostic: it cd's into each variant and clears the
% entry function to force a reload of that folder's copy (the mechanism that
% keeps the two same-named fixtures distinct), and also resets the classic
% lazy-load global - so it works on both the inline fixtures and a classic
% capture.
%
% On any mismatch it errors, so it fails a bare Octave run and the
% matlab.unittest wrapper alike. Returns a struct with the computed
% quantities for the wrapper to re-assert.
%
% Usage (license-free, from the repo root; the absolute path matters because
% the fixtures cd elsewhere and a relative load reference would go stale):
%   octave --quiet --eval "addpath(fullfile(pwd,'tests','offline')); gap_interproc_equiv"

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
fixRoot = fullfile(root, 'tests', 'fixtures', 'gen_dialect');
srcDir  = fullfile(root, 'examples', 'optimization', 'pipg');

% restore the path and working directory whatever happens (the fixtures cd
% into their own folders and may load constant data relative to cwd)
origPath = path();
origPwd  = pwd();
cleanup  = onCleanup(@() restoreEnv(origPath, origPwd)); %#ok<NASGU>
addpath(srcDir);

% inline fixtures call coder.const (identity at runtime); shim it ONLY where it
% is unavailable, so we never shadow MATLAB's real coder.const.
if isempty(which('coder.const'))
    addpath(fullfile(here, 'octave_shims'));
end

% arbitrary test point: nonzero, distinct components so a dropped term shows up
w = [3; 5];
z = [7; 11];

% oracle 1: analytic gradient and value
Jref = w + 2*z;
Fref = w'*(z - 1) + z'*z;

% oracle 2: finite difference of the plain gapfun source (cross-checks oracle 1
% independently of the generated code and the hand derivation)
Jfd   = fdgrad(@(zz) gapfun(w, zz), z);
fdTol = 1e-5;
assert(norm(Jfd - Jref, Inf) <= fdTol, ...
    'gap_interproc_equiv:fdOracle', ...
    'FD cross-check failed: |Jfd-Jref|_inf = %.3e > %.1e', ...
    norm(Jfd - Jref, Inf), fdTol);

% run each committed fixture and compare to the analytic oracle
variants = {'slim0', 'slim1'};
exTol = 1e-9;
J = cell(1, numel(variants));
F = zeros(1, numel(variants));
for k = 1:numel(variants)
    [Jk, Fk] = runFixture(fullfile(fixRoot, variants{k}), w, z);
    assert(norm(Jk - Jref, Inf) <= exTol, ...
        'gap_interproc_equiv:gradMismatch', ...
        '%s gradient != analytic: |dJ|_inf = %.3e > %.1e', ...
        variants{k}, norm(Jk - Jref, Inf), exTol);
    assert(abs(Fk - Fref) <= exTol, ...
        'gap_interproc_equiv:valueMismatch', ...
        '%s value != analytic: |dF| = %.3e > %.1e', ...
        variants{k}, abs(Fk - Fref), exTol);
    J{k} = Jk;
    F(k) = Fk;
end

% interprocedural-equivalence invariant: slimmed == unslimmed, exactly
dJ = norm(J{2} - J{1}, Inf);
dF = abs(F(2) - F(1));
assert(dJ == 0 && dF == 0, ...
    'gap_interproc_equiv:slimDrift', ...
    'slim1 not numerically identical to slim0: |dJ|_inf = %.3e, |dF| = %.3e', ...
    dJ, dF);

result = struct('w', w, 'z', z, 'Jref', Jref, 'Fref', Fref, 'Jfd', Jfd, ...
    'Jslim0', J{1}, 'Jslim1', J{2}, 'Fslim0', F(1), 'Fslim1', F(2));
fprintf(['gap_interproc_equiv: PASS  Jac=[%g; %g]  Fun=%g  ' ...
         '(slim0==slim1; FD |d|=%.1e)\n'], ...
        Jref(1), Jref(2), Fref, norm(Jfd - Jref, Inf));
end

% ----------------------------------------------------------------------- %
function [J, F] = runFixture(dir, w, z)
% Execute one committed fixture. slim0 and slim1 share the entry name
% gapfun_Grd (each a self-contained inline file), so cd into the variant and
% clear it (and the derivative name, harmless when it is an inline local) to
% force a reload of the current folder's copy. Reset the lazy-load global too:
% it is unused by inline fixtures but, for a classic-mode capture, prevents the
% second variant silently reusing the first's loaded data - so the runner stays
% fixture-shape agnostic and never compares a fixture against itself.
old     = cd(dir);
restore = onCleanup(@() cd(old)); %#ok<NASGU>
clear('gapfun_Grd', 'gapfun_ADiGatorGrd');
resetGlobal();
[J, F] = gapfun_Grd(w, z);
J = reshape(J, [], 1);
end

% ----------------------------------------------------------------------- %
function resetGlobal()
% Empty the lazy-load global so a classic fixture's ADiGator_LoadData() reloads
% from the current folder (the fixture reloads iff the global is empty). A no-op
% for inline fixtures, which embed their data and declare no such global.
global ADiGator_gapfun_ADiGatorGrd
ADiGator_gapfun_ADiGatorGrd = [];
end

% ----------------------------------------------------------------------- %
function g = fdgrad(fun, x)
% central finite-difference gradient of a scalar function
n = numel(x);
g = zeros(n, 1);
h = 1e-6;
for i = 1:n
    e = zeros(n, 1);
    e(i) = h;
    g(i) = (fun(x + e) - fun(x - e)) / (2*h);
end
end

% ----------------------------------------------------------------------- %
function restoreEnv(p, d)
path(p);
cd(d);
end
