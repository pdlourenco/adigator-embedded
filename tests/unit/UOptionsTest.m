classdef UOptionsTest < matlab.unittest.TestCase
    % UOptionsTest  Option spelling/validation matrix.
    %
    % CI plan: TS-U-07, verifies REQ-C-08. Pins the B11 fix (embed_mode
    % accepts long names and any case via adigatorNormalizeEmbedMode) and
    % the B12 fix (documented upper-case option field names accepted by the
    % generator option parsers).

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

    methods (Test)
        function normalizeAcceptsAliases(tc)
            tc.verifyEqual(adigatorNormalizeEmbedMode('c'), 'c');
            tc.verifyEqual(adigatorNormalizeEmbedMode('classic'), 'c');
            tc.verifyEqual(adigatorNormalizeEmbedMode('Coderload'), 'l');
            tc.verifyEqual(adigatorNormalizeEmbedMode('L'), 'l');
            tc.verifyEqual(adigatorNormalizeEmbedMode("inline"), 'i');
            tc.verifyEqual(adigatorNormalizeEmbedMode('I'), 'i');
        end

        function normalizeRejectsJunk(tc)
            tc.verifyError(@() adigatorNormalizeEmbedMode('x'), 'adigator:embedMode');
            tc.verifyError(@() adigatorNormalizeEmbedMode(42), 'adigator:embedMode');
            tc.verifyError(@() adigatorNormalizeEmbedMode(''), 'adigator:embedMode');
        end

        function adigatorOptionsNormalizesEmbedMode(tc)
            o = adigatorOptions('EMBED_MODE','classic');
            tc.verifyEqual(o.embed_mode, 'c');
            o = adigatorOptions('embed_mode','Inline');
            tc.verifyEqual(o.embed_mode, 'i');
        end

        function generatorAcceptsDocumentedSpellings(tc)
            % B11+B12 end to end: upper-case fields and a long-form
            % embed_mode in a hand-built struct must work
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
            fid = fopen('optfix.m','w');
            fprintf(fid, 'function y = optfix(x)\ny = x^2;\nend\n');
            fclose(fid);
            rehash;
            ax = adigatorCreateDerivInput([1 1],'x');
            opts = struct('OVERWRITE',1,'ECHO',0,'EMBED_MODE','classic');
            adigatorGenJacFile('optfix',{ax},opts);
            rehash;
            [J,F] = optfix_Jac(0.8);
            tc.verifyEqual(J, 1.6, 'AbsTol', 1e-12);
            tc.verifyEqual(F, 0.64, 'AbsTol', 1e-12);
        end
    end
end
