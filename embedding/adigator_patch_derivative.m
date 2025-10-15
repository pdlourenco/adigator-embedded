function txt = adigator_patch_derivative(deriv_filepath, deriv_filename, subfun_list,apply_codegen_only)
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

txt  = fileread(deriv_filepath);
orig = txt;

% ------------------------------------------------------------------------
% 1) Insert %#codegen on the *next* line after all function headers
% ------------------------------------------------------------------------
funcLineExpr = "(?m)^(?<hdr>\s*function[^\n\r]*)$";
m = regexp(txt, funcLineExpr, 'names', 'once');
if ~isempty(m)
    hdr = m.hdr;
    if ~contains(txt, "%#codegen")
        newHdr = sprintf('%s\n%%#codegen\n', hdr);
        txt = regexprep(txt, funcLineExpr, escapeReplacement(newHdr), 'once');
    end
end

if apply_codegen_only; return; end

% ------------------------------------------------------------------------
% 2) Remove the "if isempty(...); ADiGator_LoadData(); end" block entirely
% ------------------------------------------------------------------------
% TODO THIS IS NOT WORKING
globalName = "ADiGator_" + deriv_filename;
% Match the whole line, allowing spaces, optional semicolons, and an optional trailing comment
pat = "^\s*if\s+isempty\(\s*" + regexptranslate("escape", globalName) + "\s*\)\s*;?\s*ADiGator_LoadData\(\)\s*;?\s*end\s*(?:%.*)?\s*$";
ws = "[\s\xA0]*";  % \xA0 covers non-breaking space
pat = "^" + ws + "if" + ws + "isempty\(" + ws + regexptranslate("escape", globalName) + ws + "\)" + ws + ";?" + ws + ...
      "AdiGator_LoadData(?:\(" + ws + "\))?" + ws + ";?" + ws + "end" + ws + "(?:%.*)?$";
% Remove all such lines (line-by-line anchors)
txt = regexprep(txt, pat, '', 'once');


for ii = 1:numel(subfun_list) % run through the list of subfunctions
    % ------------------------------------------------------------------------
    % 2) Replace the global declaration with a persistent one.
    %    Also introduce a loading call for the correct function every time the
    %    persistent variable is declared, to fill it
    % ------------------------------------------------------------------------

    % Build a pattern to find the function
    % Pattern explanation:
    % ^\s*function\s+(?:.*?=\s*)?myfun\s*\([^)]*\)\s*\r?\n  : function line (with or without outputs)
    % (?:[ \t]*(?:%.*)?\r?\n)*                             : any number of blank/comment lines
    % \s*global\s+ABC\s*;?                                 : the global declaration line
    pat = ['(^\s*function\s+(?:.*?=\s*)?' subfun_list{ii} '\s*\([^)]*\)\s*\r?\n' ...
        '(?:[ \t]*(?:%.*)?\r?\n)*\s*global\s+ABC\s*;?)'];
    % Build the output for the new persistent variable
    globalStr = 'persistent '+globalName+';';

    % Build the loading call
    loadStr = 'if isempty(' +globalName+'); '+globalName+' = coder.load('+deriv_filename+','+subfun_list{ii}+');';

    % Replacement:
    % $1 → everything up to and including the function and comments
    rep = [globalStr '\n' loadStr];

    % Perform the replacement
    txt = regexprep(txt, pat, rep, 'lineanchors');

    %TODO: modify this to remove the function name from the structure
    % ------------------------------------------------------------------------
    % 4) Rewrite every assignment of the form:
    %      GatorXData = ADiGator_<myfun>(.optionalMyfun).GatorXData;
    %    to:
    %      GatorXData = coder.const(ADiGator_<myfun>.GatorXData);
    % ------------------------------------------------------------------------
    % Direct from global (with or without .myfun)
    for V = gatorList.'
        directA = "(?m)^\s*(" + V + ")\s*=\s*" + regexptranslate('escape', globalName) + "\." + V + "\s*;\s*$";
        txt = regexprep(txt, directA, '$1 = coder.const(' + globalName + '.' + V + ');');

        directB = "(?m)^\s*(" + V + ")\s*=\s*" + regexptranslate('escape', globalName) + "\." + regexptranslate('escape', subfun_list{ii}) + "\." + V + "\s*;\s*$";
        txt = regexprep(txt, directB, '$1 = coder.const(' + globalName + '.' + V + ');');
    end
end

% ------------------------------------------------------------------------
% 5) Remove the ADiGator_LoadData() subfunction entirely
% ------------------------------------------------------------------------
subPat = "(?ms)^\s*function\s+ADiGator_LoadData\s*\(\s*\)\s*.*?^\s*end\s*$";
txt = regexprep(txt, subPat, '', 'once');

% ------------------------------------------------------------------------
% 6) Save back if changed
% ------------------------------------------------------------------------
if ~strcmp(txt, orig)
    fid = fopen(deriv_filepath,'w'); fwrite(fid, txt); fclose(fid);
end
end

% ================= helpers =================

function out = replace_global_line(matchStruct, globalName)
line = matchStruct.match{1};
if contains(line, "global") && contains(line, globalName)
    out = regexprep(line, '\<global\>', 'persistent');
else
    out = line; % leave unrelated global lines alone
end
end

function s = buildCoderLoad(globalName, matfile, gatorList)
% Build the compact coder.load block (single line) with only needed vars
quoted = join("'" + gatorList + "'", ', ');
if strlength(quoted) == 0
    % Fallback: no explicit varlist -> load everything (still compile-time)
    s = sprintf("if isempty(%s); %s = coder.load('%s'); end", globalName, globalName, matfile);
else
    s = sprintf("if isempty(%s); %s = coder.load('%s', %s); end", ...
                globalName, globalName, matfile, quoted);
end
end

function out = escapeReplacement(s)
out = strrep(s, '\', '\\');
out = strrep(out, '$', '\$');
end

