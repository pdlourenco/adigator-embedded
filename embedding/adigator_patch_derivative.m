function txt = adigator_patch_derivative(deriv_filepath, deriv_filename, subfun_list,apply_codegen_only,data_functions)
%PATCH_ADIGATOR_FILE    Patch an ADiGator-generated function for Embedded Coder
%                       assuming a coder.load option
%
% Assumptions:
% - The MAT file at MATFILE contains only top-level variables named Gator*Data
%   (e.g., Gator1Data, Gator2Data, ...), each with Index* fields inside.
% - The generated .m uses: global ADiGator_<myfun>; if isempty(...); ADiGator_LoadData(); end
% - We want:
%     * %#codegen on the line after the function header
%     * global ADiGator_<myfun>  ->  persistent ADiGator_<myfun>
%     * if isempty(...); ADiGator_LoadData(); end
%           -> if isempty(...); ADiGator_<myfun> = coder.load('<mat>','Gator1Data',...); end
%     * GatorXData = ADiGator_<myfun>(.optionalMyfun).GatorXData;
%           -> GatorXData = coder.const(ADiGator_<myfun>.GatorXData);
%     * Remove the ADiGator_LoadData() subfunction entirely.
%
%   Copyright GMV.
%   2025-10  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%
%   Changelog:
%

if nargin<5 % codeload option selected
    data_functions = {};
end

txt = readlines(deriv_filepath);
orig = txt;

% ------------------------------------------------------------------------
% 1) Remove the ADiGator_LoadData() subfunction entirely
% ------------------------------------------------------------------------
patterns = {'function ADiGator_LoadData()'};
idx = find_in_file(txt,patterns,1,1,[]);
if ~isempty(idx); txt(idx:end) = []; end

% ------------------------------------------------------------------------
% 2) Remove the "if isempty(...); ADiGator_LoadData(); end" block entirely
% ------------------------------------------------------------------------
patterns = {'if isempty', deriv_filename, 'ADiGator_LoadData();'};
idx = find_in_file(txt,patterns,1,0,[]);
inc = 0;
for ii=1:length(idx)
    txt(idx+inc) = [];
    inc = inc - 1;
end

% create global variable name
globalName = ['ADiGator_',deriv_filename];

for fun = 1:length(subfun_list)
    % ------------------------------------------------------------------------
    % 3) Insert %#codegen on the *next* line after all function headers
    % ------------------------------------------------------------------------
    patterns = {'function',subfun_list{fun}};
    fidx = find_in_file(txt,patterns,1,0,'%');
    txt = [txt(1:(fidx));
        "%#codegen";
        txt((fidx+1):end)];
    if apply_codegen_only; break; end

    % ------------------------------------------------------------------------
    % 4) Replace the global declaration with a call to the function that fills
    %    the required data without any loading (not even at compile time)
    %    INLINE OPTION (no extra .mat files)
    % ------------------------------------------------------------------------
    % ------------------------------------------------------------------------
    % 4) Replace the global declaration with a persistent one.
    %    Also introduce a loading call for the correct function every time the
    %    persistent variable is declared, to fill it
    %    CODERLOAD OPTION (load at compile time)
    % ------------------------------------------------------------------------
    % find the global variable declaration
    patterns = {'global', globalName};
    gidx = find_in_file(txt,patterns,fidx,1,[]);
    if ~isempty(data_functions) % inline option
        txt(gidx) = []; % remove the declaration
        gidx = gidx-1;
        loading_call = globalName+" = coder.const("+data_functions{fun}+"());";
    else % coderload option
        % ------------------------------------------------------------------------
        % 4) Replace the global declaration with a persistent one.
        %    Also introduce a loading call for the correct function every time the
        %    persistent variable is declared, to fill it
        % ------------------------------------------------------------------------
        txt(gidx) = strrep(txt(gidx),'global','persistent'); % declare persistent
        % add the loading call
        loading_call = "if isempty(" +globalName+"); "+globalName+" = coder.load('"+deriv_filename+".mat','"+subfun_list{fun}+"'); end";
    end
    txt = [txt(1:(gidx));
           loading_call;
           txt((gidx+1):end)];


    % ------------------------------------------------------------------------
    % 5) Rewrite every assignment of the form:
    %      GatorXData = ADiGator_<myfun>.function_name.GatorXData;
    %    to:
    %      GatorXData = coder.const(ADiGator_<myfun>.function_name.GatorXData);
    % ------------------------------------------------------------------------
    patterns = {'Gator','Data',globalName,subfun_list{fun}};
    gdidx = find_in_file(txt,patterns,fidx,2,[]);
    for ii=1:length(gdidx)
        % add constant
        txt(gdidx) = strrep(txt(gdidx),'Data = ADiGator','Data = coder.const(ADiGator');
        txt(gdidx) = strrep(txt(gdidx),'Data;','Data);');
        if ~isempty(data_functions)
            % remove the unnecessary field
            txt(gdidx) = strrep(txt(gdidx),['.',subfun_list{fun},'.'],'.');
        end
    end
end

% ------------------------------------------------------------------------
% 6) Save back if changed
% ------------------------------------------------------------------------
if length(txt)~=length(orig) || ~all(strcmp(txt, orig))
    writelines(txt, deriv_filepath);
end
end

% ================= helpers =================
% find all the elements in a string array that contain all the patterns
function idx = find_in_file(txt,patterns,start,once,avoid_start)
idx = [];
for line = start:length(txt)
    pat_find = false(size(patterns));
    if ~isempty(avoid_start)
        avoid = ~(~isempty(txt{line}) && (txt{line}(1) ~= avoid_start));
    else
        avoid = false;
    end
    if ~avoid
        for pat = 1:length(patterns)
            pat_find(pat) = contains(txt(line),patterns{pat});
            if ~pat_find(pat)
                break;
            end
        end
    end
    if all(pat_find)
        if isempty(idx)
            last_idx = line;
        else
            last_idx = idx(end);
        end
        idx = [idx line]; %#ok<AGROW>
        if once == 1; return; end % only one instance
        if once > 1 % more than one instance
            if line-last_idx > 2
                idx(end) = [];
                return;
            end
        end
    end
end
end
