function output = adigatorGenJtVFile(UserFun,UserFunInputs,varargin)
%ADIGATORGENJTVFILE  Generate a transposed-Jacobian-vector product file.
%
% output = adigatorGenJtVFile(UserFun,UserFunInputs)
% output = adigatorGenJtVFile(UserFun,UserFunInputs,options)
%
% Generates <UserFun>_JtV.m with the signature
%
%   [Jtv, Fun] = <UserFun>_JtV(<original inputs...>, v)
%
% (DESIGN Contract C-6: derivative first, value last) where Fun = f(x,...)
% is the (vector) output of the user function and
% Jtv = J(x).'*v(:) is the transposed-Jacobian-vector product - the
% quantity gradient-based embedded solvers consume directly (ANALYSIS.md
% 2.3, roadmap R5). v is a RUNTIME input the size of y: one generated
% file serves every v, and the cost of jtv is one forward plus one
% adjoint sweep of f, independent of numel(x).
%
% Mechanism: the reverse engine of adigatorGenRevGradFile, with the
% adjoint of the output seeded by v instead of 1, so the same
% restrictions apply (exactly one derivative input; no rolled control
% flow - use adigatorOptions('unroll',1) for loops; supported operation
% set per adigatorGenRevGradFile). UserFunInputs are exactly the inputs
% of the user function; v does not participate in the generation.
%
% options: overwrite, path, echo, unroll are forwarded.
%
% Copyright Pedro Lourenço and GMV.
% Changelog:
%   2026-06    Created (roadmap R5, ANALYSIS.md 2.3, on the R4 reverse
%              engine).
%
% See also adigatorGenRevGradFile adigatorGenJacFile adigatorOptions

opts = adigatorOptions();
opts.overwrite = 1;
if nargin > 2
  optfields = fieldnames(varargin{1});
  for Fcount = 1:length(optfields)
    % read the user's field as given, lower-case only the destination (B12)
    opts.(lower(optfields{Fcount})) = varargin{1}.(optfields{Fcount});
  end
end
if ~ischar(UserFun)
  error('adigator:jtv:inputs','UserFun must be a function name string');
end
if ~iscell(UserFunInputs)
  error('adigator:jtv:inputs','UserFunInputs must be a cell array');
end

opts.filename = [UserFun,'_JtV'];
opts.seedname = 'cadaJtV_v';
output = adigatorGenRevGradFile(UserFun,UserFunInputs,opts);
output.JtVName = opts.filename;
end
