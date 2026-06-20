classdef ILevelSelectTest < matlab.unittest.TestCase
    % ILevelSelectTest  Roadmap R7a (issue #21): the DER_LEVELS option selects
    % which derivative levels a generated wrapper returns - 0 = function value,
    % 1 = first derivative (gradient/Jacobian), 2 = Hessian. The top level the
    % generator is named for is always returned; DER_LEVELS trims the
    % lower-order outputs (and their assembly) from the wrapper.
    %
    % Checks:
    %  - the wrapper signature is trimmed to the requested levels (nargout)
    %  - each emitted output is numerically identical to the full-generation
    %    counterpart (DER_LEVELS only removes outputs, never changes values)
    %  - the gradient intermediate of a Grd->Hes chain stays [Grd,Fun]
    %  - the option validation guards (type/range/top-level-missing)
    %  - DER_LEVELS composes with the embedded pipeline (mode 'l')

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
        function resolverDefaultsAndGuards(tc)
            % the shared resolver: [] -> all levels; top level mandatory;
            % range and type checks
            tc.verifyEqual(adigatorResolveDerLevels([],1,'t'), 0:1);
            tc.verifyEqual(adigatorResolveDerLevels([],2,'t'), 0:2);
            tc.verifyEqual(adigatorResolveDerLevels([2 1 2],2,'t'), [1 2]);
            tc.verifyError(@() adigatorResolveDerLevels([0 1],2,'t'), ...
                'adigator:derLevels:topmissing');
            tc.verifyError(@() adigatorResolveDerLevels(0,1,'t'), ...
                'adigator:derLevels:topmissing');
            tc.verifyError(@() adigatorResolveDerLevels(2,1,'t'), ...
                'adigator:derLevels:range');
            tc.verifyError(@() adigatorResolveDerLevels(1.5,2,'t'), ...
                'adigator:derLevels:type');
            % adigatorOptions validates the field at parse time
            tc.verifyError(@() adigatorOptions('der_levels',3), ...
                'adigator:derLevels');
            tc.verifyError(@() adigatorOptions('der_levels',1.5), ...
                'adigator:derLevels');
            tc.verifyEqual(adigatorOptions('der_levels',[2 1]).der_levels, [1 2]);
        end

        function jacobianFunGating(tc)
            % Jacobian: level 1 (Jac) always returned; level 0 (Fun) optional
            body = 'y = [x(1)^2; x(2)*x(3)];';
            writeFcn('ls_jf', body);   % default
            writeFcn('ls_j1', body);   % der_levels = [1]
            gx = @() adigatorCreateDerivInput([3 1],'x');
            adigatorGenJacFile('ls_jf',{gx()}, struct('overwrite',1,'echo',0));
            adigatorGenJacFile('ls_j1',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_levels',1));
            rehash;

            tc.verifyEqual(nargout('ls_jf_Jac'), 2); % [Jac,Fun]
            tc.verifyEqual(nargout('ls_j1_Jac'), 1); % [Jac]

            xv = randn(3,1);
            [Jf,Ff] = ls_jf_Jac(xv);
            J1 = ls_j1_Jac(xv);
            tc.verifyEqual(full(J1), full(Jf), 'AbsTol', 0);
            tc.verifyEqual(Ff, [xv(1)^2; xv(2)*xv(3)], 'AbsTol', 1e-12);

            % the trimmed wrapper assembles no function value (matches the
            % generator's literal "Fun = " fprintf in adigatorGenJacFile)
            wtxt = fileread('ls_j1_Jac.m');
            tc.verifyFalse(contains(wtxt,'Fun ='), ...
                'der_levels=[1] wrapper must not assemble Fun');
        end

        function hessianLevelSubsets(tc)
            % Hessian: level 2 (Hes) always; gradient/function optional. Each
            % subset's outputs must equal the full-generation references.
            body = 'y = x(1)^2*x(2) + sin(x(3));';
            writeFcn('ls_hf', body);   % default [Hes,Grd,Fun]
            writeFcn('ls_h2', body);   % der_levels = [2]      -> [Hes]
            writeFcn('ls_hg', body);   % der_levels = [1 2]    -> [Hes,Grd]
            writeFcn('ls_hk', body);   % der_levels = [0 2]    -> [Hes,Fun]
            gx = @() adigatorCreateDerivInput([3 1],'x');
            adigatorGenHesFile('ls_hf',{gx()}, struct('overwrite',1,'echo',0));
            adigatorGenHesFile('ls_h2',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_levels',2));
            adigatorGenHesFile('ls_hg',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_levels',[1 2]));
            adigatorGenHesFile('ls_hk',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_levels',[0 2]));
            rehash;

            % signatures
            tc.verifyEqual(nargout('ls_hf_Hes'), 3); % [Hes,Grd,Fun]
            tc.verifyEqual(nargout('ls_h2_Hes'), 1); % [Hes]
            tc.verifyEqual(nargout('ls_hg_Hes'), 2); % [Hes,Grd]
            tc.verifyEqual(nargout('ls_hk_Hes'), 2); % [Hes,Fun]
            % the gradient intermediate is always full and re-differentiable
            tc.verifyEqual(nargout('ls_h2_Grd'), 2); % [Grd,Fun]

            xv = randn(3,1);
            [Href,Gref,Fref] = ls_hf_Hes(xv);

            H2 = ls_h2_Hes(xv);
            tc.verifyEqual(full(H2), full(Href), 'AbsTol', 0);

            [Hg,Gg] = ls_hg_Hes(xv);
            tc.verifyEqual(full(Hg), full(Href), 'AbsTol', 0);
            tc.verifyEqual(Gg, Gref, 'AbsTol', 0);

            [Hk,Fk] = ls_hk_Hes(xv);
            tc.verifyEqual(full(Hk), full(Href), 'AbsTol', 0);
            tc.verifyEqual(Fk, Fref, 'AbsTol', 0);

            % the Hessian-only wrapper assembles neither Grd nor Fun
            wtxt = fileread('ls_h2_Hes.m');
            tc.verifyFalse(contains(wtxt,'Grd ='), ...
                'der_levels=[2] Hessian wrapper must not assemble Grd');
            tc.verifyFalse(contains(wtxt,'Fun ='), ...
                'der_levels=[2] Hessian wrapper must not assemble Fun');
            % but the gradient wrapper of the same generation keeps both
            gtxt = fileread('ls_h2_Grd.m');
            tc.verifyTrue(contains(gtxt,'Grd =') && contains(gtxt,'Fun ='), ...
                'gradient intermediate must stay [Grd,Fun]');
        end

        function generatorGuards(tc)
            % the generators reject an out-of-range / top-missing der_levels
            writeFcn('ls_g', 'y = x(1)^2 + x(2);');
            gx = @() adigatorCreateDerivInput([2 1],'x');
            tc.verifyError(@() adigatorGenJacFile('ls_g',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_levels',0)), ...
                'adigator:derLevels:topmissing');
            tc.verifyError(@() adigatorGenHesFile('ls_g',{gx()}, ...
                struct('overwrite',1,'echo',0,'der_levels',[0 1])), ...
                'adigator:derLevels:topmissing');
        end

        function composesWithEmbedMode(tc)
            % DER_LEVELS is orthogonal to the embed pipeline: a Hessian-only
            % wrapper built in mode 'l' returns the same Hes as classic full
            writeFcn('ls_em', 'y = x(1)*x(2) + x(3)^2;');
            base = pwd;
            cdir = fullfile(base,'em_c');
            ldir = fullfile(base,'em_l');
            adigatorGenDerFile_embedded('hessian','ls_em', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','c','path',cdir,'echo',0));
            adigatorGenDerFile_embedded('hessian','ls_em', ...
                {adigatorCreateDerivInput([3 1],'x')}, ...
                struct('embed_mode','l','path',ldir,'echo',0,'der_levels',2));

            % text-level proof the trimming composed with the embed pipeline -
            % runs without MATLAB Coder (the numeric check below needs coder.*)
            txtl = readlines(fullfile(ldir,'ls_em_Hes.m'));
            tc.verifyTrue(any(contains(txtl,'function [Hes] = ls_em_Hes(')), ...
                'mode l: Hessian-only wrapper signature not trimmed to [Hes]');
            tc.verifyFalse(any(startsWith(strtrim(txtl),'Grd =')), ...
                'mode l: Hes-only wrapper must not assemble Grd');

            xv = [0.7; -1.3; 0.4];
            c1 = cdInto(cdir); clear('ls_em_Hes'); rehash; %#ok<NASGU>
            Hc = ls_em_Hes(xv);
            clear c1

            c2 = cdInto(ldir); clear('ls_em_Hes'); rehash; %#ok<NASGU>
            try
                Hl = ls_em_Hes(xv);
            catch e
                if strcmp(e.identifier,'MATLAB:UndefinedFunction') && ...
                        contains(e.message,'coder.')
                    tc.assumeFail("coderload evaluation requires MATLAB Coder: " + e.message);
                end
                rethrow(e);
            end
            clear c2
            tc.verifyEqual(full(Hl), full(Hc), 'AbsTol', 0, ...
                'der_levels=[2] mode l Hessian differs from classic full');
        end
    end
end

function cleanupObj = cdInto(d)
old = cd(d);
cleanupObj = onCleanup(@() cd(old));
end

function writeFcn(name, body)
% write a single-output fixture function into the (temporary) working folder
fid = fopen([name '.m'], 'w');
assert(fid > 0, 'could not create fixture %s', name);
fprintf(fid, 'function y = %s(x)\n%s\nend\n', name, body);
fclose(fid);
rehash;
end
