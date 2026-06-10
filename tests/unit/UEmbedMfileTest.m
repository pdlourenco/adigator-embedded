classdef UEmbedMfileTest < matlab.unittest.TestCase
    % UEmbedMfileTest  Unit tests for embedding/structure_to_embed_mfile.m
    %
    % CI plan: TS-U-05, verifies REQ-C-06 (round trip: emitted data function
    % returns a struct equal in values, classes, and sizes to the input).
    % Pins ANALYSIS.md bug B2 (format-string defect in the generated header)
    % and the integer/logical class-preservation fix.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            repoRoot = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(repoRoot,'embedding')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function roundTripPreservesValuesAndClasses(tc)
            S = struct();
            S.Gator1Data.Index1 = uint32([1 2 3; 4 5 6]);
            S.Gator1Data.Index2 = int32([-1; 0; 7]);
            S.Gator1Data.Index3 = uint32(42);            % integer scalar
            S.Gator1Data.Data1  = [2 0; 0 2];            % double matrix
            S.Gator1Data.Data2  = pi;                    % double scalar
            S.Gator1Data.Data3  = [0.1 0.2 0.30000000000000004]; % round-trip precision
            S.Gator1Data.Data4  = zeros(0,1);            % empty double
            S.Gator1Data.Data5  = zeros(0,1,'uint32');   % empty integer
            S.Gator1Data.Data6  = logical([1 0 1]);      % logical array
            S.Gator1Data.Data7  = reshape(1:8, 2, 2, 2); % n-d array
            S.Gator1Data.Data8  = 1.5 + 2.5i;            % complex scalar
            S.meta.name = 'my''fun';                     % char with quote
            S.meta.list = {1, [1 2; 3 4], 'abc'};        % cell

            fpath = structure_to_embed_mfile('data_roundtrip_ut', S, pwd);
            tc.assertTrue(isfile(fpath));
            rehash;
            S2 = data_roundtrip_ut();
            tc.verifyEqual(S2, S); % verifyEqual is class-strict for numerics
        end

        function headerIsValidCode(tc)
            % B2: the header fprintf used an unescaped '%' and a missing
            % newline, which could leave 'S = struct();' inside a comment.
            S.Gator1Data.Index1 = uint32(1);
            fpath = structure_to_embed_mfile('data_header_ut', S, pwd);
            txt = readlines(fpath);
            tc.verifyTrue(startsWith(txt(1), "function S = data_header_ut"));
            tc.verifyEqual(strtrim(txt(2)), "%#codegen");
            % every line between header and 'S = struct();' must be a comment
            k = find(strtrim(txt) == "S = struct();", 1);
            tc.assertNotEmpty(k, "'S = struct();' must appear on its own line");
            for line = 3:(k-1)
                tc.verifyTrue(startsWith(strtrim(txt(line)), "%"), ...
                    "line " + line + " between header and body must be a comment");
            end
            % and the helper-file comment must have survived the format string
            tc.verifyTrue(any(contains(txt(1:k), "Helper file for ADiGator")));
        end

        function generatedFileHasNoErrors(tc)
            S.Gator1Data.Index1 = uint32([1 2 3]);
            S.Gator1Data.Data1 = eye(3);
            fpath = structure_to_embed_mfile('data_lint_ut', S, pwd);
            msgs = checkcode(char(fpath));
            if ~isempty(msgs)
                texts = string({msgs.message});
                tc.verifyFalse(any(contains(texts, "Parse error", 'IgnoreCase', true)), ...
                    "generated data function does not parse: " + strjoin(texts, "; "));
            end
        end
    end
end
