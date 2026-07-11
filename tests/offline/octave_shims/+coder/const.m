function y = const(x)
%CODER.CONST  License-free shim for ADiGator inline-embedded fixtures.
%
% Inline embed mode patches the generated derivative to wrap its constant data
% in coder.const(...) (a MATLAB Coder directive that, outside codegen, is simply
% identity). This shim lets the committed inline fixtures under
% tests/fixtures/gen_dialect/ run license-free in GNU Octave - and on MATLAB
% installs without the Coder toolbox - so the offline equivalence guard
% (tests/offline/gap_interproc_equiv.m) can execute them.
%
% It is added to the path ONLY when coder.const is otherwise unavailable
% (see gap_interproc_equiv), so it never shadows MATLAB's real coder.const.
%
% Copyright Pedro Lourenço and GMV. Distributed under the GNU General Public License version 3.0.
y = x;
end
