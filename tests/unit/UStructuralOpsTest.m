classdef UStructuralOpsTest < matlab.unittest.TestCase
    % UStructuralOpsTest  Structural-operation derivative rules.
    %
    % CI plan: TS-U-03, verifies REQ-C-03 and the DESIGN C-2 generated-file
    % evaluation interface (the raw y.dX / y.dX_location / y.dX_size fields).
    % Each fixture exercises one structural op (concatenation, gather/indexing
    % with duplicate indices, indexed-assignment scatter, transpose, reshape,
    % sum, mtimes) with a VECTOR output, so the unrolled derivative is a plain
    % [numel(y) x numel(x)] Jacobian. The raw fields are reconstructed via
    % dX_size + dX_location (C-2: one location column per dimension, nonzeros in
    % ascending linear order) and checked against a dense finite-difference
    % Jacobian - the check that would have caught a structural-op location/size
    % corruption at the source-interface level, below the wrapper.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
            tc.applyFixture(PathFixture(fullfile(root,'tests','helpers')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
            rng(7);
        end
    end

    methods (Test)
        function concatenation(tc)
            checkStructuralOp(tc, 'concat', 'y = [x(1:2); x(2:3); x(1)+x(3)];', 3);
        end

        function gatherWithDuplicateIndices(tc)
            % duplicate index (x(2) twice) exercises the gather map, not a
            % permutation - a classic place for a location/dedup slip
            checkStructuralOp(tc, 'gather', 'y = x([3 1 2 2]);', 3);
        end

        function indexedAssignmentScatter(tc)
            checkStructuralOp(tc, 'scatter', ...
                {'v = zeros(4,1);', 'v([1 3]) = x(1:2);', ...
                 'v(2) = x(3);', 'v(4) = x(1) + x(3);', 'y = v;'}, 3);
        end

        function transpose(tc)
            % transpose to a row and back; y stays a column vector
            checkStructuralOp(tc, 'transpose', ...
                {'r = x.'';', 'y = [r.''; r(2)];'}, 3);
        end

        function reshapeRoundTrip(tc)
            % reshape into a matrix and (implicitly) back through M(:)
            checkStructuralOp(tc, 'reshape', ...
                {'M = reshape(x, 2, 3);', 'y = M(:) + [M(:,1); M(:,2); M(:,3)];'}, 6);
        end

        function sumReduction(tc)
            checkStructuralOp(tc, 'sum', 'y = [sum(x); x(1) - x(2)];', 3);
        end

        function matrixTimesVector(tc)
            checkStructuralOp(tc, 'mtimes', ...
                {'A = [1 2 3; 4 5 6];', 'y = A*x;'}, 3);
        end
    end
end

%% ============================ helpers ================================ %%
function checkStructuralOp(tc, name, body, n)
% Generate y = f(x) for a [n x 1] input, evaluate the RAW generated file with
% the identity seed, reconstruct the unrolled derivative from the C-2 fields,
% and assert size + values against a dense finite-difference Jacobian.
fname = ['ust_', name];
writeVecFixture(fname, body);
dname = [fname, '_dx'];
ax = adigatorCreateDerivInput([n 1], 'x');
adigator(fname, {ax}, dname, adigatorOptions('overwrite',1,'echo',0));
rehash;

xv = 0.5 + rand(n,1);                 % away from 0 (safe for the FD compare)
xx.f = xv; xx.dx = ones(n,1);         % identity seed: the VOD's nonzero values
yy = feval(dname, xx);

m = numel(feval(fname, xv));

% C-2: reconstruct the dense unrolled [m x n] Jacobian from the raw
% y.dX / y.dX_location / y.dX_size fields (the helper asserts the interface
% shape) and compare to finite differences.
D = reconstructUnrolled(yy, m, n);
Jfd = fdcheck('jac', @(z) feval(fname, z), xv);
tc.verifyEqual(D, Jfd, 'AbsTol', 1e-5, 'RelTol', 1e-5, ...
    sprintf('%s: reconstructed derivative disagrees with finite differences', name));
end

function writeVecFixture(name, body)
if ischar(body) || isstring(body); body = {char(body)}; end
fid = fopen([name,'.m'], 'w');
assert(fid > 0, 'could not create fixture %s', name);
fprintf(fid, 'function y = %s(x)\n', name);
fprintf(fid, '%s\n', body{:});
fprintf(fid, 'end\n');
fclose(fid);
rehash;
end
