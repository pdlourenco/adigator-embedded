function locations = adigatorCSCToLocs(csc)
%ADIGATORCSCTOLOCS  Reconstruct [row, col] locations from a CSC pattern.
%
%   locations = adigatorCSCToLocs(csc)
%
% Host-only convenience inverse of adigatorBuildCSC's pattern (issue #192,
% ADR-0030 D6). Returns the Nnz x 2 array of one-based [row, col] subscripts in
% CSC (column-major, row-ascending-within-column) order - the order the CSC
% value stream is bound to. NEVER an embedded dependency: generated derivative
% procedures consume ColPtr/RowIdx directly and never call this.
%
% csc is a struct as produced by adigatorBuildCSC (fields Size, ColPtr, RowIdx,
% Nnz, IndexBase). Index metadata may be uint32 or double; the returned
% locations are double.
%
% See also adigatorBuildCSC, adigatorCSCToSparse.
%
% Copyright Pedro Lourenço and GMV.
% Changelog:
%   2026-07    Created (#192, ADR-0030, R31 Phase A): host-only CSC->locs
%              reconstruction helper.
% Distributed under the GNU General Public License version 3.0

colPtr = double(csc.ColPtr(:));
rowIdx = double(csc.RowIdx(:));
ncols  = csc.Size(2);
nnz_   = csc.Nnz;

colOfEntry = zeros(nnz_, 1);
for j = 1:ncols
    colOfEntry(colPtr(j):colPtr(j+1)-1) = j;
end
locations = [rowIdx, colOfEntry];
end
