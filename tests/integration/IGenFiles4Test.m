classdef IGenFiles4Test < matlab.unittest.TestCase
    % IGenFiles4Test  The inherited adigatorGenFiles4{Fmincon,Ipopt} convenience
    % wrappers. Pins M1 (#121): the single-constraint SPARSE Hessian branch
    % emitted `sparse(...,%1.0d,%1.0d)` with NO fprintf arguments, so MATLAB
    % truncated the emission at the first conversion and wrote a syntactically
    % broken `_Hes` file (missing dimensions and closing paren) - the generator
    % reported success. n >= 16 (n^2 >= 250) with a sparse constraint Hessian
    % hits that branch. The pin: the generated Hessian file must parse.

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
        function fminconSingleInequalityHessianParses(tc)
            % M1 site 1: single inequality constraint, sparse Hessian branch.
            n = 16;
            writeRaw('m1f_obj', {'function y = m1f_obj(x)', 'y = sum(x.^2);', 'end'});
            writeRaw('m1f_con', {'function [c,ceq] = m1f_con(x)', ...
                'c = x(1)*x(2) + x(3)*x(4) - 1;', 'ceq = [];', 'end'});
            setup = struct('order',2,'numvar',n,'objective','m1f_obj','constraint','m1f_con');
            adigatorGenFiles4Fmincon(setup);
            rehash;
            tc.verifyGeneratedHessianParses('m1f_obj_Hes.m', 'con.dxdx');
        end

        function fminconSingleEqualityHessianParses(tc)
            % M1 site 2: single equality constraint, sparse Hessian branch.
            n = 16;
            writeRaw('m1e_obj', {'function y = m1e_obj(x)', 'y = sum(x.^2);', 'end'});
            writeRaw('m1e_con', {'function [c,ceq] = m1e_con(x)', ...
                'c = [];', 'ceq = x(1)*x(2) + x(3)*x(4) - 1;', 'end'});
            setup = struct('order',2,'numvar',n,'objective','m1e_obj','constraint','m1e_con');
            adigatorGenFiles4Fmincon(setup);
            rehash;
            tc.verifyGeneratedHessianParses('m1e_obj_Hes.m', 'coneq.dxdx');
        end

        function ipoptSingleConstraintHessianParses(tc)
            % M1 site 3: single constraint, sparse Hessian branch (Ipopt).
            n = 16;
            writeRaw('m1i_obj', {'function y = m1i_obj(x)', 'y = sum(x.^2);', 'end'});
            writeRaw('m1i_con', {'function c = m1i_con(x)', ...
                'c = x(1)*x(2) + x(3)*x(4);', 'end'});
            setup = struct('order',2,'numvar',n,'objective','m1i_obj','constraint','m1i_con');
            adigatorGenFiles4Ipopt(setup);
            rehash;
            tc.verifyGeneratedHessianParses('m1i_obj_Hes.m', 'con.dxdx');
        end
    end

    methods
        function verifyGeneratedHessianParses(tc, hesFile, sparseVar)
            tc.assertEqual(exist(hesFile,'file'), 2, ...
                sprintf('%s was not generated', hesFile));
            % A truncated `<var>Hes = sparse(...,<var>,` line (M1) makes the
            % file syntactically broken -> checkcode reports a syntax error
            % (e.g. "... might be missing a closing ')' ... invalid syntax").
            msgs = checkcode(hesFile);
            synErr = arrayfun(@(m) contains(m.message, ...
                {'parse','invalid syntax','missing a closing'},'IgnoreCase',true), msgs);
            tc.verifyFalse(any(synErr), ...
                sprintf('%s has a syntax error (M1 truncation): %s', hesFile, ...
                strjoin({msgs(synErr).message}, '; ')));
            % Positive check: the sparse line carries its two integer dims + closer.
            txt = fileread(hesFile);
            tc.verifyNotEmpty(regexp(txt, ...
                ['sparse\([^;\n]*',regexptranslate('escape',sparseVar),',\d+,\d+\);'], 'once'), ...
                sprintf('%s: the sparse Hessian line is missing its dimensions', hesFile));
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
