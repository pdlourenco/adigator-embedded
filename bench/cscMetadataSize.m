function rows = cscMetadataSize(varargin)
%CSCMETADATASIZE  Pattern-metadata size of the v2.0 CSC contract vs the removed
% coordinate/sparse surface (issue #192, ADR-0030 phase-C bench acceptance).
%
%   rows = cscMetadataSize('n', 8)
%
% The CSC break's win is in the PATTERN METADATA, not the runtime arithmetic:
% `der_output='csc'` returns the SAME structurally-possible-nonzero value vector
% as the removed `'nonzeros'` form (identical computation, so evaluation cost is
% unchanged), but the constant pattern is now a single CSC triple
% (Size/ColPtr/RowIdx) instead of the two redundant copies the old surface
% exported: the `nnz x 2` coordinate `*Locs` (2*nnz indices) AND the MATLAB
% sparse `*Structure` (a second full copy of the same pattern). This script
% measures that, for a few representative derivative shapes:
%
%   valuesN     nnz            (the returned value vector; identical old vs new)
%   cscIdx      nnz + ncols+1  (RowIdx + ColPtr - the sole exported pattern now)
%   coordIdx    2*nnz          (the old *Locs coordinate array)
%   oldPattern  coordIdx + cscIdx   (old exported BOTH: *Locs + sparse *Structure)
%   reduction   oldPattern / cscIdx (pattern-metadata index-count reduction)
%
% Interpretation lives in bench/SHOWCASE.md (## CSC pattern metadata).
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public License version 3.0.

p = inputParser;
p.addParameter('n', 8, @(x) isnumeric(x) && isscalar(x) && x >= 2);
p.addParameter('verbose', true, @(x) islogical(x) && isscalar(x));
p.parse(varargin{:});
n = p.Results.n;

root   = fileparts(fileparts(mfilename('fullpath')));   % repo root
addpath(root, fullfile(root,'lib'), fullfile(root,'lib','cadaUtils'), ...
        fullfile(root,'util'), fullfile(root,'embedding'), ...
        fullfile(root,'bench','showcase'), ...
        fullfile(root,'examples','jacobians','arrowhead'));

% Generate into an isolated working folder so the tree stays clean.
home = pwd;  wd = tempname;  mkdir(wd);
cleaner = onCleanup(@() cleanup(home, wd));
cd(wd);

% (anchor, DerType, label) - a spread of nnz/ncols ratios.
specs = {
    'scostfun', 'gradient', 'scalar-cost gradient [n x 1] (dense)'
    'arrowhead', 'jacobian', 'arrowhead Jacobian [n x n] (dense row+col)'
    'vfun',      'jacobian', 'diagonal Jacobian [n x n] (sparse)'
    'scostfun',  'hessian',  'scalar-cost Hessian [n x n] (diagonal)'
    };

rows = struct('label', {}, 'rows', {}, 'cols', {}, 'nnz', {}, ...
              'cscIdx', {}, 'coordIdx', {}, 'oldPattern', {}, 'reduction', {});
gx = adigatorCreateDerivInput([n 1], 'x');
for i = 1:size(specs, 1)
    fn = specs{i,1};
    switch specs{i,2}
        case 'gradient'
            out = adigatorGenJacFile(fn, {gx}, struct('overwrite',1,'echo',0), 'Grd');
            csc = out.GradientCSC;
        case 'jacobian'
            out = adigatorGenJacFile(fn, {gx}, struct('overwrite',1,'echo',0));
            csc = out.JacobianCSC;
        case 'hessian'
            out = adigatorGenHesFile(fn, {gx}, struct('overwrite',1,'echo',0));
            csc = out.HessianCSC;
    end
    ncols    = csc.Size(2);
    cscIdx   = numel(csc.ColPtr) + numel(csc.RowIdx);   % == nnz + ncols + 1
    coordIdx = 2 * csc.Nnz;                              % old *Locs
    oldPat   = coordIdx + cscIdx;                        % *Locs + sparse *Structure
    rows(end+1) = struct('label', specs{i,3}, ...
        'rows', csc.Size(1), 'cols', ncols, 'nnz', csc.Nnz, ...
        'cscIdx', cscIdx, 'coordIdx', coordIdx, 'oldPattern', oldPat, ...
        'reduction', oldPat / cscIdx); %#ok<AGROW>
end

if p.Results.verbose
    fprintf('\nCSC pattern-metadata size (n = %d)\n', n);
    fprintf('%-44s %5s %5s %5s | %8s %8s %10s %9s\n', ...
        'shape', 'rows', 'cols', 'nnz', 'cscIdx', 'coordIdx', 'oldPattern', 'reduction');
    for i = 1:numel(rows)
        r = rows(i);
        fprintf('%-44s %5d %5d %5d | %8d %8d %10d %8.2gx\n', ...
            r.label, r.rows, r.cols, r.nnz, r.cscIdx, r.coordIdx, r.oldPattern, r.reduction);
    end
    fprintf(['\nvalue vector (nnz doubles) is identical old vs new; evaluation ', ...
             'cost unchanged.\n']);
end
end

function cleanup(home, wd)
cd(home);
try
    rmdir(wd, 's');
catch
end
end
