function out = adigatorErtCleanOutputIndices(lines)
%adigatorErtCleanOutputIndices  Make output-index metadata Embedded-Coder safe.
%
%   OUT = adigatorErtCleanOutputIndices(LINES) rewrites the derivative
%   subfunction's output-index bookkeeping so the output struct is *written
%   only*, never read-then-grown.
%
%   The core printer (lib/@cada/adigatorPrintOutputIndices.m) emits each
%   derivative order's sparsity metadata by referencing the previous order's
%   field ON THE OUTPUT STRUCT, e.g.
%
%       y.dx_size       = 8;
%       y.dx_location   = Gator1Data.Index1;
%       y.dxdx_size     = [y.dx_size, 8];                              % reads y
%       y.dxdx_location = [y.dx_location(Gator2Data.Index1,:), Gator2Data.Index2];
%
%   Reading y.dx_size and then adding the new field y.dxdx_size is exactly the
%   pattern strict Embedded Coder (ERT) codegen forbids ("addition of new
%   fields after a structure has been read or used"). Plain MATLAB Coder
%   tolerates it; ERT does not (issue #80). These metadata fields are dead in
%   the terminal embedded file, but they must still codegen.
%
%   The fix routes every <out>.<order>_size / <out>.<order>_location assignment
%   through a local, and rewrites later orders to read the PREVIOUS order's
%   LOCAL instead of the struct field:
%
%       cadaOI_dx_size       = 8;            y.dx_size       = cadaOI_dx_size;
%       cadaOI_dx_location   = Gator1Data.Index1; y.dx_location = cadaOI_dx_location;
%       cadaOI_dxdx_size     = [cadaOI_dx_size, 8];        y.dxdx_size = cadaOI_dxdx_size;
%       cadaOI_dxdx_location = [cadaOI_dx_location(Gator2Data.Index1,:), Gator2Data.Index2];
%       y.dxdx_location      = cadaOI_dxdx_location;
%
%   The transform is CHAIN-GENERAL: it follows the order chain in source order
%   (which the printer emits low-order-first), so it is correct for the
%   gradient, the Hessian, and any higher order (3rd, 4th, ...) the routine can
%   produce - the property the maintainer asked for. It is semantically the
%   identity (the locals carry the same values), so derivative values are
%   unchanged.
%
%   Copyright 2026 Pedro Lourenço

out = string(lines(:));

% Match an output-index metadata assignment:  <indent><var>.<name>_size = <rhs>;
% (or _location). The generated subfunction contains no inline comments on
% these lines, so the RHS runs to the final ';'.
pat = '^(\s*)([A-Za-z]\w*)\.([A-Za-z]\w*_(?:size|location))\s*=\s*(.*?);\s*$';

mLine = false(numel(out),1);      % is this a metadata assignment?
mOut = strings(numel(out),1);     % output variable
mFld = strings(numel(out),1);     % field, e.g. "dx_location"
for i = 1:numel(out)
    tok = regexp(out(i), pat, 'tokens', 'once');
    if isempty(tok); continue; end
    mLine(i) = true; mOut(i) = tok(2); mFld(i) = tok(3);
end

% Fail loud (principle 1) if a metadata-shaped ASSIGNMENT did not match the
% strict single-line pattern - e.g. an upstream stage wrapped the RHS across
% lines or appended an inline comment. Silently missing such a line would leave
% the struct read-then-grown and re-break ERT codegen with no warning.
% Anchored at line start (after indent) so it matches an ASSIGNMENT line but
% never the same text inside a "% Deriv ... Line:" comment.
loosePat = '^\s*[A-Za-z]\w*\.[A-Za-z]\w*_(?:size|location)\s*=(?!=)';
for i = 1:numel(out)
    if mLine(i); continue; end
    if ~isempty(regexp(out(i), loosePat, 'once'))
        error('adigatorErtCleanOutputIndices:unexpectedShape', ...
            ['Output-index metadata line did not match the expected single-line ' ...
             'shape; the ERT-safety pass cannot guarantee it (line %d): %s'], i, out(i));
    end
end

if ~any(mLine); return; end       % nothing to do (e.g. a 1st-order gradient)

% A field needs a local only if a LATER metadata line READS it off the struct
% (<out>.<field>); 1st-order metadata is read by nothing and is left untouched,
% so only Hessian-and-higher files change.
readByLater = false(numel(out),1);
idx = find(mLine);
for a = 1:numel(idx)
    rhsA = regexp(out(idx(a)), pat, 'tokens', 'once'); rhsA = rhsA(4);
    for b = 1:a-1   % earlier metadata lines whose field this RHS might read
        if contains(rhsA, mOut(idx(b)) + "." + mFld(idx(b)))
            readByLater(idx(b)) = true;
        end
    end
end

% Rewrite: redirect every read of a hoisted field to its local, and hoist
% (assign through a local) only the fields that are read later.
localOfFld = @(f) "cadaOI_" + f;
for a = 1:numel(idx)
    i = idx(a);
    tok = regexp(out(i), pat, 'tokens', 'once');
    indent = tok(1); outvar = tok(2); field = tok(3); rhs = tok(4);
    for b = 1:a-1
        j = idx(b);
        if ~readByLater(j); continue; end
        % The full 'y\.<field>' literal anchor (not just the trailing \>) is what
        % prevents matching y.dx_location *inside* y.dxdx_location: the bare field
        % 'dx_location' is a substring of 'dxdx_location', but 'y.dx_location' is
        % not a substring of 'y.dxdx_location'. Do not simplify to match just the
        % field name - it would corrupt the longer order's name.
        ref = regexptranslate('escape', mOut(j) + "." + mFld(j));
        rhs = regexprep(rhs, ref + "\>", localOfFld(mFld(j)));
    end
    if readByLater(i)
        local = localOfFld(field);
        out(i) = indent + local + " = " + rhs + ";" + newline + ...
                 indent + outvar + "." + field + " = " + local + ";";
    else
        out(i) = indent + outvar + "." + field + " = " + rhs + ";";
    end
end

% Split any 2-statement rewrites back into individual lines. Safe because the
% printer emits no embedded newline within a line, so join/split on newline is
% lossless (blank lines and any trailing CR survive symmetrically).
out = split(join(out, newline), newline);
end
