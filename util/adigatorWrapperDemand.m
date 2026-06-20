function [resvar, fields] = adigatorWrapperDemand(wrapperLines, dername)
% adigatorWrapperDemand  Determine which fields of a generated derivative
% function's output struct the WRAPPER actually reads - the demand seed for
% the R7b field-slice (issue #21).
%
% A generated wrapper (myfun_Jac / myfun_Hes / myfun_Grd) calls the
% _ADiGator* derivative function once, '<resvar> = <dername>(...)', and then
% reads some of the result's fields - e.g. '<resvar>.dx' and '<resvar>.f'
% always, but '<resvar>.dx_location' / '..._size' ONLY in classic mode (embed
% modes scatter through generation-time literal indices). This function
% returns exactly the fields the wrapper references, so the slice keeps them
% (and drops the rest); it is therefore mode-agnostic by construction - a
% no-op for classic wrappers, slimming for embed wrappers.
%
% ------------------------------ Inputs --------------------------------- %
%   wrapperLines - string array (or cellstr) of the wrapper file's lines.
%   dername      - name of the _ADiGator* derivative function the wrapper
%                  calls (GenFiles(derf).dername).
%
% ------------------------------ Outputs -------------------------------- %
%   resvar - the wrapper's call-result variable name ('' if the call to
%            <dername> is not found - the caller should then NOT slice).
%   fields - cellstr (row) of the distinct field names read from <resvar>
%            (e.g. {'f','dx'} or {'f','dx','dx_location'}); {} when resvar=''.
%
% Conservative by design: resvar is returned empty (so the driver leaves the
% derivative file unsliced) if the single 'X = dername(...)' call cannot be
% located unambiguously, OR if the result struct is used WHOLE anywhere (a
% bare 'X' token), since the per-field demand would then be incomplete.
%
% Copyright GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%            R7b interprocedural demand extraction (issue #21).
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorFieldSlice, adigatorParseTape, adigatorGenDerFile_embedded

wrapperLines = string(wrapperLines);
resvar = '';
fields = {};

% locate the call '<resvar> = <dername>(' (ignoring commented lines)
callpat = ['^\s*([A-Za-z]\w*)\s*=\s*',regexptranslate('escape',char(dername)),'\s*\('];
hits = cell(0,1);
callidx = zeros(0,1);
for i = 1:numel(wrapperLines)
  ln = strtrim(char(wrapperLines(i)));
  if isempty(ln) || ln(1) == '%'
    continue
  end
  tok = regexp(ln,callpat,'tokens','once');
  if ~isempty(tok)
    hits{end+1,1} = tok{1};   %#ok<AGROW> collect every call-site result name
    callidx(end+1,1) = i;     %#ok<AGROW> and its line, to skip in the bare scan
  end
end
if numel(hits) ~= 1
  return % no call, or more than one - bail (resvar stays '')
end
resvar = hits{1};

% defensive bail: if the result struct is used WHOLE anywhere (a bare
% <resvar> token not followed by '.', other than the call's own LHS), the
% demand seeded from <resvar>.<field> reads would be incomplete - so refuse
% to slice rather than under-demand. Today's generated wrappers only ever
% field-access the result, so this never fires in practice.
barepat = ['\<',regexptranslate('escape',resvar),'\>(?!\.)'];
for i = 1:numel(wrapperLines)
  if i == callidx(1)
    continue % the call's own LHS assignment, not a use
  end
  ln = strtrim(char(wrapperLines(i)));
  if isempty(ln) || ln(1) == '%'
    continue
  end
  if ~isempty(regexp(ln,barepat,'once'))
    resvar = ''; return % whole-struct use - bail (resvar/fields stay empty)
  end
end

% collect every '<resvar>.<field>' read across the wrapper
fpat = ['\<',regexptranslate('escape',resvar),'\.([A-Za-z]\w*)'];
found = {};
for i = 1:numel(wrapperLines)
  ln = char(wrapperLines(i));
  toks = regexp(ln,fpat,'tokens');
  for t = 1:numel(toks)
    found{end+1,1} = toks{t}{1}; %#ok<AGROW> field name read from the result
  end
end
fields = unique(found(:)).';
end
