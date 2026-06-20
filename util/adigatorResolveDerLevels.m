function levels = adigatorResolveDerLevels(der_levels, maxlevel, caller)
% adigatorResolveDerLevels  Resolve and validate the DER_LEVELS option.
%
%   levels = adigatorResolveDerLevels(der_levels, maxlevel, caller)
%
%   DER_LEVELS (roadmap R7a, issue #21) selects which derivative levels a
%   generated wrapper returns: 0 = function value, 1 = first derivative
%   (gradient/Jacobian), 2 = Hessian.
%
%   Inputs:
%     der_levels  the user-supplied option value: a numeric vector of the
%                 requested levels, or [] for "all levels up to maxlevel".
%     maxlevel    the highest level the calling generator can produce
%                 (1 for Jacobian/gradient, 2 for Hessian).
%     caller      a string naming the calling generator (for error messages).
%
%   The top level (maxlevel) is always returned - a generated derivative file
%   must return the derivative it is named for - so DER_LEVELS only chooses
%   which lower-order outputs (0..maxlevel-1) accompany it. The default ([])
%   returns every level 0:maxlevel, so the historical wrapper signatures
%   ([Jac,Fun], [Hes,Grd,Fun], [Grd,Fun]) are reproduced exactly.
%
%   Output:
%     levels      a sorted row vector of the requested levels.
%
% Copyright GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorOptions, adigatorGenJacFile, adigatorGenHesFile

if isempty(der_levels)
  levels = 0:maxlevel;
  return;
end
if ~isnumeric(der_levels) || ~isvector(der_levels) ...
    || any(der_levels(:) ~= round(der_levels(:))) || any(der_levels(:) < 0)
  error('adigator:derLevels:type', ...
    ['%s: der_levels must be empty (all levels) or a vector of ', ...
     'nonnegative integers from {0,1,2} (0=function, 1=first derivative, ', ...
     '2=Hessian)'], caller);
end
levels = unique(der_levels(:).');
if any(levels > maxlevel)
  error('adigator:derLevels:range', ...
    ['%s: der_levels may not exceed %d for this derivative type ', ...
     '(0=function, 1=first derivative, 2=Hessian)'], caller, maxlevel);
end
if ~ismember(maxlevel, levels)
  error('adigator:derLevels:topmissing', ...
    ['%s: der_levels must include the top level %d - a generated ', ...
     'derivative file must return the derivative it is named for; use a ', ...
     'lower-order generator if you do not want that derivative'], ...
    caller, maxlevel);
end
end
