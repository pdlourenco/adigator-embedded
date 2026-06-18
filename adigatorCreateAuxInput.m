function x = adigatorCreateAuxInput(xsize,value)
% ADiGator auxiliary input variable creation routine.
%
% --------------------------- Usage ------------------------------------- %
%  x = adigatorCreateAuxInput(xsize)
% This function creates an input,x, (which has NO derivatives, but is not 
% a fixed value), that is to be used with the function source-to-derivative
% source transformation function, adigator.
%             OR
%  x = adigatorCreateAuxInput(xsize,value)
% This is useful if you have a vectorized input which is actually a fixed
% value. If the first dimension is vectorized, then value should be a row
% vector, if second dimension is vectorized, then value should be a column
% vector.
%
% ------------------------ Input Information ---------------------------- %
% xsize - size of auxiliary input variable, 1 by nd integer row vector
%         with nd >= 2
% value - fixed value of auxiliary input variable (optional, should ony be
% used with vectorized, known auxiliary inputs)
%
% --------------------- N-D Declarations (nd > 2) ----------------------- %
% An auxiliary input may be declared with more than two dimensions, e.g.
%  B = adigatorCreateAuxInput([m n K])
% Internally the input is treated as its 2D column-major fold of size
% [m, n*K] (reshape(B,m,[])); ()-references with three or more subscripts
% are interpreted in the declared shape, provided they are slices: a
% leading block of ':' subscripts followed by scalar subscripts, which may
% be loop counters or counter-derived, e.g. B(:,:,k) or B(:,:,a,k). Such a
% slice is rewritten as the equivalent affine column window on the fold
% and returns an ordinary 2D variable. All other operations (1- and
% 2-subscript references, size, length, concatenation, ...) see the 2D
% fold. The generated derivative file accepts the parameter either as the
% N-D array or as its 2D fold. N-D declarations cannot be vectorized (no
% Inf dimensions) and cannot take the fixed value argument.
%
% Copyright 2011-2014 Matthew J. Weinstein and Anil V. Rao
% Distributed under the GNU General Public License version 3.0
%
% Modifications as described below are Copyright GMV.
% Changelog:
%   2026-06    Accept N-D size declarations (more than two dimensions):
%              the input is folded to its 2D column-major form internally
%              and carries the declared shape for slice references in
%              @cada/subsref (roadmap R2, issue #11 Level 2, PR #14).
%
% See also: adigatorCreateDerivInput adigatorOptions adigator

if ~(isnumeric(xsize) && isrow(xsize) && length(xsize) >= 2 && ...
    isequal(xsize,floor(xsize)))
  error('first input xsize must be an integer row vector of length >= 2')
end
if length(xsize) > 2
  % N-D declared parameter (roadmap R2, issue #11 Level 2): fold to 2D and
  % keep the declared shape for slice references in @cada/subsref
  if any(isinf(xsize))
    error('adigator:ndparam:vectorized',...
      'N-D declared auxiliary inputs cannot be vectorized (no Inf dimensions)');
  end
  if nargin == 2
    error('adigator:ndparam:fixedValue',...
      ['the fixed value argument is only for vectorized auxiliary ',...
      'inputs and cannot be combined with an N-D declaration']);
  end
  func.size   = [xsize(1) prod(xsize(2:end))];
  func.ndsize = xsize;
  x = adigatorInput(func,[]);
  return
end
func.size = xsize;
if isinf(xsize(1)) && isinf(xsize(2))
  error('only one dimension of the input may be vectorized');
end

if nargin == 2
  valsize = size(value);
  if any(xsize(~isinf(xsize)) ~= valsize(~isinf(xsize))) || any(valsize(isinf(xsize))~=1)
    error('Invalue value input');
  end
  func.value = value;
end

x = adigatorInput(func,[]);
