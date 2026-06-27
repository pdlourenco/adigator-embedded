classdef UErtCleanOutputIndicesTest < matlab.unittest.TestCase
    % UErtCleanOutputIndicesTest  Unit test for adigatorErtCleanOutputIndices,
    % the embed-pipeline pass that makes the output-index metadata Embedded
    % Coder (ERT) safe (#80, Gap A).
    %
    % The core printer emits each derivative order's size/location by reading
    % the previous order's field ON the output struct (y.dxdx_size =
    % [y.dx_size, ...]); strict ERT codegen forbids adding a field after the
    % struct is read. The pass routes those back-references through locals so
    % the output struct is write-only. The transform must (a) be semantically
    % identity, (b) leave a 1st-order gradient untouched (no churn / no broken
    % golden fixtures), and (c) generalise to ANY derivative order.

    methods (Test)
        function gradientIsUntouched(tc)
            % 1st-order metadata is read by nothing -> the pass is a no-op.
            in = [ "y.dx = something;"
                   "y.dx_size = 8;"
                   "y.dx_location = Gator1Data.Index1;"
                   "y.f = stuff;" ];
            out = adigatorErtCleanOutputIndices(in);
            tc.verifyEqual(string(out(:)), in(:), ...
                'a gradient (no back-reference) must be returned unchanged');
            tc.verifyFalse(any(contains(out,'cadaOI')), 'no locals should be introduced');
        end

        function hessianStructIsWriteOnly(tc)
            in = [ "y.dx_size = 8;"
                   "y.dx_location = Gator1Data.Index1;"
                   "y.dxdx_size = [y.dx_size,8];"
                   "y.dxdx_location = [y.dx_location(Gator2Data.Index1,:), Gator2Data.Index2];" ];
            out = adigatorErtCleanOutputIndices(in);
            % the output struct must never be READ on any RHS (the ERT rule):
            % no `y.<field>` appears to the right of an '=' anywhere.
            for k = 1:numel(out)
                rhs = regexprep(out(k), '^[^=]*=', '');
                tc.verifyFalse(contains(rhs, 'y.'), ...
                    sprintf('output struct read on a RHS (line %d): %s', k, out(k)));
            end
            % the back-references became locals, but the y.* assignments survive.
            tc.verifyTrue(any(contains(out,"y.dxdx_size = ")), 'y.dxdx_size still assigned');
            tc.verifyTrue(any(contains(out,"y.dxdx_location = ")), 'y.dxdx_location still assigned');
            tc.verifyTrue(any(contains(out,"cadaOI_dx_location")), 'dx_location hoisted to a local');
        end

        function recursesToThirdOrder(tc)
            % 3rd order references 2nd, 2nd references 1st - the whole chain must
            % be routed through locals (the property the maintainer asked for).
            in = [ "y.dx_size = 8;"
                   "y.dx_location = G1.Index1;"
                   "y.dxdx_size = [y.dx_size,8];"
                   "y.dxdx_location = [y.dx_location(G2.Index1,:), G2.Index2];"
                   "y.dxdxdx_size = [y.dxdx_size,8];"
                   "y.dxdxdx_location = [y.dxdx_location(G3.Index1,:), G3.Index2];" ];
            out = adigatorErtCleanOutputIndices(in);
            for k = 1:numel(out)
                rhs = regexprep(out(k), '^[^=]*=', '');
                tc.verifyFalse(contains(rhs, 'y.'), ...
                    sprintf('3rd-order: struct read on a RHS (line %d): %s', k, out(k)));
            end
            % dx and dxdx (read by later orders) are hoisted; dxdxdx (terminal) is not.
            tc.verifyTrue(any(contains(out,"cadaOI_dxdx_location")), 'dxdx hoisted (read by 3rd order)');
            % substring-safety: the 3rd-order read of dxdx_location must redirect
            % to cadaOI_DXDX_location, NOT be corrupted via the dx_location field
            % (dx_location is a substring of dxdx_location).
            tc.verifyTrue(any(contains(out,"[cadaOI_dxdx_location(G3.Index1,:), G3.Index2]")), ...
                'dxdx_location read must redirect to its own local, uncorrupted');
            tc.verifyFalse(any(contains(out,"cadaOI_dx_location(G3")), ...
                'dx_location local must not leak into the dxdx_location read');
        end
    end
end
