function [yName,yInds] = cadaRepDers(xName,xInds,ySize,Vcount,DPFLAG,targetInds)
% This function is used to repmat derivatives of scalar variables.
%
% The optional targetInds is the derivative pattern the result is about to be
% remapped into (cadaOverMapTargetNz, #217). Replicating a scalar's derivative
% across an array multiplies nonzero counts - nnz(scalar) * numel(array) - and
% in the printing run of a rolled loop both factors are loop overmaps, so the
% product can be quadratic where the union of the per-iteration results is
% linear. Given the target, the doomed locations are dropped here instead of
% being gathered onto the stack and thrown away by cadaPrintReMap one statement
% later.
%
% Copyright 2011-2014 Matthew J. Weinstein and Anil V. Rao
% Copyright 2026 Pedro Lourenço and GMV (#217 overmap-directed pruning)
% Distributed under the GNU General Public License version 3.0
global ADIGATOR
fid    = ADIGATOR.PRINT.FID;
indent = ADIGATOR.PRINT.INDENT;
NDstr  = sprintf('%1.0f',ADIGATOR.DERNUMBER);

nv = ADIGATOR.VAROFDIFF(Vcount).usize;
dx = sparse(xInds(:,1),xInds(:,2),1:size(xInds,1),1,nv);
dy = repmat(dx,ySize,1);

[yrows,ycols,yind] = find(dy);

if size(yrows,2) > 1
  yrows = yrows.'; ycols = ycols.';
end
yInds = [yrows,ycols];

if nargin > 5 && ~isempty(targetInds)
  keep = ismember(yInds,targetInds,'rows');
  % Prune only when something is left. An empty intersection would mean the
  % overmap disagrees with this operation about the variable having derivatives
  % at all; that is not this function's call to make, so hand the full pattern
  % on and let the existing remap machinery deal with it.
  if any(keep) && ~all(keep)
    yInds = yInds(keep,:);
    yind  = yind(keep);
  end
end

if DPFLAG
  yName = ['cada',NDstr,'tempd',ADIGATOR.VAROFDIFF(Vcount).name];
  Dind1 = cadaindprint(yind);
  fprintf(fid,[indent,yName,' = ',xName,'(',Dind1,');\n']);
else
  yName = xName;
end