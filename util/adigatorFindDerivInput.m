function [derflag, pathStr, pathSubs, derx] = adigatorFindDerivInput(UserFunInputs, callerName)
% Locate the single derivative-variable input for the Jacobian/Hessian
% wrapper generators (adigatorGenJacFile, adigatorGenHesFile).
%
% Unlike the original top-level-only search, this also looks recursively
% inside scalar-struct fields and cell contents, so the derivative variable
% may be carried as a field of a struct input (issue #24, scope A) -- e.g.
%   in.x = adigatorCreateDerivInput([n 1],'x');
%   in.p = adigatorCreateAuxInput([n 1]);
%   adigatorGenHesFile('myfun',{in});
%
% ----------------------------- Outputs -------------------------------- %
% derflag  - index (in UserFunInputs) of the top-level input that carries
%            the derivative variable.
% pathStr  - MATLAB access path of the derivative variable within that
%            input, as a string ('' when the input is itself the variable,
%            '.x', '.a.b', '{2}.x', ...). Append to the input name to read
%            the value in generated code.
% pathSubs - the same path as a substruct() chain, for programmatic
%            subsref/subsasgn on the live input (empty 0x0 when pathStr='').
% derx     - the located adigatorInput object (so callers can read
%            derx.func.size and derx.deriv as before).
%
% The single-derivative-variable and no-vectorized-input restrictions of
% the wrappers are preserved. Recursion descends scalar structs and cells
% to any depth; struct arrays (numel>1) are not descended into (left alone,
% as before), so a derivative variable carried inside a struct array is not
% found and surfaces as the usual "derivative input ... not found" error.
%
% Copyright Pedro Lourenço and GMV. 2026-06. Distributed under the GNU General
% Public License version 3.0.
%
% See also adigatorGenJacFile adigatorGenHesFile adigator

derflag  = 0;
pathStr  = '';
pathSubs = struct('type',{},'subs',{});
derx     = [];

for I = 1:numel(UserFunInputs)
  leaves = collectInputs(UserFunInputs{I}, '', struct('type',{},'subs',{}));
  for j = 1:numel(leaves)
    if any(isinf(leaves(j).obj.func.size))
      error('%s not written for vectorized functions', callerName);
    end
    if ~isempty(leaves(j).obj.deriv)
      if derflag > 0
        error('%s is only used for single derivative variable input', callerName);
      end
      derflag  = I;
      pathStr  = leaves(j).pathStr;
      pathSubs = leaves(j).pathSubs;
      derx     = leaves(j).obj;
    end
  end
end

if derflag == 0
  error(['derivative input of user function not found (searched top-level ',...
    'inputs and the fields/elements of struct and cell inputs)']);
end

end

function L = collectInputs(val, pathStr, pathSubs)
% Recursively collect all adigatorInput leaves, with their access paths.
L = struct('pathStr',{},'pathSubs',{},'obj',{});
if isa(val,'adigatorInput')
  L(1).pathStr  = pathStr;
  L(1).pathSubs = pathSubs;
  L(1).obj      = val;
elseif isstruct(val) && isscalar(val)
  % only scalar structs are descended into; struct arrays are left alone
  % (as before, they cannot carry the single derivative variable here)
  fn = fieldnames(val);
  for k = 1:numel(fn)
    L = [L, collectInputs(val.(fn{k}), [pathStr,'.',fn{k}], ...
      [pathSubs, substruct('.',fn{k})])]; %#ok<AGROW>
  end
elseif iscell(val)
  for k = 1:numel(val)
    L = [L, collectInputs(val{k}, [pathStr,'{',int2str(k),'}'], ...
      [pathSubs, substruct('{}',{k})])]; %#ok<AGROW>
  end
end
end
