function adigatorAssertNumericOutput(adiout, UserFunName, component)
%ADIGATORASSERTNUMERICOUTPUT  Guard: a derivative generator's user function must
% return a single NUMERIC output, not a struct or cell.
%
%   adigatorAssertNumericOutput(adiout, UserFunName, component)
%
% The derivative generators (adigatorGenJacFile, adigatorGenHesFile,
% adigatorGenRevGradFile) differentiate a single numeric output. When the user
% function instead returns a struct or cell, the core adigator() transform
% succeeds (the output comes back as a plain struct/cell whose fields/elements
% are cada objects, the wrapper having been unwrapped by adigatorFunctionEnd),
% and the generator then dies much later with a cryptic internal error - e.g.
% MATLAB's own "Unrecognized field name 'func'" (GenJac/GenHes) or an
% "adigator:fwdtape:parse ... cannot parse generated statement" (reverse) -
% after a wasted transformation and a truncated wrapper left on disk (#164).
%
% Called immediately after the user-function adigator() call, this turns that
% into an actionable error naming the function, the returned class, and the two
% ways forward. `component` picks the per-generator error id
% (adigator:<component>:structOutput), e.g. 'genjac' / 'genhes' / 'revgrad'.
% The caller is responsible for restoring the path first if it is still
% modified at the call site (GenHes) - this helper only validates and throws.
%
% Copyright Pedro Lourenço and GMV.
% Changelog:
%   2026-07    Created (#164): shared numeric-output guard for the derivative
%              generators, replacing the cryptic downstream failures.
% Distributed under the GNU General Public License version 3.0

if isa(adiout,'cada')
  return
end
if isstruct(adiout)
  whatis = 'a struct (with cada fields)';
elseif iscell(adiout)
  whatis = 'a cell';
else
  whatis = ['a ',class(adiout)];
end
error(['adigator:',component,':structOutput'], ...
  ['%s returned %s, but the derivative generators require a single ',...
   'differentiable numeric output (a cada). Return the numeric array ',...
   '(assemble any struct/cell from it AFTER differentiation), or call ',...
   'adigator() directly - the core transform supports struct/cell outputs.'], ...
   UserFunName, whatis);
end
