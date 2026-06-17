function violations = test_norm_rules()
% Finite-difference check of the overloaded @cada/norm (issue #28) for the
% supported vector p-norms and the Frobenius norm, plus a check that the
% unsupported matrix (induced/spectral) norm errors cleanly and a smoke
% test of the isnan/isinf/isfinite predicate overloads.
%
% Mirrors the harness style of test_unarymath_rules.m: generate a small
% derivative file with adigator, then compare its gradient to central-ish
% finite differences. Returns the number of violations (0 = all good).

violations = 0;
if ~exist('tmp','dir'); mkdir('tmp'); end
addpath('tmp');

n = 4;
ps     = {2,    1,    Inf,   'fro'};
labels = {'2',  '1',  'Inf', 'fro'};

for k = 1:numel(ps)
  p   = ps{k};
  fn  = ['test_norm_', labels{k}];
  fid = fopen(fullfile('tmp',[fn,'.m']),'w+');
  fprintf(fid,'function y = %s(x)\n',fn);
  if ischar(p)
    fprintf(fid,'y = norm(x,''%s'');\n',p);
  else
    fprintf(fid,'y = norm(x,%s);\n',labels{k});   % 2 | 1 | Inf
  end
  fprintf(fid,'end\n');
  fclose(fid);
  rehash;

  ax    = adigatorCreateDerivInput([n 1],'x');
  dname = [fn,'_dx'];
  adigator(fn,{ax},dname,adigatorOptions('overwrite',1));
  movefile([dname,'.*'],'tmp'); rehash;

  rng(k);
  for t = 1:5
    % keep |x_i| away from 0 so the abs/max kinks of the 1- and inf-norms
    % do not confound the finite-difference comparison
    xv = randn(n,1); xv = sign(xv).*(abs(xv) + 0.5);

    xx.f = xv; xx.dx = ones(n,1);
    yy   = feval(dname,xx);

    g_ad = zeros(n,1);
    if isfield(yy,'dx_location') && ~isempty(yy.dx_location)
      g_ad(yy.dx_location(:,1)) = yy.dx;
    else
      g_ad(:) = yy.dx;
    end

    ee = 1e-6; g_fd = zeros(n,1); f0 = feval(fn,xv);
    for j = 1:n
      xp = xv; xp(j) = xp(j) + ee;
      g_fd(j) = (feval(fn,xp) - f0)/ee;
    end

    if norm(g_ad - g_fd)/(1 + norm(g_fd)) > 1e-4
      violations = violations + 1;
      fprintf('norm(x,%s): gradient mismatch at trial %d (err %.3g)\n', ...
        labels{k}, t, norm(g_ad - g_fd));
    end
  end
end

% --- the induced/spectral matrix norm must error cleanly, not mis-diff --- %
fid = fopen(fullfile('tmp','test_norm_mat.m'),'w+');
fprintf(fid,'function y = test_norm_mat(X)\ny = norm(X);\nend\n'); fclose(fid);
rehash;
try
  aX = adigatorCreateDerivInput([3 3],'X');
  adigator('test_norm_mat',{aX},'test_norm_mat_dx',adigatorOptions('overwrite',1));
  violations = violations + 1;
  fprintf('matrix norm(A) did NOT error as expected\n');
catch ME
  if ~(strcmp(ME.identifier,'adigator:norm:matrixNorm') || ...
       contains(lower(ME.message),'matrix'))
    violations = violations + 1;
    fprintf('matrix norm errored with an unexpected identifier: %s\n',ME.identifier);
  end
end
if exist(fullfile('tmp','test_norm_mat_dx.m'),'file')
  delete(fullfile('tmp','test_norm_mat_dx.*'));
end

% --- isnan/isinf/isfinite: derivative-free predicate, generation smoke --- %
fid = fopen(fullfile('tmp','test_pred.m'),'w+');
fprintf(fid,'function y = test_pred(x)\n');
fprintf(fid,'y = x.^2;\n');
fprintf(fid,'y(isnan(x) | isinf(x)) = 0;\n');   % predicate used in indexing
fprintf(fid,'end\n'); fclose(fid);
rehash;
try
  axp = adigatorCreateDerivInput([n 1],'x');
  adigator('test_pred',{axp},'test_pred_dx',adigatorOptions('overwrite',1));
  movefile('test_pred_dx.*','tmp'); rehash;
  xx.f = randn(n,1); xx.dx = ones(n,1);
  yy = feval('test_pred_dx',xx);          % must run without error
  g_ad = zeros(n,1);
  if isfield(yy,'dx_location') && ~isempty(yy.dx_location)
    g_ad(yy.dx_location(:,1)) = yy.dx;
  else
    g_ad(:) = yy.dx;
  end
  if norm(g_ad - 2*xx.f)/(1 + norm(2*xx.f)) > 1e-6   % d(x.^2)/dx = 2x
    violations = violations + 1;
    fprintf('isnan/isinf predicate path changed the derivative\n');
  end
catch ME
  violations = violations + 1;
  fprintf('isnan/isinf overload failed: %s\n',ME.message);
end

if violations == 0
  fprintf('test_norm_rules: all checks passed.\n');
end
end
