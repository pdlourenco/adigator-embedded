function txt = patch_adigator_derivative_coderload(deriv_filepath, deriv_filename,codegen_only)
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

arguments
  deriv_filepath   (1,1) string
  deriv_filename   (1,1) string
  codegen_only     (1,1) double
end

txt  = fileread(deriv_filepath);
orig = txt;

% ------------------------------------------------------------------------
% 1) Insert %#codegen on the *next* line after the function header
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
if codegen_only; return; end

% ------------------------------------------------------------------------
% 2) global -> persistent for ADiGator_<myfun>
% ------------------------------------------------------------------------
globalName = "ADiGator_" + deriv_filename;
% Build a pattern that matches ONLY the 'global' line that contains our variable
globalPatrn = '^\s*global\s+'+globalName+'+\s*;\s*$';
% Create the output;
globalStr = 'persistent '+globalName+';';
% Reconstruct the line as "persistent <rest>" preserving indentation
txt = regexprep(txt, globalPatrn, globalStr, 'lineanchors');
% clean up again for cases without ""
globalPatrn = '^\s*global\s+'+globalName+'+\s*\s*$';
% Create the output;
txt = regexprep(txt, globalPatrn, globalStr, 'lineanchors');

% ------------------------------------------------------------------------
% 3) Replace the "if isempty(...); ADiGator_LoadData(); end" block
%    with a coder.load that pulls only the needed Gator*Data vars
% ------------------------------------------------------------------------
% Accept both single-line and multi-line variants:
% if isempty(ADiGator_<myfun>); ADiGator_LoadData(); end
% if isempty(ADiGator_<myfun>)
%     ADiGator_LoadData();
% end
%  Discover which Gator*Data symbols are actually used in the file
%     and intersect with what's present in the MAT (optional but nice)
gatorList = unique(string(regexp(txt, '\<Gator[0-9A-Za-z_]*Data\>', 'match')));
% continue
patIfLoad = "(?ms)if\s+isempty\(\s*" + regexptranslate('escape', globalName) + "\s*\)\s*;?\s*ADiGator_LoadData\(\);\s*end";
if ~isempty(regexp(txt, patIfLoad, 'once'))
    coderLoad = buildCoderLoad(globalName, deriv_filename, gatorList);
    txt = regexprep(txt, patIfLoad, escapeReplacement(coderLoad), 'once');
end

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

    directB = "(?m)^\s*(" + V + ")\s*=\s*" + regexptranslate('escape', globalName) + "\." + regexptranslate('escape', deriv_filename) + "\." + V + "\s*;\s*$";
    txt = regexprep(txt, directB, '$1 = coder.const(' + globalName + '.' + V + ');');
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

