classdef USlimEngineTest < matlab.unittest.TestCase
    % USlimEngineTest  Unit tests for the R7b slice engine (issue #21):
    % adigatorWrapperDemand (which output-struct fields the wrapper reads) and
    % adigatorSlimDerivBody (locate body -> field-slice -> dependency-closure
    % gate -> re-emit, with conservative bail-outs). Text-in / text-out on
    % hand-written generated-file snippets; no toolbox, no file I/O.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
        end
    end

    methods (Test)
        % ---------------------- adigatorWrapperDemand ------------------- %
        function wrapperReadsEmbedFields(tc)
            w = embedWrapper();
            [res, fields] = adigatorWrapperDemand(w, 'mf_ADiGatorJac');
            tc.verifyEqual(res, 'y');
            tc.verifyEqual(sort(fields), {'dx','f'}); % no _location in embed mode
        end

        function wrapperReadsClassicLocation(tc)
            w = classicWrapper();
            [res, fields] = adigatorWrapperDemand(w, 'mf_ADiGatorJac');
            tc.verifyEqual(res, 'y');
            tc.verifyEqual(sort(fields), {'dx','dx_location','f'});
        end

        function wrapperBailsWhenCallAbsent(tc)
            w = ["function [Jac,Fun] = mf_Jac(x)"; "Jac = 0;"; "Fun = 0;"; "end"];
            [res, fields] = adigatorWrapperDemand(w, 'mf_ADiGatorJac');
            tc.verifyEmpty(res);
            tc.verifyEmpty(fields);
        end

        function wrapperBailsOnWholeStructUse(tc)
            % the result struct is passed WHOLE somewhere (bare 'y'): demand
            % seeded from y.<field> reads would be incomplete -> bail
            w = [ ...
                "function [Jac,Fun] = mf_Jac(x)"; ...
                "gator_x.f = x;"; ...
                "y = mf_ADiGatorJac(gator_x);"; ...
                "otherfun(y);"; ...
                "Jac = y.dx;"; ...
                "end"];
            [res, fields] = adigatorWrapperDemand(w, 'mf_ADiGatorJac');
            tc.verifyEmpty(res);
            tc.verifyEmpty(fields);
        end

        function wrapperFieldNameEqualsResvar(tc)
            % gradient wrapper shape: result var 'f' collides with the seed
            % field name 'f' (gator_z.f) and the '.f' result read (f.f). The
            % bare-use scan must NOT mistake the dotted field 'f' for a whole-
            % struct use - it should resolve resvar='f' and the read fields,
            % not bail. (Regression: the missing '(?<!\.)' lookbehind silently
            % no-op'd slim_embed on every gradient wrapper.)
            w = [ ...
                "function [Jac,Fun] = gapfun_Grd(w,z)"; ...
                "gator_z.f = z;"; ...
                "gator_z.dz = ones(2,1);"; ...
                "f = gapfun_ADiGatorGrd(w,gator_z);"; ...
                "Jac = reshape(f.dz,[2 1]);"; ...
                "Fun = f.f;"; ...
                "end"];
            [res, fields] = adigatorWrapperDemand(w, 'gapfun_ADiGatorGrd');
            tc.verifyEqual(res, 'f');
            tc.verifyEqual(sort(fields), {'dz','f'});
        end

        function wrapperStillBailsOnBareUseWhenNameCollides(tc)
            % even with the field-name collision fix, a GENUINE bare use of the
            % result var (passed whole to otherfun) must still bail - the
            % lookbehind only excludes dotted occurrences, not a real bare token
            w = [ ...
                "function [Jac,Fun] = gapfun_Grd(w,z)"; ...
                "gator_z.f = z;"; ...
                "f = gapfun_ADiGatorGrd(w,gator_z);"; ...
                "otherfun(f);"; ...
                "Jac = f.dz;"; ...
                "end"];
            [res, fields] = adigatorWrapperDemand(w, 'gapfun_ADiGatorGrd');
            tc.verifyEmpty(res);
            tc.verifyEmpty(fields);
        end

        % ---------------------- adigatorSlimDerivBody ------------------- %
        function dropsUnreadMetadataFields(tc)
            % embed demand {f,dx}: the .dx_location / .dx_size writers and the
            % Index1 they reference must be removed
            [out, info] = adigatorSlimDerivBody(jacFile(), {'f','dx'});
            tc.verifyTrue(info.sliced);
            tc.verifyEqual(info.dropped, 2);
            tc.verifyFalse(any(contains(out,'dx_location')));
            tc.verifyFalse(any(contains(out,'dx_size')));
            tc.verifyFalse(any(contains(out,'Index1')));
            % demanded fields and their value chains survive
            tc.verifyTrue(any(contains(out,'y.f = cada1f1;')));
            tc.verifyTrue(any(contains(out,'y.dx = cada1d1;')));
            tc.verifyTrue(any(contains(out,'cada1d1 = ')));
            % the file skeleton is preserved
            tc.verifyTrue(any(contains(out,'ADiGator Start Derivative Computations')));
            tc.verifyTrue(any(contains(out,'function ADiGator_LoadData()')));
        end

        function noSliceWhenEveryFieldDemanded(tc)
            [out, info] = adigatorSlimDerivBody(jacFile(), ...
                {'f','dx','dx_location','dx_size'});
            tc.verifyFalse(info.sliced);
            tc.verifyEqual(info.reason, 'no dead statements');
            tc.verifyEqual(out, string(jacFile())); % unchanged
        end

        function classicLocationKeptSizeDropped(tc)
            % classic demand keeps _location (runtime scatter) but _size is
            % still never read, so it drops
            [out, info] = adigatorSlimDerivBody(jacFile(), ...
                {'f','dx','dx_location'});
            tc.verifyTrue(info.sliced);
            tc.verifyEqual(info.dropped, 1);
            tc.verifyTrue(any(contains(out,'y.dx_location =')));
            tc.verifyFalse(any(contains(out,'dx_size')));
        end

        function bailsOnNoDemandedFields(tc)
            [out, info] = adigatorSlimDerivBody(jacFile(), {});
            tc.verifyFalse(info.sliced);
            tc.verifyEqual(info.reason, 'no demanded fields');
            tc.verifyEqual(out, string(jacFile()));
        end

        function bailsOnMissingMarkers(tc)
            f = ["function y = mf_ADiGatorJac(gator_x)"; ...
                 "y.f = gator_x.f;"; "end"];
            [~, info] = adigatorSlimDerivBody(f, {'f'});
            tc.verifyFalse(info.sliced);
            tc.verifyEqual(info.reason, 'body markers not found');
        end

        function bailsOnLineContinuation(tc)
            f = jacFile();
            f(8) = "y.dx = cada1d1 + ..."; % introduce a continuation in the body
            [~, info] = adigatorSlimDerivBody(f, {'f','dx'});
            tc.verifyFalse(info.sliced);
            tc.verifyEqual(info.reason, 'line continuation in body');
        end

        function bailsOnTopLevelControlFlow(tc)
            f = jacFile();
            f(8) = "if gator_x.f(1) > 0"; % top-level non-for control flow
            [~, info] = adigatorSlimDerivBody(f, {'f','dx'});
            tc.verifyFalse(info.sliced);
            tc.verifyTrue(startsWith(info.reason,'cannot slice'));
        end

        function keepsRolledLoopButDropsMetadata(tc)
            % a rolled loop assembling the demanded .dx is kept whole, but the
            % UNdemanded sibling metadata (.dx_location/.dx_size) still drops
            [out, info] = adigatorSlimDerivBody(rolledJacFile(), {'f','dx'});
            tc.verifyTrue(info.sliced);
            tc.verifyEqual(info.dropped, 2);
            tc.verifyTrue(any(contains(out,'for cadaforcount1')));  % loop kept
            tc.verifyFalse(any(contains(out,'dx_location')));
            tc.verifyFalse(any(contains(out,'dx_size')));
        end

        function dropsRolledLoopWhenUndemanded(tc)
            % demanding only .f drops the whole loop (and its zeros-init, .dx
            % and the .dx metadata) as a unit
            [out, info] = adigatorSlimDerivBody(rolledJacFile(), {'f'});
            tc.verifyTrue(info.sliced);
            tc.verifyEqual(info.dropped, 7);
            tc.verifyFalse(any(contains(out,'for cadaforcount1'))); % loop gone
            tc.verifyFalse(any(contains(out,'y.dx')));
            tc.verifyTrue(any(contains(out,'y.f = cada1f1')));
        end
    end
end

% ---------------------------- fixtures --------------------------------- %
function w = embedWrapper()
w = [ ...
    "function [Jac,Fun] = mf_Jac(x)"; ...
    "gator_x.f = x;"; ...
    "gator_x.dx = ones(2,1);"; ...
    "y = mf_ADiGatorJac(gator_x);"; ...
    "Jac = zeros(2,1);"; ...
    "Jac([1 2]) = y.dx;"; ...
    "Fun = y.f;"; ...
    "end"];
end

function w = classicWrapper()
w = [ ...
    "function [Jac,Fun] = mf_Jac(x)"; ...
    "gator_x.f = x;"; ...
    "gator_x.dx = ones(2,1);"; ...
    "y = mf_ADiGatorJac(gator_x);"; ...
    "Jac = zeros(2,1);"; ...
    "Jac(y.dx_location) = y.dx;"; ...
    "Fun = y.f;"; ...
    "end"];
end

function f = jacFile()
% a minimal but structurally faithful _ADiGatorJac file. Body lines (between
% the Start marker and 'function ADiGator_LoadData()'):
%   1 cada1f1   2 cada1d1   3 y.dx   4 y.dx_location   5 y.dx_size   6 y.f
f = [ ...
    "function y = mf_ADiGatorJac(gator_x)"; ...
    "global ADiGator_mf_ADiGatorJac"; ...
    "if isempty(ADiGator_mf_ADiGatorJac); ADiGator_LoadData(); end"; ...
    "Gator1Data = ADiGator_mf_ADiGatorJac.mf_ADiGatorJac.Gator1Data;"; ...
    "% ADiGator Start Derivative Computations"; ...
    "cada1f1 = gator_x.f.^2;"; ...
    "cada1d1 = 2.*gator_x.f.*gator_x.dx;"; ...
    "y.dx = cada1d1;"; ...
    "y.dx_location = Gator1Data.Index1;"; ...
    "y.dx_size = [2 1];"; ...
    "y.f = cada1f1;"; ...
    "end"; ...
    "function ADiGator_LoadData()"; ...
    "global ADiGator_mf_ADiGatorJac"; ...
    "load('mf_ADiGatorJac.mat')"; ...
    "end"];
end

function f = rolledJacFile()
% as jacFile, but the .dx column is assembled by a rolled for...end loop (the
% unrolled==0 dialect) over a zeros-init, so the slice must keep/drop the loop
% as a unit. Body statements: 1 cada1f1  2 cadaJac=zeros  3 for...end (block)
%   4 y.dx  5 y.dx_location  6 y.dx_size  7 y.f
f = [ ...
    "function y = mf_ADiGatorJac(gator_x)"; ...
    "global ADiGator_mf_ADiGatorJac"; ...
    "if isempty(ADiGator_mf_ADiGatorJac); ADiGator_LoadData(); end"; ...
    "Gator1Data = ADiGator_mf_ADiGatorJac.mf_ADiGatorJac.Gator1Data;"; ...
    "% ADiGator Start Derivative Computations"; ...
    "cada1f1 = gator_x.f.^2;"; ...
    "cadaJac = zeros(2,1);"; ...
    "for cadaforcount1 = 1:2"; ...
    "  cadaJac(cadaforcount1) = 2.*gator_x.f(cadaforcount1).*gator_x.dx(cadaforcount1);"; ...
    "end"; ...
    "y.dx = cadaJac;"; ...
    "y.dx_location = Gator1Data.Index1;"; ...
    "y.dx_size = [2 1];"; ...
    "y.f = cada1f1;"; ...
    "end"; ...
    "function ADiGator_LoadData()"; ...
    "global ADiGator_mf_ADiGatorJac"; ...
    "load('mf_ADiGatorJac.mat')"; ...
    "end"];
end
