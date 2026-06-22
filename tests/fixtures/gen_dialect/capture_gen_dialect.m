function capture_gen_dialect()
% capture_gen_dialect  Generator for the issue #44 part-1b equivalence
% fixtures. It lives next to the golden data it produces so the generator and
% the fixtures stay in sync. It generates the gapfun gradient derivative
% (gapfun calls subfunctions conefun/setfun, so the generated _ADiGator file is
% multi-subfunction) and, for both slim variants:
%   - the generated wrapper           gapfun_Grd.m
%   - the generated derivative file   gapfun_ADiGatorGrd.m   <-- the key artifact
%   - the .mat field/layout           gapfun_ADiGatorGrd.mat
% both WITHOUT slimming (slim=0, the raw dialect the slice will consume) and
% WITH the current slim (slim=1, what today's intra-function engine leaves).
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
  opts = struct('embed_mode','c','path',outdir,'echo',0, ...
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
  dumpfile(sprintf('slim=%d  WRAPPER  gapfun_Grd.m', doSlim), ...
           fullfile(outdir,'gapfun_Grd.m'));
  dumpfile(sprintf('slim=%d  DERIV    gapfun_ADiGatorGrd.m', doSlim), ...
           fullfile(outdir,'gapfun_ADiGatorGrd.m'));
  dumpmat(sprintf('slim=%d  MAT      gapfun_ADiGatorGrd.mat', doSlim), ...
          fullfile(outdir,'gapfun_ADiGatorGrd.mat'));
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
