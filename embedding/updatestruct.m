function out=updatestruct(default,in,addfields)
%UPDATESTRUCT   create structure based on default values for all fields
%               updated with structure with potentially fewer fields
%
%   Input:
%       default     base structure
%       in          input structure (only fields coincident with default
%                   are copied)
%       addfields   (optional) boolean to add new fields if the input
%                   structure has fields not present in the default one
%
%   Output:
%       out         base structure updated according to in structure
%
%	Dependencies:
%		none
%
%   Copyright GMV.
%   2022-09  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%
%   Changelog:
%       2025-10 PADL    Add option to add new fields if the input structure
%                       has fields that the default one does not

if nargin<3
    addfields = false;
end

out = default;

complete_fields = fieldnames(default); % list of root fields in default
input_fields = fieldnames(in); % list of root fields in input struct

% run through the input structure fields
for ii=1:length(input_fields)
    if isfield(out,input_fields{ii}) % field exists
        if isstruct(out.(input_fields{ii})) % if it is a struct check nested field
            out.(input_fields{ii}) = updatestruct(default.(input_fields{ii}),in.(input_fields{ii}),addfields);
        else % if it is a simple field, copy it using the same variable type
            out.(input_fields{ii}) = feval(class(out.(input_fields{ii})),in.(input_fields{ii}));
        end
    elseif addfields % add field to default structure if it does not exist
        out.(input_fields{ii}) = in.(input_fields{ii});
    end
end