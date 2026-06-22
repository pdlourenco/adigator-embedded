function structout = prune_adigator_mat(structin,funnames,referenced)
%PRUNE_ADIGATOR_MAT     Prune an ADiGator-generated data struct for embedding
%
% Keep only <funcName>.Gator*Data.{Index*, non-empty} fields per derivative
% function. Down-cast Index* fields (always integer index arrays, see
% lib/cadaUtils/cadaindprint.m) to int32/uint32 to shrink embedded constants.
%
% IMPORTANT: Data* fields (see lib/cadaUtils/cadamatprint.m) hold numeric
% value constants that the generated code uses in *arithmetic* (e.g.
% cada1f1 = Gator1Data.Data1*x.f). They must remain double: down-casting
% them to integer classes makes MATLAB integer-arithmetic rules apply
% (errors on integer-matrix * double-matrix, silent rounding otherwise).
% Only Index* fields, which are exclusively used for indexing, are safe to
% down-cast.
%
%   Input:
%       structin    struct loaded from the ADiGator-generated .mat file
%       funnames    cell array of generated function names (fields of structin)
%       referenced  (optional) the slice-before-prune data-shrink map from
%                   adigatorReferencedIndex: a struct keyed by function name
%                   recording, per confidently-parsed function, which
%                   Gator<d>Data.Index<n> the slimmed code still references
%                   (.index) and which Gator<d>Data tables it references
%                   (.table). When supplied, an Index* field is kept only if
%                   the slimmed code references it (issue #21 / ROADMAP R7b: the
%                   dead per-subfunction index tables drop here once the slice
%                   has removed their readers). Omitted, empty, or missing a
%                   given function => ALL of that function's Index* are kept,
%                   the unchanged default. See adigatorReferencedIndex for the
%                   conservative keep-all-on-doubt contract.
%
%   Output:
%       structout   pruned struct containing only the runtime-needed fields
%
%   Copyright GMV, S.A.
%   Property of GMV, S.A.; all rights reserved
%
%   Changelog:
%       2026-06    Extracted from adigatorGenDerFile_embedded for testability.
%                  Restrict integer down-casting to Index* fields (Data*
%                  stays double). Use exact integer check. Initialize output.
%                  Optional REFERENCED map drops Index* the slimmed code no
%                  longer reads (slice-before-prune data half, issue #21).

if nargin < 3, referenced = struct(); end

structout = struct();

for jj = 1:numel(funnames) % go through each of the functions
    if isfield(structin,funnames{jj}) % if field exists, save it
        fn = fieldnames(structin.(funnames{jj}));
        keepTop = fn(startsWith(fn, "Gator") & endsWith(fn,"Data"));
        auxstruct = struct();

        % Slice-before-prune (issue #21): when the slimmed code was scanned
        % (adigatorReferencedIndex) and this function parsed confidently, keep
        % an Index* only if the code still references it; otherwise keep ALL
        % Index* (unchanged behaviour). REF.(fn) absent => keep-all.
        hasRef = isfield(referenced, funnames{jj});
        if hasRef
            refIndex = referenced.(funnames{jj}).index;  % "Gator<d>Data.Index<n>" tokens
            refTable = referenced.(funnames{jj}).table;  % "Gator<d>Data" tokens
        end

        for ii = 1:numel(keepTop)
            gname = keepTop{ii};
            G = structin.(funnames{jj}).(gname);
            if ~isstruct(G), continue; end
            fG = fieldnames(G);

            % Keep the only subfields that are not empty
            keepIdx = check_adigator_mat_empty(G,fG);

            isIndex = startsWith(fG, "Index");
            if hasRef
                % Keep an Index* iff the slimmed code references it; Data*
                % stays governed by the non-empty rule above. (cellstr + strcmp
                % so this matches adigatorReferencedIndex and runs in Octave.)
                tok = strcat(gname, '.', fG);
                refKeep = (keepIdx & ~isIndex) | (isIndex & ismember(tok, refIndex));
                if ~any(refKeep) && any(strcmp(gname, refTable))
                    % Shrinking would empty a table the slimmed code still
                    % references (the "Gator<d>Data = coder.const(
                    % <data>.Gator<d>Data)" boilerplate reads it even when it
                    % indexes nothing). Fall back to the UNSHRUNK keep-set for
                    % this table, so the emitted data keeps its existing,
                    % codegen-proven shape rather than a zero-field struct that
                    % coder.const has never been exercised on (ADR-0010).
                    keepIdx = isIndex | keepIdx;
                else
                    keepIdx = refKeep;
                end
            else
                % Keep ALL Index* subfields (unchanged default)
                keepIdx = isIndex | keepIdx;
            end
            if ~any(keepIdx), continue; end % table fully dead -> drop it

            G2 = struct();
            idxNames = fG(keepIdx);
            for k = 1:numel(idxNames)
                idxName = idxNames{k};
                A = G.(idxName);

                % Down-cast Index* arrays (and only those) to save memory.
                % Exact integer check to avoid rounding near-integer floats.
                if startsWith(idxName,"Index") && ~issparse(A) && isnumeric(A) ...
                        && isreal(A) && all(isfinite(A(:))) && isequal(A, round(A))
                    % Nonnegative? prefer uint32; otherwise int32
                    if all(A(:) >= 0)
                        A = uint32(A);
                    else
                        A = int32(A);
                    end
                end
                % Data* value constants, logicals, and anything else left as-is
                G2.(idxName) = A;
            end

            if ~isempty(fieldnames(G2))
                auxstruct.(gname) = G2;
            end
        end
        structout.(funnames{jj}) = auxstruct;
    end
end
end

function keepIdx = check_adigator_mat_empty(structin,fields)

keepIdx = false(size(fields));

for ii = 1:numel(fields)
    keepIdx(ii) = ~isempty(structin.(fields{ii}));
end
end
