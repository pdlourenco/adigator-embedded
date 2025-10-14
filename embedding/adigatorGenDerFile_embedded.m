function info = adigatorGenDerFile_embedded(DerType,UserFunName,UserFunInputs,varargin)
%TODO:  Missing header
%TODO:  Modify gradients and Jacobians to output in column form, i.e.,
%       replace the Grd = reshape(y.dz,[row col]); line by
%                   Grd = reshape(y.dz,[col row]);
%       This line only appears in the AdigatorGeneratedFiles(ii).name file,
%       a dedicated patcher needs to do it (e.g., while it adds the
%       %#codegen header

%% -------------------------- ARGUMENTS PARSING -------------------------%%
% parse options
opts = adigatorOptions();
if nargin>3
    optfields = fieldnames(varargin{1});
    for Fcount = 1:length(optfields)
        opts.(lower(optfields{Fcount})) = varargin{1}.(lower(optfields{Fcount}));
    end
else
    varargin = {opts};
end

%% --------------------- Call the ADiGator wrappers ---------------------%%
switch DerType
    case 'jacobian'
        info = adigatorGenJacFile(UserFunName,UserFunInputs,varargin{:});
    case 'hessian'
        info = adigatorGenHesFile(UserFunName,UserFunInputs,varargin{:});
    case 'gradient'
        info = adigatorGenJacFile(UserFunName,UserFunInputs,varargin{:},'Grd');
    otherwise
        error('Unsupported derivative type: %s', DerType);
end

switch opts.embed_mode
    case 'c' % classical mode, no embedding
        fprintf('User selected classical mode, no processing needed, exiting.\n');
        return;
    case 'i' % inline mode
        inline = true; coderload = false;
        fprintf('User selected inline mode (static data embedded in a function).\n');
    case 'l' % coderload
        coderload = true; inline = false;
        fprintf('User selected coderload mode.\n')
    otherwise
        error('unkown embed_mode option %s',opts.embed_mode);
end

%% ------------ Post-process according to user instructions -------------%%
% this is a structure array that includes all the files associated with all
% the derivatives in the form:
% .main - wrapper for calling adigator processing functions - path
% .m    - adigator generated processing of derivative (to be processed for embedding in main) - path
% .mat  - adigator generated static data (to be processed if user options = 'inline') - path
% .name - name of the main file
% .dername - name of the adigator generated processing
% .func - cell with the list of functions inside the .m file
%
% each element of the array is a single derivative (all files are standalone)
AdigatorGeneratedFiles = info.GenFiles;
N_derivs = length(AdigatorGeneratedFiles);

% go through each derivative
for ii = 1:N_derivs
    fprintf('Processing derivative #%d...\n',ii);

    %%% process the data file to prune it of unnecessary data for derivative evaluation
    fprintf('\t Processing static data file (cleaning up unnecessary data)... ');
    % TODO this matfile should have several different variables depending
    % on the subfunctions. the current version considers only the main
    % function
    tmp_adigator_struct = load(AdigatorGeneratedFiles(ii).mat); % load data
    tmp_adigator_struct = prune_adigator_mat(tmp_adigator_struct,AdigatorGeneratedFiles(ii).func); % remove unnecessary fields
    save(AdigatorGeneratedFiles(ii).mat,'-struct','tmp_adigator_struct'); % replace existing mat file with the relevant fields only
    fprintf('done.\n');

    %%% if user requests inline option, the data is loaded from a function
    if inline
        % generate new data function (tmp)
        fprintf('\t\t Generating data function(s) as requested in inline mode...');
        for funidx=1:numel(AdigatorGeneratedFiles(ii).func)
            AdigatorGeneratedFiles(ii).data{funidx} = ['data_',AdigatorGeneratedFiles(ii).name,'_',AdigatorGeneratedFiles(ii).func{funidx}];
            AdigatorGeneratedFiles(ii).datapath{funidx} = structure_to_embed_mfile(AdigatorGeneratedFiles(ii).data{funidx},...
                                                            tmp_adigator_struct.(AdigatorGeneratedFiles(ii).func{funidx}),AdigatorGeneratedFiles(ii).path);
        end
        fprintf('done.\n');

        % patch the adigator generated derivative file
        fprintf('\t Processing ADiGator derivative file... ');
        % adigator_patch_derivative(AdigatorGeneratedFiles(ii).m,AdigatorGeneratedFiles(ii).dername,AdigatorGeneratedFiles(ii).data{funidx})
        % TODO - WIP
        fprintf('done.\n');

        % cleanup (derivative file)
        deletd(AdigatorGeneratedFiles(ii).m);
        % cleanup (static data file)
        delete(AdigatorGeneratedFiles(ii).mat);
    end

    %%% if user requests the coderload option, the data is loaded at compile time from a file
    if coderload
        % patch the adigator generated derivative file
        fprintf('\t Processing ADiGator derivative file... ');
        auxiliary_deriv_filecontents = adigator_patch_derivative(AdigatorGeneratedFiles(ii).m,AdigatorGeneratedFiles(ii).dername,0);
        fprintf('done.\n');

        % cleanup (remove derivative file)
        delete(AdigatorGeneratedFiles(ii).m);
    end

    %%% embed derivative and data function into the main wrapper
    fprintf('\t Embed data and derivative functions... ');
    % patch main wrapper with %#codegen
    main_deriv_filecontents = adigator_patch_derivative(AdigatorGeneratedFiles(ii).main,AdigatorGeneratedFiles(ii).name,1);
    % open file for writing the auxiliary adigator function
    wrapper = fopen(AdigatorGeneratedFiles(ii).main,'w');
    % write to file
    fwrite(wrapper,main_deriv_filecontents);
    fwrite(wrapper,sprintf('\n\n'));
    fwrite(wrapper,auxiliary_deriv_filecontents);
    % close file
    fclose(wrapper);
    
    fprintf('done.\n')
end

end

%% ---------------- PRUNE ADIGATOR_DERIVATIVE DATA ------------------%%
function structout = prune_adigator_mat(structin,funnames)
% PRUNE_ADIGATOR_MAT
% Keep only <funcName>.Gator*Data.Index* per derivative function.
% Downcast integer-valued arrays to int32/uint32 to shrink embedded consts.

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

            % Keep only Index* subfields
            keepIdx = fG(startsWith(fG, "Index"));
            if isempty(keepIdx), continue; end

            G2 = struct();
            for k = 1:numel(keepIdx)
                idxName = keepIdx{k};
                A = G.(idxName);

                % Down-cast numeric integer arrays to save memory
                if isnumeric(A) && isreal(A) && all(isfinite(A(:))) && all(abs(A(:) - round(A(:))) < 1e-12)
                    % Nonnegative? prefer uint32; otherwise int32
                    if all(A(:) >= 0)
                        A = uint32(A);
                    else
                        A = int32(A);
                    end
                end
                % Logical stays logical; other types left as-is (doubles etc.)
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