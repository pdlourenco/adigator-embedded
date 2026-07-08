classdef IGenFiles4Test < matlab.unittest.TestCase
    % IGenFiles4Test  The inherited adigatorGenFiles4{Fmincon,Ipopt} convenience
    % wrappers. Pins M1 (#121): the single-constraint SPARSE Hessian branch
    % emitted `sparse(...,%1.0d,%1.0d)` with NO fprintf arguments, so MATLAB
    % truncated the emission at the first conversion and wrote a syntactically
    % broken `_Hes` file (missing dimensions and closing paren) - the generator
    % reported success. n >= 16 (n^2 >= 250) with a sparse constraint Hessian
    % hits that branch. The pin: the generated Hessian file must parse.
    %
    % Also pins two emission-hygiene fixes from the same #121 batch:
    %   M2 (Fminunc) - `if order` was always true (order is 1 or 2), so an
    %      order-1 request wrongly named the gradient wrapper `_Hes` and listed a
    %      never-regenerated `_ADiGatorHes` for overwrite-deletion.
    %   M3 (Fmincon) - the auxdata branch assigned the constraint-gradient handle
    %      to the misspelled field `funcs.congrd` (every caller uses `consgrd`).

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

        function fminuncOrder1NamesGradientWrapper(tc)
            % M2: an order-1 (gradient-only) Fminunc request must emit a `_Grd`
            % wrapper, emit no `_Hes`, and leave a pre-existing `_ADiGatorHes`
            % untouched. Pre-fix `if order` was always true, so order-1 named the
            % gradient wrapper `_Hes` and scheduled `_ADiGatorHes` for deletion.
            n = 4;
            writeRaw('m2_obj', {'function y = m2_obj(x)', 'y = sum(x.^2);', 'end'});
            % a stray second-deriv file from an earlier order-2 run must survive a
            % subsequent order-1 regeneration (order-1 never regenerates it)
            writeRaw('m2_obj_ADiGatorHes', ...
                {'function y = m2_obj_ADiGatorHes(x)', 'y = x;', 'end'});
            setup = struct('order',1,'numvar',n,'objective','m2_obj');
            funcs = adigatorGenFiles4Fminunc(setup);
            rehash;
            tc.verifyEqual(exist('m2_obj_Grd.m','file'), 2, ...
                'order-1 must generate the _Grd gradient wrapper (M2)');
            tc.verifyNotEqual(exist('m2_obj_Hes.m','file'), 2, ...
                'order-1 must NOT generate a _Hes wrapper (M2)');
            tc.verifyEqual(exist('m2_obj_ADiGatorHes.m','file'), 2, ...
                'order-1 must not delete a pre-existing _ADiGatorHes (M2)');
            tc.verifyTrue(isfield(funcs,'gradient'), ...
                'order-1 must return funcs.gradient (M2)');
            % the wrapper carries the gradient signature [f, g], not [f, g, h]
            hdr = fileread('m2_obj_Grd.m');
            tc.verifyNotEmpty(regexp(hdr,'function \[f, g\] = m2_obj_Grd','once'), ...
                'the _Grd wrapper must have the [f, g] gradient signature (M2)');
        end

        function fminconAuxdataConstraintExposesConsgrd(tc)
            % M3: an auxdata problem with a constraint must expose the
            % constraint-gradient handle under `funcs.consgrd` (the field every
            % caller reads), not the misspelled `funcs.congrd` the auxdata branch
            % used - which silently dropped the handle.
            n = 3;
            writeRaw('m3_obj', {'function y = m3_obj(x,a)', 'y = a*sum(x.^2);', 'end'});
            writeRaw('m3_con', {'function [c,ceq] = m3_con(x,a)', ...
                'c = a*x(1) - 1;', 'ceq = [];', 'end'});
            setup = struct('order',1,'numvar',n,'objective','m3_obj', ...
                'constraint','m3_con','auxdata',2);
            funcs = adigatorGenFiles4Fmincon(setup);
            rehash;
            tc.verifyTrue(isfield(funcs,'consgrd'), ...
                'auxdata+constraint must expose funcs.consgrd (M3)');
            tc.verifyFalse(isfield(funcs,'congrd'), ...
                'the misspelled funcs.congrd must be gone (M3)');
        end

        function echoOptionGatesSuccessBanner(tc)
            % M6 (#121): the success banner must honor the echo option (it was
            % printed unconditionally). echo=0 -> silent; echo unset (the
            % default, no options field) -> the banner still prints.
            n = 4;
            writeRaw('m6q_obj', {'function y = m6q_obj(x)', 'y = sum(x.^2);', 'end'});
            setupQuiet = struct('order',1,'numvar',n,'objective','m6q_obj', ...
                'options',adigatorOptions('echo',0)); %#ok<NASGU> read by evalc
            outQuiet = evalc('adigatorGenFiles4Fminunc(setupQuiet);');
            rehash;
            tc.verifyEmpty(regexp(outQuiet,'successfully generated','once'), ...
                'echo=0 must suppress the success banner (M6)');

            writeRaw('m6l_obj', {'function y = m6l_obj(x)', 'y = sum(x.^2);', 'end'});
            setupLoud = struct('order',1,'numvar',n,'objective','m6l_obj'); %#ok<NASGU> read by evalc
            outLoud = evalc('adigatorGenFiles4Fminunc(setupLoud);');
            rehash;
            tc.verifyNotEmpty(regexp(outLoud,'successfully generated','once'), ...
                'the default (echo unset) must still print the banner (M6)');
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
