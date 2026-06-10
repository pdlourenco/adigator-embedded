function structout = prune_adigator_mat(structin,funnames)
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

structout = struct();

for jj = 1:numel(funnames) % go through each of the functions
    if isfield(structin,funnames{jj}) % if field exists, save it
        fn = fieldnames(structin.(funnames{jj}));
        keepTop = fn(startsWith(fn, "Gator") & endsWith(fn,"Data"));
        auxstruct = struct();

        for ii = 1:numel(keepTop)
            gname = keepTop{ii};
            G = structin.(funnames{jj}).(gname);
            if ~isstruct(G), continue; end
            fG = fieldnames(G);

            % Keep the only subfields that are not empty
            keepIdx = check_adigator_mat_empty(G,fG);

            % Keep Index* subfields
            keepIdx = startsWith(fG, "Index") | keepIdx;
            if ~any(keepIdx), continue; end

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
