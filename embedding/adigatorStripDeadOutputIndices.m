function out = adigatorStripDeadOutputIndices(lines)
%adigatorStripDeadOutputIndices  Remove dead output-index metadata for ERT.
%
%   OUT = adigatorStripDeadOutputIndices(LINES) deletes the output-index
%   sparsity metadata assignments - y.<order>_size and y.<order>_location (and
%   the "% Deriv ... Line:" comments that echo them) - from an embeddable
%   derivative subfunction.
%
%   Why: the core printer (lib/@cada/adigatorPrintOutputIndices.m) emits each
%   order's metadata by reading the previous order's field on the output struct
%   then adding a new field in the same statement, e.g.
%
%       y.dxdx_size     = [y.dx_size, 8];
%       y.dxdx_location = [y.dx_location(Gator2Data.Index1,:), Gator2Data.Index2];
%
%   Strict Embedded Coder (ERT) codegen forbids adding a field after a struct is
%   read ("addition of new fields after a structure has been read or used"), so
%   these lines break ERT (#80, Gap A). They are DEAD in the terminal embedded
%   wrapper - it assembles results from hardcoded index lists (e.g.
%   Hes([1 10 19 ...]) = y.dxdx) and never reads `_size`/`_location` - so the
%   right fix is to not emit them, not to rewrite dead code to be legal.
%
%   `slim_embed=1` (the default) already removes them via demand slicing; this
%   pass makes the removal UNCONDITIONAL for the embeddable modes (inline /
%   coderload) so `slim_embed=0` also codegens under ERT. Classic mode ('c')
%   returns before the embed pipeline, so the raw generated form - metadata
%   included - remains observable there.
%
%   The index tables the stripped metadata referenced become unreferenced;
%   `slim_embed=1` prunes them, `slim_embed=0` keeps them (dead `static const`
%   the C compiler drops) - consistent with the slim/no-slim distinction.
%
%   A user OUTPUT field literally named *_size / *_location with a bare
%   numeric/bracket-literal value is the one (exotic) case the RHS guard cannot
%   distinguish from metadata; such a field would be stripped. Any non-literal
%   user RHS is safe.
%
%   Copyright 2026 Pedro Lourenço @ GMV. Distributed under the GNU General
%   Public License version 3.0.

out = string(lines(:));

% A metadata assignment "<var>.<name>_size|_location = <rhs>", optionally behind
% a "% Deriv N Line:" echo comment. Anchored at line start (after indent) so it
% never matches the same text elsewhere; requires the trailing "_size"/
% "_location" so value lines (y.dx, y.dxdx, y.f) are untouched.
pat = '^\s*(?:%\s*Deriv[^:]*:\s*)?[A-Za-z]\w*\.[A-Za-z]\w*_(?:size|location)\s*=\s*(.*?);?\s*$';

% RHS guard: only strip when the right-hand side has the printer's metadata
% shape - a Gator*Data index reference, a back-reference to a prior
% _size/_location, or a numeric/bracket size literal. This protects a user
% OUTPUT field that happens to be named *_size / *_location: its value line
% (y.foo_size = someUserExpr) has an arbitrary RHS and is left alone (principle
% 1 - never silently corrupt an output). The one residual is a user field
% literally named *_size/*_location whose value is a bare numeric/bracket
% literal; that is documented as a known (exotic) limitation.
rhsGuard = '(?:Gator\d+Data|_(?:size|location)\>|^\s*\[?\s*[+-]?\d)';

keep = true(numel(out),1);
for i = 1:numel(out)
    % char input -> regexp 'tokens' always returns a cell (version-stable; the
    % string-vs-cell return only bites char-vs-string for 'tokens').
    tok = regexp(char(out(i)), pat, 'tokens', 'once');
    if isempty(tok); continue; end
    if ~isempty(regexp(tok{1}, rhsGuard, 'once', 'start'))
        keep(i) = false;
    end
end
out = out(keep);
end
