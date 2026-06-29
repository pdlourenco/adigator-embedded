classdef UStripDeadOutputIndicesTest < AdigatorTestCase
    % UStripDeadOutputIndicesTest  Unit test for adigatorStripDeadOutputIndices,
    % the embed-pipeline pass that removes the dead output-index metadata so the
    % embeddable derivative codegens under strict Embedded Coder (ERT) (#80,
    % Gap A). The metadata (y.<order>_size / _location) is unread by the terminal
    % wrapper and its read-then-add-field shape breaks ERT, so it is deleted.
    %
    % Subclasses AdigatorTestCase (#82) for the repo source paths (incl.
    % embedding/, where adigatorStripDeadOutputIndices lives).

    methods (Test)
        function stripsSizeAndLocationLines(tc)
            in = [ "y.dx = cada1td1;"
                   "y.f = sum(stuff);"
                   "y.dx_size = 8;"
                   "y.dx_location = Gator1Data.Index1;"
                   "y.dxdx_size = [y.dx_size,8];"
                   "y.dxdx_location = [y.dx_location(Gator2Data.Index1,:), Gator2Data.Index2];" ];
            out = adigatorStripDeadOutputIndices(in);
            % the value lines survive; all metadata lines are gone.
            tc.verifyEqual(string(out(:)), ["y.dx = cada1td1;"; "y.f = sum(stuff);"]);
            tc.verifyFalse(any(contains(out,"_size")), 'no _size metadata remains');
            tc.verifyFalse(any(contains(out,"_location")), 'no _location metadata remains');
        end

        function stripsEchoComments(tc)
            in = [ "y.dx_size = 8;"
                   "% Deriv 1 Line: y.dx_size = 8;"
                   "y.dx_location = Gator1Data.Index1;"
                   "% Deriv 1 Line: y.dx_location = Gator1Data.Index1;" ];
            out = adigatorStripDeadOutputIndices(in);
            tc.verifyEmpty(out, 'metadata assignments AND their echo comments are removed');
        end

        function leavesValueLinesAndOtherCommentsUntouched(tc)
            % Value fields (y.dx, y.dxdx, y.f) and unrelated comments must stay;
            % only *_size / *_location assignments (and their echoes) go.
            in = [ "y.dxdx = cada1f3dxdx;"
                   "% Deriv 1 Line: y.dx = cada1f3dx;"
                   "cada1f1 = exp(x.f);"
                   "y.dx_size = 8;" ];
            out = adigatorStripDeadOutputIndices(in);
            tc.verifyEqual(string(out(:)), [ "y.dxdx = cada1f3dxdx;"
                                             "% Deriv 1 Line: y.dx = cada1f3dx;"
                                             "cada1f1 = exp(x.f);" ]);
        end

        function preservesUserFieldWithArbitraryRhs(tc)
            % A user OUTPUT field named *_size / *_location with a non-literal
            % RHS must NOT be stripped (principle 1: never corrupt an output).
            % Only metadata-shaped RHS (Gator*Data / prior _size/_location /
            % numeric literal) is removed.
            in = [ "y.window_size = numel(x);"          % user field -> keep
                   "y.peak_location = findPeak(x);"     % user field -> keep
                   "y.dx_location = Gator1Data.Index1;" % metadata  -> strip
                   "y.dxdx_size = [y.dx_size,8];" ];    % metadata  -> strip
            out = adigatorStripDeadOutputIndices(in);
            tc.verifyEqual(string(out(:)), ...
                ["y.window_size = numel(x);"; "y.peak_location = findPeak(x);"]);
        end

        function emptyAndGradientInputs(tc)
            tc.verifyEmpty(adigatorStripDeadOutputIndices(strings(0,1)));
            % a gradient still has dx_size/_location (1st order) - they are dead
            % too and get stripped; the value line stays.
            g = [ "y.dx = grad;"; "y.dx_size = 8;"; "y.dx_location = Gator1Data.Index1;" ];
            tc.verifyEqual(string(adigatorStripDeadOutputIndices(g)), "y.dx = grad;");
        end
    end
end
