function [csc, perm, isIdentity] = adigatorBuildCSC(size_, locations)
%ADIGATORBUILDCSC  Canonical compressed-sparse-column (CSC) pattern builder.
%
%   [csc, perm, isIdentity] = adigatorBuildCSC(size_, locations)
%
% The single canonicalizer behind the v2.0 `der_output` CSC contract
% (issue #192, ADR-0030 D5). Every derivative generator routes its structural
% pattern through this function so the exported metadata, the value order, and
% the invariant checks all come from one place.
%
% ------------------------------ Inputs ----------------------------------
% size_     : [nrows, ncols] - the returned derivative's shape (C-1). Both
%             non-negative integers.
% locations : Nnz x 2 array of [row, col] one-based subscripts, in the NATIVE
%             order the generated derivative procedure returns its value stream
%             (for an ordinary Jacobian this is `[I,J] = find(Jac)` order, i.e.
%             already column-major with rows ascending within each column).
%             May be empty (0 x 2) for a structurally empty derivative.
%
% ------------------------------ Outputs ---------------------------------
% csc  : struct with the sole public pattern representation (ADR-0030 D2)
%          .Size      = [nrows, ncols]
%          .ColPtr    = column vector, length ncols+1; ColPtr(1)==1,
%                       ColPtr(end)==Nnz+1, non-decreasing; empty columns are
%                       adjacent equal pointers.
%          .RowIdx    = column vector, length Nnz; the CSC-ordered row indices,
%                       strictly increasing within each column.
%          .Nnz       = double scalar, number of structurally possible nonzeros.
%          .IndexBase = 1.
%        ColPtr/RowIdx are uint32 (ADR-0030 D4) when both nrows and Nnz+1 fit in
%        uint32; otherwise they fall back to double with a warning rather than
%        saturating (a silent saturation would be a principle-1 wrong-gather).
%        They are column vectors so they parallel the Nnz x 1 value stream and
%        MATLAB's own find() convention.
% perm : Nnz x 1 double gather index from native to CSC order, i.e.
%        cscValues = nativeValues(perm). The generation-time permutation a
%        generator applies as a CONSTANT gather when the native order is not
%        already CSC order - never a runtime sort.
% isIdentity : logical; true iff perm == (1:Nnz).', i.e. the native value
%        stream is already in CSC order and no gather is needed. Expected true
%        for ordinary Jacobian / gradient / Hessian streams (the remap cases are
%        the watch item - ADR-0030 §Decision 5 / Context).
%
% Structural locations must be unique and in range; runtime numeric values may
% be zero (the pattern is a structural superset - REQ-T-03).
%
% See also adigatorCSCToLocs, adigatorCSCToSparse.
%
% Copyright Pedro Lourenço and GMV.
% Changelog:
%   2026-07    Created (#192, ADR-0030, R31 Phase A): the CSC canonicalizer
%              and identity/permutation analysis shared by every generator.
% Distributed under the GNU General Public License version 3.0

%% ---- validate size_ -------------------------------------------------- %%
if ~isnumeric(size_) || ~isreal(size_) || numel(size_) ~= 2
    error('adigator:buildcsc:size', ...
        'size_ must be a numeric [nrows, ncols] pair.');
end
nrows = double(size_(1));
ncols = double(size_(2));
if any([nrows ncols] < 0) || any([nrows ncols] ~= floor([nrows ncols]))
    error('adigator:buildcsc:size', ...
        'size_ entries must be non-negative integers; got [%g %g].', nrows, ncols);
end

%% ---- validate locations ---------------------------------------------- %%
if isempty(locations)
    locations = zeros(0, 2);
end
if ~isnumeric(locations) || ~isreal(locations) || ~ismatrix(locations) || ...
        size(locations, 2) ~= 2
    error('adigator:buildcsc:locShape', ...
        'locations must be an Nnz x 2 array of [row, col] subscripts.');
end
Nnz = size(locations, 1);
if Nnz > 0
    if any(locations(:) ~= floor(locations(:)))
        error('adigator:buildcsc:notInteger', ...
            'locations must be integer [row, col] subscripts.');
    end
    rows = locations(:, 1);
    cols = locations(:, 2);
    if any(rows < 1) || any(rows > nrows) || any(cols < 1) || any(cols > ncols)
        error('adigator:buildcsc:outOfRange', ...
            ['locations must lie within [1,nrows] x [1,ncols] = ', ...
             '[1,%d] x [1,%d].'], nrows, ncols);
    end
    if size(unique(locations, 'rows'), 1) ~= Nnz
        error('adigator:buildcsc:duplicate', ...
            'locations must be unique; a structural nonzero is listed twice.');
    end
end

%% ---- order by (column, row); derive the native->CSC permutation ------ %%
% sortrows priority [2 1] = column first, then row: exactly CSC order.
[sortedLoc, perm] = sortrows(locations, [2 1]);
perm = perm(:);
isIdentity = isequal(perm, (1:Nnz).');

rowIdx = sortedLoc(:, 1);            % strictly increasing within each column
sortedCols = sortedLoc(:, 2);

%% ---- column pointers (empty columns as adjacent equal pointers) ------ %%
if Nnz > 0
    counts = accumarray(sortedCols, 1, [ncols 1]);
else
    counts = zeros(ncols, 1);
end
colPtr = [1; 1 + cumsum(counts)];   % length ncols+1; colPtr(end) == Nnz+1

%% ---- index class policy (ADR-0030 D4): uint32 with a range guard ----- %%
maxIndex = max([nrows, Nnz + 1]);   % RowIdx <= nrows; ColPtr <= Nnz+1
if maxIndex <= double(intmax('uint32'))
    colPtr = uint32(colPtr);
    rowIdx = uint32(rowIdx);
else
    warning('adigator:buildcsc:indexRange', ...
        ['CSC index range %g exceeds intmax(''uint32''); falling back to ', ...
         'double index metadata rather than saturating.'], maxIndex);
end

%% ---- assemble ------------------------------------------------------- %%
csc = struct('Size', [nrows ncols], ...
             'ColPtr', colPtr, ...
             'RowIdx', rowIdx, ...
             'Nnz', double(Nnz), ...
             'IndexBase', 1);
end
