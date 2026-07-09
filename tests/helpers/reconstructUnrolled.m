function D = reconstructUnrolled(y, m, n)
% RECONSTRUCTUNROLLED  Dense [m x n] unrolled Jacobian from the raw C-2 fields.
%
% Given the struct y returned by a raw adigator-generated derivative file
% evaluated with the identity seed (y.dX / y.dX_location / y.dX_size, DESIGN
% Contract C-2), rebuild the dense unrolled Jacobian [numel(y_out) x numel(x)].
% Used by the C-2 interface tests (CI_PLAN TS-U-02/03).
%
% Handles both storage regimes:
%   - sparse: y.dX are the possible-nonzeros, y.dX_location has one column per
%     dimension in y.dX_size (2 columns for a Jacobian, 1 when a dimension is
%     trivial, e.g. a scalar variable of differentiation);
%   - dense: no y.dX_location (or empty) -> y.dX is the full column-major fill.
%
% Asserts the normalized y.dX_size is [m n] (the interface-shape check itself).
%
% Assumes the variable of differentiation is named 'x' (so the derivative fields
% are dx / dx_location / dx_size), as both callers (TS-U-02/03) create it.

sz = double(y.dx_size(:)).';
if isscalar(sz); sz = [sz 1]; end
assert(isequal(sz, [m n]), ...
    'dx_size normalized to [%s], expected [%d %d]', num2str(sz), m, n);

D = zeros(m, n);
if isfield(y, 'dx_location') && ~isempty(y.dx_location)
    loc = y.dx_location;
    if size(loc, 2) >= 2
        lin = sub2ind([m n], loc(:,1), loc(:,2));
    else
        lin = loc(:,1);                 % trivial second dimension (n==1)
    end
    assert(numel(unique(lin)) == numel(lin), ...
        'dx_location entries must be distinct');
    D(lin) = y.dx;
else
    D(:) = y.dx;                        % dense derivative, column-major
end
end
