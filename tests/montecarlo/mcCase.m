function c = mcCase(varargin)
%MCCASE  Build and validate a Monte-Carlo test case (issue #38, ADR-0007).
%
% A case is the generator-agnostic contract every oracle consumes: a
% self-contained single-input fixture function plus the metadata needed to
% generate its derivative, evaluate it, and check it.
%
%   c = mcCase('name', n, 'body', b, 'xsize', s, 'deriv', d, 'x0', x, ...)
%
% Required name/value pairs:
%   name   - char, a valid MATLAB identifier; the fixture is written as
%            `function y = <name>(x)` (single input, all constants inlined).
%   body   - char / string / cellstr: the fixture body line(s).
%   xsize  - 1x2 size of the variable of differentiation x.
%   deriv  - 'jacobian' | 'gradient' | 'hessian'.
%   x0     - numeric sample point of size xsize.
%
% Optional name/value pairs:
%   exactJac  - [] or @(x)->J, the analytic Jacobian in ADiGator's unrolled
%               [prod(ysize) x prod(xsize)] convention (m x n for n>1).
%   exactHess - [] or @(x)->H, the analytic Hessian (n x n) for a scalar f.
%   tags      - struct of free-form metadata (ops, shapes, density, order)
%               consumed by mcCoverage; defaults to an empty struct.
%
% The exact* handles are the "known-derivative-by-construction" oracle inputs
% (ADR-0007); leave them [] when no closed form is generated. M18: a []-exact
% case currently gets NO value oracle - no FD oracle exists yet (a later phase,
% ROADMAP R9 C-D; see tests/montecarlo/README.md) - so only the structural oracles
% (cross-mode agreement, sparsity superset, Hessian symmetry) apply; none
% checks the value against ground truth. Supply a closed form where one exists.

p = inputParser;
p.FunctionName = 'mcCase';
p.addParameter('name', '', @(v) ischar(v) || (isstring(v) && isscalar(v)));
p.addParameter('body', {});
p.addParameter('xsize', [], @(v) isnumeric(v) && numel(v) == 2);
p.addParameter('deriv', '', @(v) ischar(v) || isstring(v));
p.addParameter('x0', [], @isnumeric);
p.addParameter('exactJac', [], @(v) isempty(v) || isa(v,'function_handle'));
p.addParameter('exactHess', [], @(v) isempty(v) || isa(v,'function_handle'));
p.addParameter('tags', struct(), @isstruct);
p.parse(varargin{:});
r = p.Results;

name = char(r.name);
assert(~isempty(name) && isvarname(name), ...
    'mcCase:name', 'name must be a valid MATLAB identifier, got "%s"', name);

body = r.body;
if ischar(body) || isstring(body)
    body = cellstr(body);
end
assert(iscellstr(body) && ~isempty(body), ...
    'mcCase:body', 'body must be a non-empty char/string/cellstr');

deriv = lower(char(r.deriv));
assert(ismember(deriv, {'jacobian','gradient','hessian'}), ...
    'mcCase:deriv', 'deriv must be jacobian|gradient|hessian, got "%s"', deriv);

assert(numel(r.xsize) == 2 && all(r.xsize >= 1) && all(r.xsize == round(r.xsize)), ...
    'mcCase:xsize', 'xsize must be a 1x2 positive integer size');
assert(isequal(size(r.x0), r.xsize(:).'), ...
    'mcCase:x0', 'x0 must have size [%d %d]', r.xsize(1), r.xsize(2));

% gradient/hessian require a scalar-valued objective; that is a generator
% responsibility, but record the intent so oracles can rely on it.
c = struct( ...
    'name',      name, ...
    'body',      {body}, ...
    'xsize',     r.xsize(:).', ...
    'deriv',     deriv, ...
    'x0',        r.x0, ...
    'exactJac',  r.exactJac, ...
    'exactHess', r.exactHess, ...
    'tags',      r.tags);
end
