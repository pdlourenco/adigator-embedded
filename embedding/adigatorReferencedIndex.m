function ref = adigatorReferencedIndex(lines, funcNames)
%ADIGATORREFERENCEDINDEX  Which Gator*Data.Index* each generated function reads.
%
% The data half of slice-before-prune (issue #21 / ROADMAP R7b): once the
% derivative code has been slimmed, scan it to learn which per-function
% Gator<d>Data.Index<n> constants the surviving code still references, so
% prune_adigator_mat can drop the now-dead index tables from the embedded data
% (see adigatorGenDerFile_embedded, prune_adigator_mat).
%
%   Input:
%       lines      string array or cellstr - the lines of the generated
%                  derivative file (genfile.m), AFTER slimming.
%       funcNames  cellstr/string - the generated function names
%                  (genfile.func), i.e. the top-level fields of the static-data
%                  struct that prune_adigator_mat walks.
%
%   Output:
%       ref        struct keyed by function name. ref.(fn) is present ONLY for
%                  a function whose body was parsed with confidence; its value
%                  is a struct with
%                      .index  cellstr of "Gator<d>Data.Index<n>" tokens the
%                              function references,
%                      .table  cellstr of "Gator<d>Data" table names the
%                              function references (bare or via any subfield).
%                  A function name ABSENT from ref means "unknown / not
%                  confidently parsed" and prune_adigator_mat then keeps ALL of
%                  that function's Index* (the unchanged default).
%
% Conservative by construction. Index access in ADiGator-generated code is
% always the literal token Gator<d>Data.Index<n>. If a function body uses a
% Gator*Data table any other way - a dynamic field Gator1Data.(v), or aliasing
% / passing the bare table to another variable - a static token scan could miss
% a live index, so such a function is dropped from ref (prune keeps all its
% Index*) rather than risk under-keeping. A wrongly *dropped* index is a wrong
% derivative; a wrongly *kept* one is a few bytes (REVIEW_CONTEXT principle 1).
%
% Char/cellstr + regexp throughout (no string/extractBefore), so the real
% function runs in both MATLAB and GNU Octave and can be exercised license-free
% (tests/offline/prune_shrink_offline_checks.m).
%
%   Copyright Pedro Lourenço and GMV.
%   Distributed under the GNU General Public License v3.0
%
%   Changelog:
%       2026-06    Created for the slice-before-prune data half (issue #21).
%
% see also prune_adigator_mat, adigatorSlimEmbeddedDeriv, adigatorGenDerFile_embedded

ref   = struct();
lines = cellstr(lines(:));
want  = cellstr(funcNames(:));

% function-definition lines: "function" as a whole word at line start (a
% leading '%' is not whitespace, so commented headers never match). The
% trailing [\s(] is a portable word boundary (Octave's regexp does not honour
% \b), and also rejects identifiers like "functionfoo".
isDef = ~cellfun('isempty', regexp(lines, '^\s*function[\s(]', 'once'));
starts = find(isDef);

for k = 1:numel(starts)
    first = starts(k);
    last  = numel(lines);
    if k < numel(starts)
        last = starts(k+1) - 1;
    end

    % the function name is the identifier immediately before the first '('
    nm = regexp(lines{first}, 'function[^(]*?(\w+)\s*\(', 'tokens', 'once');
    if isempty(nm) || ~any(strcmp(nm{1}, want))
        continue % not one of the data-struct functions -> ignore this block
    end
    name = nm{1};

    [idxTok, tblTok, unsafe] = scanBlock(lines(first:last));
    if unsafe
        continue % leave NAME out of ref -> prune keeps all its Index*
    end
    ref.(name) = struct('index', {unique(idxTok)}, 'table', {unique(tblTok)});
end
end

%% --------------------------------------------------------------------- %%
function [idxTok, tblTok, unsafe] = scanBlock(blk)
% Collect the Gator<d>Data.Index<n> tokens (idxTok) and the Gator<d>Data table
% names (tblTok) referenced in a function block, flagging UNSAFE if the block
% touches a Gator*Data table in any way other than the literal field/table
% access the generated dialect uses.
idxTok = {};
tblTok = {};
unsafe = false;

for li = 1:numel(blk)
    % drop comments: the generated derivative dialect never uses '%' as an
    % operator, so everything from the first '%' on is comment. (This assumes no
    % char literal containing '%' shares a line with an index access - true for
    % the bare mechanical assignment lines ADiGator emits; see ADR-0010.) Keeps
    % a Gator*Data mention inside a comment from spuriously keeping (or, via the
    % unsafe guard, over-keeping) an index table.
    code = regexprep(blk{li}, '%.*$', '');
    [s, e, tok] = regexp(code, 'Gator\d+Data', 'start', 'end', 'match');
    for i = 1:numel(s)
        pre  = strtrim(code(1:s(i)-1));         % text before the token
        rest = strtrim(code(e(i)+1:end));       % text after the token

        if ~isempty(pre) && pre(end) == '.'
            tblTok{end+1} = tok{i};             %#ok<AGROW> % parent.Gator<d>Data
            % Defensive (not in today's dialect, which binds the table to a
            % local before indexing): a chained parent.Gator<d>Data.Index<n>
            % still records its index here, so it can never be under-kept.
            if ~isempty(rest) && rest(1) == '.'
                f2 = regexp(rest(2:end), '^\s*(\w+)', 'tokens', 'once');
                if ~isempty(f2) && strncmp(f2{1}, 'Index', 5)
                    idxTok{end+1} = [tok{i} '.' f2{1}]; %#ok<AGROW>
                end
            end
            continue
        end
        if numel(rest) >= 2 && strcmp(rest(1:2), '.(')
            unsafe = true; return              % dynamic field Gator<d>Data.(...)
        elseif ~isempty(rest) && rest(1) == '.'
            fld = regexp(rest(2:end), '^\s*(\w+)', 'tokens', 'once');
            if isempty(fld)
                unsafe = true; return          % '.' not followed by a name
            end
            tblTok{end+1} = tok{i};             %#ok<AGROW>
            if strncmp(fld{1}, 'Index', 5)
                idxTok{end+1} = [tok{i} '.' fld{1}]; %#ok<AGROW>
            end
            % Data* fields are governed by prune's non-empty rule, not here.
        elseif ~isempty(rest) && rest(1) == '=' && ~(numel(rest) >= 2 && rest(2) == '=')
            tblTok{end+1} = tok{i};             %#ok<AGROW> % canonical local def: Gator<d>Data = ...
        else
            unsafe = true; return              % bare table aliased/passed/indexed
        end
    end
end
end
