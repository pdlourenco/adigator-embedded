classdef ISymbolicIndexTest < matlab.unittest.TestCase
    % ISymbolicIndexTest  Data-dependent (symbolic) index handling (B20).
    %
    % Indexing a variable by a value computed at runtime (`A(k,:)` where k is
    % not a compile-time constant) cannot be differentiated by static forward AD
    % -- the derivative sparsity pattern would be runtime-dependent. This is a
    % hard error, never a wrong derivative (REVIEW_CONTEXT principle 1). B20's
    % fix makes that error **actionable**: it names the construct and points to
    % the logical-weight-sum rewrite (ADR-0024). This test pins both the
    % actionable error and that the documented workaround actually generates.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
            tc.applyFixture(PathFixture(fullfile(root,'embedding')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function dynamicIndexRaisesActionableError(tc)
            % A data-dependent subscript errors with the actionable id/message.
            writeRaw('symidx_dyn', { ...
                'function y = symidx_dyn(x)', ...
                'ref_data = [0 1 2; 10 1 3; 20 1 4; 30 1 5];', ...
                'ref_idx = min(4, max(1, floor(x(1))+1));', ...
                'y = ref_data(ref_idx,3) .* x(2);', ...
                'end'});
            gx = adigatorCreateDerivInput([2 1],'x');
            try
                adigatorGenJacFile('symidx_dyn',{gx},struct('echo',0));
                tc.verifyFail('dynamic index must raise the symbolic-index error');
            catch err
                tc.verifyEqual(err.identifier, 'adigator:symbolicIndex', ...
                    'must use the actionable symbolic-index error id');
                % the message must be actionable (point to the workaround)
                tc.verifySubstring(err.message, 'logical weights', ...
                    'error must point to the logical-weight-sum workaround');
            end
        end

        function logicalWeightRewriteGenerates(tc)
            % The documented workaround (sum with logical weights) removes the
            % dynamic subscript, so it generates and differentiates correctly.
            % At x=[1.5;3]: ref_idx=2, y=ref_data(2,3)*x(2)=3*3=9, J=[0 3].
            writeRaw('symidx_weighted', { ...
                'function y = symidx_weighted(x)', ...
                'ref_data = [0 1 2; 10 1 3; 20 1 4; 30 1 5];', ...
                'ref_idx = min(4, max(1, floor(x(1))+1));', ...
                'y = 0;', ...
                'for k = 1:size(ref_data,1)', ...
                '    y = y + (ref_idx == k) .* ref_data(k,3) .* x(2);', ...
                'end', ...
                'end'});
            gx = adigatorCreateDerivInput([2 1],'x');
            adigatorGenJacFile('symidx_weighted',{gx},struct('echo',0));
            rehash;
            xv = [1.5; 3];
            [J,F] = symidx_weighted_Jac(xv);
            tc.verifyEqual(F, symidx_weighted(xv), 'AbsTol', 1e-12, 'value');
            tc.verifyEqual(F, 9, 'AbsTol', 1e-12, 'selected value ref_data(2,3)*x(2)');
            tc.verifyEqual(J, [0 3], 'AbsTol', 1e-12, ...
                'Jacobian: 0 wrt x(1) (piecewise-constant selector), 3 wrt x(2)');
        end

        function whileCounterIndexRaisesError(tc)
            % B19: a `while`-loop counter used as a matrix subscript is a
            % symbolic index -- ADiGator deliberately does not unroll `while`
            % loops. It folds into the B20 symbolic-index limitation, and the
            % error now also points to the `for`-loop fix.
            writeRaw('symidx_while', { ...
                'function y = symidx_while(x)', ...
                'N = 4; A = (1:N).'';', ...
                'n = 1; s = 0; p = x(1);', ...
                'while n <= N', ...
                '    s = s + p .* A(n);', ...
                '    n = n + 1; p = p .* x(1);', ...
                'end', ...
                'y = s;', ...
                'end'});
            gx = adigatorCreateDerivInput([1 1],'x');
            try
                adigatorGenJacFile('symidx_while',{gx},struct('echo',0));
                tc.verifyFail('while-counter index must raise the symbolic-index error');
            catch err
                tc.verifyEqual(err.identifier, 'adigator:symbolicIndex');
                tc.verifySubstring(err.message, 'unroll', ...
                    'error must point to the for-loop (unroll) fix for a loop-counter index');
            end
        end

        function forLoopCounterIndexGenerates(tc)
            % The `for`-loop equivalent unrolls (counter is a compile-time
            % constant), so it generates and differentiates correctly.
            % y = sum_{n=1..4} p_n * A(n), p_n = x^n, A = [1;2;3;4].
            % At x=1: y = 1+2+3+4 = 10; dy/dx = sum n*A(n)*x^(n-1) = 1+4+9+16=30.
            writeRaw('symidx_for', { ...
                'function y = symidx_for(x)', ...
                'N = 4; A = (1:N).'';', ...
                's = 0; p = x(1);', ...
                'for n = 1:N', ...
                '    s = s + p .* A(n);', ...
                '    p = p .* x(1);', ...
                'end', ...
                'y = s;', ...
                'end'});
            gx = adigatorCreateDerivInput([1 1],'x');
            adigatorGenJacFile('symidx_for',{gx},struct('echo',0));
            rehash;
            [J,F] = symidx_for_Jac(1);
            tc.verifyEqual(F, 10, 'AbsTol', 1e-12, 'value at x=1');
            tc.verifyEqual(J, 30, 'AbsTol', 1e-12, 'derivative sum n*A(n) at x=1');
        end
    end
end

% ---- helpers ----

function writeRaw(name, lines)
fid = fopen([name,'.m'],'w');
assert(fid > 0, 'could not create fixture %s', name);
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end
