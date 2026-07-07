classdef UPatchTest < matlab.unittest.TestCase
    % UPatchTest  Unit tests for embedding/adigator_patch_derivative.m
    %
    % CI plan: TS-U-06, verifies REQ-C-07. Pins the B3 fix (multi-match
    % loader-guard deletion) and the B4 fix (function-header matching by
    % definition line, robust to names containing other names).
    %
    % Uses a synthetic file mimicking the structure adigator emits in
    % classic mode (global + loader guard + Gator data reads + LoadData
    % subfunction), with deliberately adversarial details: two loader
    % guards (B3) and a subfunction whose name contains the main function
    % name as a substring (B4).

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
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
        function coderloadPatching(tc)
            fpath = writeSyntheticDerivFile();
            txt = adigator_patch_derivative(fpath, 'myfun_ADiGatorJac', ...
                {'myfun_ADiGatorJac','subfun1'}, 0);

            % loader machinery fully removed (B3: BOTH guards, nothing else)
            tc.verifyFalse(any(contains(txt, 'ADiGator_LoadData')), ...
                'runtime loader still referenced');
            tc.verifyTrue(any(contains(txt, 'sentinel_line_1 = 1;')) && ...
                          any(contains(txt, 'sentinel_line_2 = 2;')), ...
                'B3: a line adjacent to a loader guard was deleted');

            % globals replaced by persistents in both patched functions
            tc.verifyFalse(any(startsWith(strtrim(txt), 'global ')), ...
                'global declaration left behind');
            tc.verifyEqual(nnz(startsWith(strtrim(txt), 'persistent ADiGator_')), 2);
            tc.verifyEqual(nnz(contains(txt, 'coder.load(')), 2);

            % one %#codegen directly after each patched function header (B4:
            % the lookalike subfunction must NOT receive one)
            cg = find(strtrim(txt) == "%#codegen");
            tc.verifyNumElements(cg, 2, 'expected exactly two %%#codegen lines');
            for k = cg(:).'
                tc.verifyTrue(startsWith(strtrim(txt(k-1)), 'function'), ...
                    '%%#codegen not directly after a function header');
            end
            lookalike = find(contains(txt, 'function out = sub_myfun_ADiGatorJac'));
            tc.assertNumElements(lookalike, 1);
            tc.verifyNotEqual(strtrim(txt(lookalike+1)), "%#codegen", ...
                'B4: lookalike subfunction wrongly received %%#codegen');

            % Gator data reads wrapped in coder.const
            gd = txt(contains(txt, 'Gator1Data = '));
            tc.verifyTrue(all(contains(gd, 'coder.const(')), ...
                'Gator data read not wrapped in coder.const');
        end

        function inlinePatching(tc)
            fpath = writeSyntheticDerivFile();
            txt = adigator_patch_derivative(fpath, 'myfun_ADiGatorJac', ...
                {'myfun_ADiGatorJac','subfun1'}, 0, {'data_main','data_sub'});

            tc.verifyFalse(any(contains(txt, 'ADiGator_LoadData')));
            tc.verifyFalse(any(startsWith(strtrim(txt), 'global ')));
            tc.verifyFalse(any(contains(txt, 'coder.load(')), ...
                'inline mode must not load from file');
            tc.verifyTrue(any(contains(txt, 'coder.const(data_main())')));
            tc.verifyTrue(any(contains(txt, 'coder.const(data_sub())')));
            % per-function field level removed from data references
            gd = txt(contains(txt, 'Gator1Data = '));
            tc.verifyFalse(any(contains(gd, '.myfun_ADiGatorJac.')) || ...
                           any(contains(gd, '.subfun1.')), ...
                'function-name struct level not removed in inline mode');
        end

        function missingGlobalDeclarationErrors(tc)
            % M9: a derivative file whose subfunction has a header but no
            % `global ADiGator_<name>` line must fail loudly. find_in_file scans
            % from the header to EOF, so a missing global yields an empty gidx ->
            % the `txt(gidx)=[]` / `txt(1:gidx)` splice below would corrupt the
            % file with a cryptic indexing error (or bind a later subfunction's
            % identically-named global). The generator emits the global
            % unconditionally, so a miss means a corrupted/hand-edited source.
            lines = [ ...
                "function y = gone_ADiGatorJac(x)"
                "Gator1Data = ADiGator_gone_ADiGatorJac.gone_ADiGatorJac.Gator1Data;"
                "y.f = x + Gator1Data.Index1(1);"
                "end"];
            fpath = fullfile(pwd, 'gone_ADiGatorJac.m');
            writelines(lines, fpath);
            tc.verifyError(@() adigator_patch_derivative(fpath, ...
                'gone_ADiGatorJac', {'gone_ADiGatorJac'}, 0, {}), ...
                'adigator_patch_derivative:globalNotFound');
        end

        function matPathOverride(tc)
            fpath = writeSyntheticDerivFile();
            txt = adigator_patch_derivative(fpath, 'myfun_ADiGatorJac', ...
                {'myfun_ADiGatorJac'}, 0, {}, 'sub/dir/custom.mat');
            tc.verifyTrue(any(contains(txt, "coder.load('sub/dir/custom.mat'")), ...
                'mat_filepath override not honored');
        end
    end
end

% ======================== helpers ======================== %

function fpath = writeSyntheticDerivFile()
lines = [ ...
    "function y = myfun_ADiGatorJac(x)"
    "global ADiGator_myfun_ADiGatorJac"
    "if isempty(ADiGator_myfun_ADiGatorJac); ADiGator_LoadData(); end"
    "sentinel_line_1 = 1;"
    "Gator1Data = ADiGator_myfun_ADiGatorJac.myfun_ADiGatorJac.Gator1Data;"
    "y.f = subfun1(x) + sentinel_line_1;"
    "end"
    ""
    "function out = subfun1(x)"
    "global ADiGator_myfun_ADiGatorJac"
    "if isempty(ADiGator_myfun_ADiGatorJac); ADiGator_LoadData(); end"
    "sentinel_line_2 = 2;"
    "Gator1Data = ADiGator_myfun_ADiGatorJac.subfun1.Gator1Data;"
    "out = x + Gator1Data.Index1(1) + sentinel_line_2;"
    "end"
    ""
    "function out = sub_myfun_ADiGatorJac(x)"
    "out = x;"
    "end"
    ""
    "function ADiGator_LoadData()"
    "global ADiGator_myfun_ADiGatorJac"
    "ADiGator_myfun_ADiGatorJac = load('myfun_ADiGatorJac.mat');"
    "return"
    "end"];
fpath = fullfile(pwd, 'myfun_ADiGatorJac.m');
writelines(lines, fpath);
end
