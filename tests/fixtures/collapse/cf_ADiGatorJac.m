% SYNTHETIC fixture for the R7c union-copy peephole driver path (issue #44
% item 2 / R10(b)). It mirrors the structure of a real classic-mode
% _ADiGator* Jacobian derivative file (header skeleton, the load-into-global
% line, the derivative-computations body marker, the result fields, and the
% data-loader trailer), but is HAND-WRITTEN for one purpose: to contain a
% single ORDERED-IDENTITY union copy of the generic form
%
%     v = zeros(K,1); v(Idx,1) = src;   % Idx == (1:K).'
%
% which adigatorPeepholeUnionCopy collapses to a single reshape statement.
% (The concrete instance is in the code below; it is intentionally NOT repeated
% verbatim in these comments, so a text scan of the file for the collapsed
% statement sees only the live code, not an illustrative copy.)
%
% Why synthetic: a probe of ~40 generated Jacobians/Hessians (straight-line,
% rolled, and unrolled) found that adigator's emitter never produces this
% ordered-identity FULL fill - real overmaps are always strict PARTIAL fills
% into a union-sized buffer (e.g. Index=[1 2] into zeros(4,1)), and equal-
% pattern unions are added directly with no buffer at all (see
% docs/ANALYSIS.md §2.3(6)). The collapse is therefore correct-but-unreachable
% on today's generated code; this fixture exercises the driver wiring positively
% so a silent no-op regression in adigatorSlimEmbeddedDeriv's R7c path is caught.
%
% NOTE: the comment text deliberately avoids the literal body-marker phrase and
% the literal data-loader header line - the driver locates the body by a
% substring/equality match on those, so repeating them here would mis-mark the
% body. The markers appear exactly once each, in the code below.
%
% The encoded user function is the identity y = x, so the union copy is a true
% no-op and the reshape rewrite is exactly equivalent - the driver's numeric
% round-trip cross-check passes. Driven through the real driver by
% tests/integration/IPeepholeDriverTest.m (TS-I-08).
%
% Copyright GMV. Distributed under the GNU General Public License version 3.0.
function y = cf_ADiGatorJac(x)
global ADiGator_cf_ADiGatorJac
if isempty(ADiGator_cf_ADiGatorJac); ADiGator_LoadData(); end
Gator1Data = ADiGator_cf_ADiGatorJac.cf_ADiGatorJac.Gator1Data;
% ADiGator Start Derivative Computations
cada1td1 = zeros(3,1);
cada1td1(Gator1Data.Index1,1) = x.dx;
y.dx = cada1td1;
y.f = x.f;
%User Line: y = x;
y.dx_size = [3,3];
y.dx_location = Gator1Data.Index2;
end


function ADiGator_LoadData()
global ADiGator_cf_ADiGatorJac
ADiGator_cf_ADiGatorJac = load('cf_ADiGatorJac.mat');
return
end
