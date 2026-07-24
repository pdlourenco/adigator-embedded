function S = adigatorCSCToSparse(csc, values)
%ADIGATORCSCTOSPARSE  Reconstruct a MATLAB sparse matrix from a CSC pattern.
%
%   S = adigatorCSCToSparse(csc, values)
%
% Host-only convenience that rebuilds the MATLAB `sparse(...)` object the v2.0
% CSC contract no longer exports (issue #192, ADR-0030 D6). NEVER an embedded
% dependency - it exists so host code and tests can compare a CSC value stream
% against the matrix-mode derivative.
%
% csc    : a struct as produced by adigatorBuildCSC.
% values : the Nnz x 1 CSC-ordered value vector returned by a `der_output='csc'`
%          derivative procedure. For the STRUCTURAL PATTERN alone, pass
%          ones(csc.Nnz,1):
%              pattern = adigatorCSCToSparse(csc, ones(csc.Nnz,1));
%
% Returns an csc.Size(1) x csc.Size(2) sparse matrix. Because the pattern is a
% structural superset, explicit zeros in `values` are dropped by `sparse` - the
% reconstructed matrix carries the numeric derivative, not the full pattern.
%
% See also adigatorBuildCSC, adigatorCSCToLocs.
%
% Copyright Pedro Lourenço and GMV.
% Changelog:
%   2026-07    Created (#192, ADR-0030, R31 Phase A): host-only CSC->sparse
%              reconstruction helper.
% Distributed under the GNU General Public License version 3.0

if numel(values) ~= csc.Nnz
    error('adigator:csctosparse:length', ...
        ['values must have csc.Nnz = %d elements to bind to the CSC pattern; ', ...
         'got %d.'], csc.Nnz, numel(values));
end
locations = adigatorCSCToLocs(csc);
S = sparse(locations(:, 1), locations(:, 2), values(:), ...
           csc.Size(1), csc.Size(2));
end
