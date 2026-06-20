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

        function bailsOnRolledControlFlow(tc)
            f = jacFile();
            f(8) = "for cadaforcount1 = 1:2"; % rolled loop in the body
            [~, info] = adigatorSlimDerivBody(f, {'f','dx'});
            tc.verifyFalse(info.sliced);
            tc.verifyTrue(startsWith(info.reason,'cannot slice'));
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
