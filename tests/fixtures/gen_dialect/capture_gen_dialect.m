function capture_gen_dialect()
% capture_gen_dialect  Generator for the issue #44 part-1b equivalence
% fixtures. It lives next to the golden data it produces so the generator and
% the fixtures stay in sync. It generates the gapfun gradient derivative
% (gapfun calls subfunctions conefun/setfun, so the generated _ADiGator file is
% multi-subfunction) and, for both slim variants:
%   - the inline-embedded wrapper     gapfun_Grd.m   <-- the whole artifact
% Inline mode embeds the derivative + per-subfunction data functions into the
% wrapper and deletes the standalone _ADiGator*.m / .mat, both WITHOUT slimming
% (slim=0) and WITH it (slim=1, a genuinely sliced interprocedural file - the
% main function's unread f.dz_location/f.dz_size + their index table drop). The
% offline guard (gap_interproc_equiv) checks the two are numerically identical.
%
% ADiGator uses classdef heavily, so generation must run in MATLAB (Octave
% cannot run it). Run it from anywhere in the repo:
%       >> run tests/fixtures/gen_dialect/capture_gen_dialect.m
% It does two things:
%   (1) prints the generated dialect to the console, and
%   (2) writes the generated files into tests/fixtures/gen_dialect/slim{0,1}/.
% Commit the regenerated fixtures with:
%       git add tests/fixtures/gen_dialect
%       git commit -m "test(1b): regenerate gapfun generated derivative fixtures"
%       git push

orig = pwd;
here = fileparts(mfilename('fullpath'));            % tests/fixtures/gen_dialect
root = fileparts(fileparts(fileparts(here)));       % repo root
addpath(root);
addpath(fullfile(root,'lib'));
addpath(fullfile(root,'lib','cadaUtils'));
addpath(fullfile(root,'util'));
addpath(fullfile(root,'embedding'));
addpath(fullfile(root,'examples','optimization','pipg'));
cleanup = onCleanup(@() cd(orig)); %#ok<NASGU>

fprintf('MATLAB/Octave version: %s\n', version);
fixroot = here;

for doSlim = [0 1]
  outdir = fullfile(fixroot, sprintf('slim%d', doSlim));
  if isfolder(outdir); rmdir(outdir,'s'); end
  mkdir(outdir);
  cd(outdir);
  z = adigatorCreateDerivInput([2 1], 'z');
  w = adigatorCreateAuxInput([2 1]);
  % INLINE embed mode ('i'): slim_embed actually runs (it is skipped in classic
  % mode), so slim=1 is a genuinely sliced interprocedural file rather than a
  % byte-copy of slim=0. Inline embeds the derivative + per-subfunction data
  % functions into gapfun_Grd.m and deletes the standalone _ADiGator*.m/.mat.
  opts = struct('embed_mode','i','path',outdir,'echo',0, ...
                'overwrite',1,'slim_embed',doSlim);
  fprintf('\n############### GENERATION slim_embed=%d into %s\n', doSlim, outdir);
  try
    adigatorGenDerFile_embedded('gradient','gapfun',{w,z},opts);
  catch err
    fprintf('GENERATION FAILED (slim=%d): %s\n%s\n', doSlim, err.identifier, err.message);
    cd(orig);
    continue
  end
  cd(orig);
  % inline embeds the derivative + data functions into gapfun_Grd.m (the
  % standalone _ADiGator*.m / .mat are deleted), so that one file is the whole
  % artifact; dump the others only if a non-inline capture leaves them.
  dumpfile(sprintf('slim=%d  EMBEDDED WRAPPER  gapfun_Grd.m', doSlim), ...
           fullfile(outdir,'gapfun_Grd.m'));
  if isfile(fullfile(outdir,'gapfun_ADiGatorGrd.m'))
    dumpfile(sprintf('slim=%d  DERIV    gapfun_ADiGatorGrd.m', doSlim), ...
             fullfile(outdir,'gapfun_ADiGatorGrd.m'));
  end
  if isfile(fullfile(outdir,'gapfun_ADiGatorGrd.mat'))
    dumpmat(sprintf('slim=%d  MAT      gapfun_ADiGatorGrd.mat', doSlim), ...
            fullfile(outdir,'gapfun_ADiGatorGrd.mat'));
  end
end
fprintf('\n############### DONE\n');
end

% --------------------------------------------------------------------- %
function dumpfile(title, p)
fprintf('\n>>>>>>>>>> BEGIN %s <<<<<<<<<<\n', title);
if isfile(p)
  L = readlines(p);
  for i = 1:numel(L)
    fprintf('%s\n', L(i));
  end
else
  fprintf('(missing: %s)\n', p);
end
fprintf('>>>>>>>>>> END %s <<<<<<<<<<\n', title);
end

% --------------------------------------------------------------------- %
function dumpmat(title, p)
fprintf('\n>>>>>>>>>> BEGIN %s <<<<<<<<<<\n', title);
if isfile(p)
  s = load(p);
  fns = fieldnames(s);
  for i = 1:numel(fns)
    describe(s.(fns{i}), fns{i});
  end
else
  fprintf('(missing: %s)\n', p);
end
fprintf('>>>>>>>>>> END %s <<<<<<<<<<\n', title);
end

% --------------------------------------------------------------------- %
function describe(v, name)
if isstruct(v)
  fns = fieldnames(v);
  fprintf('%s : struct {%s}\n', name, strjoin(reshape(fns,1,[]), ', '));
  for i = 1:numel(fns)
    describe(v.(fns{i}), [name '.' fns{i}]);
  end
else
  fprintf('%s : size=%s class=%s\n', name, mat2str(size(v)), class(v));
end
end
