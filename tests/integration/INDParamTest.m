classdef INDParamTest < matlab.unittest.TestCase
    % INDParamTest  Roadmap R2 acceptance test (issue #11 Level 2): N-D
    % declared auxiliary parameters, folded internally to 2D, with
    % trailing-subscript slice references (B(:,:,k), B(:,:,a,k), ...)
    % rewritten as affine column windows on the fold - including loop
    % counters and multi-counter windows - and the guards that keep the
    % veneer's semantics unambiguous.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function sliceFormsOutsideLoop(tc)
            % fixed-index slices in all supported forms, incl. 'end' and a
            % scalar element; generated file accepts 3D and folded args
            writeFcn('ndp_basic', { ...
                'function y = ndp_basic(x,B)', ...
                'S = B(:,:,2);', ...
                'c = B(:,1,3);', ...
                'e = B(:,:,end);', ...
                'b = B(1,2,4);', ...
                'y = S*(x.^2) + c*(b*x(1)) + e*x;', ...
                'end'});
            m = 3; n = 2; K = 4;
            gx = adigatorCreateDerivInput([n 1],'x');
            gB = adigatorCreateAuxInput([m n K]);
            adigator('ndp_basic',{gx,gB},'ndp_basic_dx', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            rng(1);
            B = randn(m,n,K);
            xf = randn(n,1);
            x.f = xf; x.dx = ones(n,1);
            y = ndp_basic_dx(x,B);
            J = full(sparse(y.dx_location(:,1), y.dx_location(:,2), ...
                y.dx, y.dx_size(1), y.dx_size(2)));

            tc.verifyEqual(y.f, ...
                B(:,:,2)*(xf.^2) + B(:,1,3)*(B(1,2,4)*xf(1)) + B(:,:,4)*xf, ...
                'AbsTol', 1e-12, 'RelTol', 1e-12);
            Ja = B(:,:,2)*diag(2*xf) + ...
                [B(1,2,4)*B(:,1,3), zeros(m,n-1)] + B(:,:,4);
            tc.verifyEqual(J, Ja, 'AbsTol', 1e-12, 'RelTol', 1e-12);

            % same file, folded 2D argument: identical results
            y2 = ndp_basic_dx(x, reshape(B,m,[]));
            tc.verifyEqual(y2.f,  y.f,  'AbsTol', 0);
            tc.verifyEqual(y2.dx, y.dx, 'AbsTol', 0);
        end

        function foldedEndReferenceResolvesToFold(tc)
            % M12 (issue #11): B(:,end) - the 2-subscript FOLDED reference into
            % an N-D declared parameter - must resolve `end` to the folded
            % trailing extent (func.size(2)), the fold form subsref.m supports.
            % Pre-fix `end` routed through size(x,2) -> the size(...,dim>1)
            % rejection in size.m and errored (adigator:ndparam:size), even
            % though that rejection's own message points at this fold form.
            % exercises `end` in BOTH fold positions: dim=2 (B(:,end)) and
            % dim=1 (B(end,1)), so the new branch's func.size(1)/func.size(2)
            % legs are both pinned.
            writeFcn('ndp_foldend', { ...
                'function y = ndp_foldend(x,B)', ...
                'c = B(:,end);', ...   % last folded column [m x 1], end in dim 2
                'd = B(:,1);', ...     % first folded column (control)
                'e = B(end,1);', ...   % scalar Bf(m,1), end in dim 1
                'y = c*sum(x) + d*x(1) + (e*d)*x(2);', ...
                'end'});
            m = 3; n = 2; K = 4;
            gx = adigatorCreateDerivInput([n 1],'x');
            gB = adigatorCreateAuxInput([m n K]);
            adigator('ndp_foldend',{gx,gB},'ndp_foldend_dx', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            rng(4);
            B = randn(m,n,K);
            xf = randn(n,1);
            x.f = xf; x.dx = ones(n,1);
            y = ndp_foldend_dx(x,B);
            J = full(sparse(y.dx_location(:,1), y.dx_location(:,2), ...
                y.dx, y.dx_size(1), y.dx_size(2)));

            Bf = reshape(B,m,[]);          % the internal 2D fold
            c  = Bf(:,end);                % MATLAB's own B(:,end)   (dim 2)
            d  = Bf(:,1);
            e  = Bf(end,1);                % MATLAB's own B(end,1)   (dim 1)
            tc.verifyEqual(y.f, c*sum(xf) + d*xf(1) + (e*d)*xf(2), ...
                'AbsTol', 1e-12, 'RelTol', 1e-12);
            % analytic: c*1 every column (c*sum(x)) + d in col 1 + e*d in col 2
            Ja = c*ones(1,n) + [d, zeros(m,n-1)] + [zeros(m,1), e*d];
            tc.verifyEqual(J, Ja, 'AbsTol', 1e-12, 'RelTol', 1e-12);

            % same file, folded 2D argument: identical results
            y2 = ndp_foldend_dx(x, Bf);
            tc.verifyEqual(y2.f,  y.f,  'AbsTol', 0);
            tc.verifyEqual(y2.dx, y.dx, 'AbsTol', 0);
        end

        function counterSliceMatchesManualFold(tc)
            % B(:,:,k) by the loop counter inside a rolled loop must agree
            % with the proven manual folded-2D pattern Bf(:,(k-1)*n+(1:n))
            % - this is the equivalence contract of the Level-2 veneer
            writeFcn('ndp_loop', { ...
                'function y = ndp_loop(x,B)', ...
                'K = 4; m = 3;', ...
                'g = x + x.^3/6;', ...
                'y = zeros(m*K,1);', ...
                'for k = 1:K', ...
                '  y((k-1)*m+(1:m)) = B(:,:,k)*g;', ...
                'end', ...
                'end'});
            writeFcn('ndp_loop_fold', { ...
                'function y = ndp_loop_fold(x,Bf)', ...
                'K = 4; m = 3; n = 2;', ...
                'g = x + x.^3/6;', ...
                'y = zeros(m*K,1);', ...
                'for k = 1:K', ...
                '  y((k-1)*m+(1:m)) = Bf(:,(k-1)*n+(1:n))*g;', ...
                'end', ...
                'end'});
            m = 3; n = 2; K = 4;
            gx = adigatorCreateDerivInput([n 1],'x');
            gB = adigatorCreateAuxInput([m n K]);
            adigator('ndp_loop',{gx,gB},'ndp_loop_dx', ...
                adigatorOptions('overwrite',1,'echo',0));
            gx = adigatorCreateDerivInput([n 1],'x');
            gBf = adigatorCreateAuxInput([m n*K]);
            adigator('ndp_loop_fold',{gx,gBf},'ndp_loop_fold_dx', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            rng(2);
            B = randn(m,n,K);
            x.f = randn(n,1); x.dx = ones(n,1);
            yv = ndp_loop_dx(x, B);
            yf = ndp_loop_fold_dx(x, reshape(B,m,[]));

            tc.verifyEqual(yv.dx_location, yf.dx_location);
            tc.verifyEqual(yv.f,  yf.f,  'AbsTol', 1e-14);
            tc.verifyEqual(yv.dx, yf.dx, 'AbsTol', 1e-14);

            % and against analytic / central differences
            J = full(sparse(yv.dx_location(:,1), yv.dx_location(:,2), ...
                yv.dx, yv.dx_size(1), yv.dx_size(2)));
            Ja = zeros(m*K,n);
            for k = 1:K
                Ja((k-1)*m+(1:m),:) = B(:,:,k)*diag(1 + x.f.^2/2);
            end
            tc.verifyEqual(J, Ja, 'AbsTol', 1e-12, 'RelTol', 1e-12);
            ee = 1e-6;
            Jfd = zeros(m*K,n);
            for i = 1:n
                e = zeros(n,1); e(i) = ee;
                Jfd(:,i) = (ndp_loop(x.f+e,B) - ndp_loop(x.f-e,B))/(2*ee);
            end
            tc.verifyEqual(J, Jfd, 'AbsTol', 1e-5, 'RelTol', 1e-5);
        end

        function multiCounterSlice(tc)
            % C(:,:,a,k) with two loop counters: the window is affine in
            % both ("multi-counter from day one", roadmap R2)
            writeFcn('ndp_two', { ...
                'function y = ndp_two(x,C)', ...
                'A = 2; K = 3;', ...
                'y = zeros(2,1);', ...
                'for k = 1:K', ...
                '  for a = 1:A', ...
                '    y = y + (a + 2*k)*(C(:,:,a,k)*(x.^2));', ...
                '  end', ...
                'end', ...
                'end'});
            m = 2; n = 2; A = 2; K = 3;
            gx = adigatorCreateDerivInput([n 1],'x');
            gC = adigatorCreateAuxInput([m n A K]);
            adigator('ndp_two',{gx,gC},'ndp_two_dx', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            rng(3);
            C = randn(m,n,A,K);
            x.f = randn(n,1); x.dx = ones(n,1);
            y = ndp_two_dx(x, C);
            J = full(sparse(y.dx_location(:,1), y.dx_location(:,2), ...
                y.dx, y.dx_size(1), y.dx_size(2)));

            yfa = zeros(m,1);
            Ja = zeros(m,n);
            for k = 1:K
                for a = 1:A
                    yfa = yfa + (a + 2*k)*(C(:,:,a,k)*(x.f.^2));
                    Ja  = Ja  + (a + 2*k)*C(:,:,a,k)*diag(2*x.f);
                end
            end
            tc.verifyEqual(y.f, yfa, 'AbsTol', 1e-12, 'RelTol', 1e-12);
            tc.verifyEqual(J,   Ja,  'AbsTol', 1e-12, 'RelTol', 1e-12);
        end

        function partialTrailingIndexing(tc)
            % MATLAB partial indexing: the last subscript spans the fold
            % of the remaining declared dimensions, D(:,:,i) on m x n x A x K
            writeFcn('ndp_partial', { ...
                'function y = ndp_partial(x,D)', ...
                'y = D(:,:,3)*x;', ...
                'end'});
            m = 2; n = 2; A = 2; K = 2;
            gx = adigatorCreateDerivInput([n 1],'x');
            gD = adigatorCreateAuxInput([m n A K]);
            adigator('ndp_partial',{gx,gD},'ndp_partial_dx', ...
                adigatorOptions('overwrite',1,'echo',0));
            rehash;

            rng(4);
            D = randn(m,n,A,K);
            x.f = randn(n,1); x.dx = ones(n,1);
            y = ndp_partial_dx(x, D);
            % page 3 in column-major page order is (a,k) = (1,2)
            tc.verifyEqual(y.f, D(:,:,1,2)*x.f, 'AbsTol', 1e-12, 'RelTol', 1e-12);
            J = full(sparse(y.dx_location(:,1), y.dx_location(:,2), ...
                y.dx, y.dx_size(1), y.dx_size(2)));
            tc.verifyEqual(J, D(:,:,1,2), 'AbsTol', 1e-12, 'RelTol', 1e-12);
        end

        function inputDeclarationGuards(tc)
            % N-D declarations cannot be vectorized, cannot take the fixed
            % value argument, must be integer; deriv inputs stay 2D-only
            tc.verifyError(@() adigatorCreateAuxInput([2 3 Inf]), ...
                'adigator:ndparam:vectorized');
            tc.verifyError(@() adigatorCreateAuxInput([2 3 4], ones(24,1)), ...
                'adigator:ndparam:fixedValue');
            tc.verifyError(@() adigatorCreateAuxInput([2 3.5 4]), ?MException);
            tc.verifyError(@() adigatorCreateDerivInput([2 3 4],'x'), ?MException);
            % 2D declarations keep working, incl. the vectorized value form
            tc.verifyClass(adigatorCreateAuxInput([3 2]), 'adigatorInput');
            tc.verifyClass(adigatorCreateAuxInput([Inf 2], [1 2]), 'adigatorInput');
        end

        function traceTimeGuards(tc)
            % unsupported reference forms, assignment, and ambiguous size
            % queries are rejected with clear errors at generation time
            opts = adigatorOptions('overwrite',1,'echo',0);
            gx = @() adigatorCreateDerivInput([2 1],'x');

            writeFcn('ndp_badvec', { ...
                'function y = ndp_badvec(x,B)', ...
                'y = B(:,:,[1 2]); y = x;', ...
                'end'});
            tc.verifyError(@() adigator('ndp_badvec', ...
                {gx(), adigatorCreateAuxInput([2 2 3])}, 'ndp_badvec_dx', opts), ...
                'adigator:ndparam:slice');

            writeFcn('ndp_badcolon', { ...
                'function y = ndp_badcolon(x,B)', ...
                'y = B(:,1,:); y = x;', ...
                'end'});
            tc.verifyError(@() adigator('ndp_badcolon', ...
                {gx(), adigatorCreateAuxInput([2 2 3])}, 'ndp_badcolon_dx', opts), ...
                'adigator:ndparam:slice');

            % out-of-range trailing subscript: adigator's initial native
            % evaluation already rejects it (the declared shape and native
            % N-D semantics agree); the veneer's own range guard is the
            % backstop for paths the native evaluation does not exercise
            writeFcn('ndp_oob', { ...
                'function y = ndp_oob(x,B)', ...
                'y = B(1,1,4); y = x;', ...
                'end'});
            tc.verifyError(@() adigator('ndp_oob', ...
                {gx(), adigatorCreateAuxInput([2 2 3])}, 'ndp_oob_dx', opts), ...
                ?MException);

            writeFcn('ndp_badasgn', { ...
                'function y = ndp_badasgn(x,B)', ...
                'B(1,1,2) = x(1);', ...
                'y = B(:,:,1)*x;', ...
                'end'});
            tc.verifyError(@() adigator('ndp_badasgn', ...
                {gx(), adigatorCreateAuxInput([2 2 3])}, 'ndp_badasgn_dx', opts), ...
                'adigator:ndparam:subsasgn');

            writeFcn('ndp_badsize', { ...
                'function y = ndp_badsize(x,B)', ...
                'kk = size(B,3);', ...
                'y = x*kk;', ...
                'end'});
            tc.verifyError(@() adigator('ndp_badsize', ...
                {gx(), adigatorCreateAuxInput([2 2 3])}, 'ndp_badsize_dx', opts), ...
                'adigator:ndparam:size');

            % B25: a LOGICAL base subscript (position 2) was silently coerced to
            % numeric and folded to a wrong element -- the native evaluation does
            % NOT catch it (unlike the numeric out-of-range base ndp_oob above),
            % so the veneer guard is the real backstop. Positions >=3 already
            % reject non-numeric subscripts; the base now does too.
            writeFcn('ndp_logbase', { ...
                'function y = ndp_logbase(x,B)', ...
                'y = B(1,true,2); y = x;', ...
                'end'});
            tc.verifyError(@() adigator('ndp_logbase', ...
                {gx(), adigatorCreateAuxInput([2 2 3])}, 'ndp_logbase_dx', opts), ...
                'adigator:ndparam:slice', ...
                'logical base subscript must be rejected (B25)');

            % B26: length() of an N-D declared parameter returned the 2D-fold
            % length (max of the fold dims), not the declared max -- a silent
            % wrong count. Guarded like size().
            writeFcn('ndp_length', { ...
                'function y = ndp_length(x,B)', ...
                'kk = length(B);', ...
                'y = x*kk;', ...
                'end'});
            tc.verifyError(@() adigator('ndp_length', ...
                {gx(), adigatorCreateAuxInput([2 2 3])}, 'ndp_length_dx', opts), ...
                'adigator:ndparam:length', ...
                'length() of an N-D declared parameter must be rejected (B26)');

            % B26 side effect: a bare linear `end` (B(end)) resolves through the
            % `end` overload -> length(), so it is guarded too. Pre-fix B(end)
            % linear-indexed the 2D fold (also a silent wrong element).
            writeFcn('ndp_end', { ...
                'function y = ndp_end(x,B)', ...
                'v = B(end); y = x*v;', ...
                'end'});
            tc.verifyError(@() adigator('ndp_end', ...
                {gx(), adigatorCreateAuxInput([2 2 3])}, 'ndp_end_dx', opts), ...
                'adigator:ndparam:length', ...
                'bare linear end on an N-D declared parameter is guarded via length() (B26)');
        end
    end
end

function writeFcn(name, lines)
% write a fixture function file into the (temporary) working folder
fid = fopen([name '.m'], 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end
