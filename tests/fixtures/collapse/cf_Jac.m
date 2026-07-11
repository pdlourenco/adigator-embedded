% SYNTHETIC wrapper paired with cf_ADiGatorJac.m for the R7c peephole driver
% test (issue #44 item 2 / R10(b), TS-I-08). Mirrors a real classic-mode
% Jacobian wrapper: it seeds the derivative input, calls the _ADiGator*
% derivative once, scatters the nonzero derivative vector into the dense
% Jacobian through the generation-time location table, and returns the value.
% The encoded user function is the identity y = x (a 3-vector), so the assembled
% Jacobian is the 3x3 identity. Used only to give adigatorWrapperDemand a real
% wrapper to read the demanded result fields from, and to let the driver's
% numeric round-trip cross-check evaluate the (un)slimmed derivative.
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public License version 3.0.
function [Jac,Fun] = cf_Jac(x)
gator_x.f = x;
gator_x.dx = ones(3,1);
y = cf_ADiGatorJac(gator_x);
Jac = zeros(3,3);
Jac((y.dx_location(:,2)-1)*3+y.dx_location(:,1)) = y.dx;
Fun = y.f;
end
