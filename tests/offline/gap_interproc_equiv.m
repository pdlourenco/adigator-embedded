function result = gap_interproc_equiv()
%GAP_INTERPROC_EQUIV  License-free equivalence guard for issue #44 part 1b.
%
% Runs in BOTH MATLAB and GNU Octave (no license, no classdef, no codegen):
% it only *executes* the committed, already-generated gapfun gradient
% fixtures, it does not regenerate them. Generation still needs MATLAB
% (docs/CI_PLAN.md), so the fixtures are captured on MATLAB and committed
% under tests/fixtures/gen_dialect/ by its capture_gen_dialect.m. This is the
% plain-assert core that consumes them, wrapped for the MATLAB CI gate by
% tests/integration/IInterprocGapEquivTest.
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
%       one (slim0). This is the interprocedural-equivalence invariant: today
%       the engine does no cross-call slimming so slim0 and slim1 happen to be
%       byte-identical and (3) is trivially true; once part 1b implements
%       interprocedural under-demand and the fixtures are regenerated, slim1's
%       index tables will shrink while its NUMBERS must not move - that is when
%       this guard bites. The contract is numeric, not structural, so (3)
%       compares results (AbsTol 0), never bytes or index layout.
%
% On any mismatch it errors, so it fails a bare Octave run and the
% matlab.unittest wrapper alike. Returns a struct with the computed
% quantities for the wrapper to re-assert.
%
% Usage (license-free, from the repo root; the absolute path matters because
% the fixtures cd elsewhere and a relative path entry would go stale):
%   octave --quiet --eval "addpath(fullfile(pwd,'tests','offline')); gap_interproc_equiv"

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
fixRoot = fullfile(root, 'tests', 'fixtures', 'gen_dialect');
srcDir  = fullfile(root, 'examples', 'optimization', 'pipg');

% restore the path and working directory whatever happens (the fixtures cd
% into their own folders and rely on bare load('...mat') relative to cwd)
origPath = path();
origPwd  = pwd();
cleanup  = onCleanup(@() restoreEnv(origPath, origPwd)); %#ok<NASGU>
addpath(srcDir);

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
% Execute one committed fixture. slim0 and slim1 share the function names
% gapfun_Grd / gapfun_ADiGatorGrd and a single global, so clear both and reset
% the global before each run: otherwise the second variant would silently reuse
% the first's loaded .mat and the guard would compare a fixture against itself.
old     = cd(dir);
restore = onCleanup(@() cd(old)); %#ok<NASGU>
clear('gapfun_Grd', 'gapfun_ADiGatorGrd');
resetGlobal();
[J, F] = gapfun_Grd(w, z);
J = reshape(J, [], 1);
end

% ----------------------------------------------------------------------- %
function resetGlobal()
% Force the fixture's lazy ADiGator_LoadData() to reload from the current
% folder's .mat (the fixture reloads iff the global is empty).
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
