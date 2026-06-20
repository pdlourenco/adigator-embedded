function S = adigatorForwardTapeSlice(body, InNames, OutName, VodName)
% adigatorForwardTapeSlice  Parse a generated forward derivative-file body and
% backward-slice it to the VALUE tape: the statements needed to produce
% <OutName>.f, with the derivative chain (the '.d<VodName>' field writers)
% excluded.
%
% This is the parser/slicer shared by the reverse-mode generator
% (adigatorGenRevGradFile, roadmap R4) and - in a later increment - the R7b
% interprocedural field-slice (issue #21). It was extracted verbatim from
% adigatorGenRevGradFile so the parsing/slicing logic lives in one tested
% place; the only externally visible change is the error identifier prefix
% (adigator:fwdtape:* instead of adigator:revgrad:*).
%
% ------------------------------ Inputs --------------------------------- %
%   body    - string array (or cellstr) of the generated function-body lines
%             (the lines between the "Start Derivative Computations" marker
%             and the trailing "function ADiGator_LoadData()" / "end").
%   InNames - cellstr of the generated function's input names.
%   OutName - the output base name; its '.f' field is the value to keep.
%   VodName - the variable-of-differentiation name; the derivative field
%             '.d<VodName>' is excluded from the value slice.
%
% ------------------------------ Output --------------------------------- %
%   S - struct array with fields (text,lhs,lhsSubs,rhs,deps,active,kind,info)
%       of the SLICED value-tape statements in original order. active/kind/
%       info are left empty for a downstream classify/execute pass.
%
% Rolled control flow ('for'/'while'/'if'/'elseif'/'else'/'switch') in the
% body is rejected with adigator:fwdtape:controlflow - the dialect this
% slices is fully unrolled (generate with adigatorOptions('unroll',1)).
%
% Copyright GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%            Extracted from adigatorGenRevGradFile for reuse (roadmap R7a
%            follow-up; foundation for the R7b field-slice, issue #21).
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorGenRevGradFile, adigatorGenDerFile_embedded

body = string(body);

% ------------------------- collect statements -------------------------- %
stmts = cell(0,1);
for Lcount = 1:numel(body)
  ln = strtrim(char(body(Lcount)));
  if isempty(ln) || ln(1) == '%'
    continue
  end
  if strcmp(ln,'end') || strcmp(ln,'return')
    break % closing of the generated main function
  end
  if ~isempty(regexp(ln,'^(for|while|if|elseif|else|switch)\>','once'))
    error('adigator:fwdtape:controlflow',...
      ['the generated file contains rolled control flow (''%s''); ',...
      'generate with adigatorOptions(''unroll'',1) or remove loops'],ln);
  end
  stmts{end+1,1} = ln; %#ok<AGROW> statement list is built line by line
end

% parse: lhs base name (with optional .f), scatter subscript text, rhs
n = numel(stmts);
S = struct('text',stmts,'lhs',[],'lhsSubs',[],'rhs',[],'deps',[],...
  'active',[],'kind',[],'info',[]);
reserved = {'S','Gator1Data','UserFunInputs','InNames','vodLoc','VodName',...
  'OutName','stmts','reserved','FwdGator','fwddata'};
for k = 1:n
  % split at the first top-level '=' (the dialect has no '==' and no '='
  % inside subscripts); parse the LHS manually rather than with optional
  % regexp groups, whose tokens MATLAB drops when they do not participate
  ln = S(k).text;
  eq = strfind(ln,'=');
  if isempty(eq) || ln(end) ~= ';'
    error('adigator:fwdtape:parse','cannot parse generated statement: %s',ln);
  end
  lhsfull = strtrim(ln(1:eq(1)-1));
  S(k).rhs = strtrim(ln(eq(1)+1:end-1));
  par = strfind(lhsfull,'(');
  if isempty(par)
    S(k).lhs     = lhsfull;
    S(k).lhsSubs = '';
  elseif lhsfull(end) == ')'
    S(k).lhs     = strtrim(lhsfull(1:par(1)-1));
    S(k).lhsSubs = lhsfull(par(1)+1:end-1);
  else
    error('adigator:fwdtape:parse','cannot parse generated statement: %s',ln);
  end
  if isempty(regexp(S(k).lhs,'^[A-Za-z]\w*(\.\w+)?$','once')) || ...
      isempty(S(k).rhs)
    error('adigator:fwdtape:parse','cannot parse generated statement: %s',ln);
  end
  if ~isempty(regexp(ln,'\<cadaRG','once'))
    error('adigator:fwdtape:parse','reserved name cadaRG* in generated code');
  end
  if any(strcmp(strtok(S(k).lhs,'.'),reserved))
    error('adigator:fwdtape:parse',...
      'variable name ''%s'' collides with a generator-internal name',...
      strtok(S(k).lhs,'.'));
  end
end
if any(ismember(InNames,reserved))
  error('adigator:fwdtape:parse',...
    'an input name collides with a generator-internal name');
end

% --------------- dependencies and backward slice from out.f ------------ %
defined = [InNames(:); {'Gator1Data'}];
for k = 1:n
  % strip dotted tails so field names are not mistaken for variables
  depsrc = regexprep([S(k).rhs,' ',char(S(k).lhsSubs)],'\.\w+','');
  ids = regexp(depsrc,'[A-Za-z]\w*','match');
  S(k).deps = intersect(ids,defined);
  if ~isempty(S(k).lhsSubs)
    S(k).deps = union(S(k).deps,{strtok(S(k).lhs,'.')}); % scatter reads old
  end
  defined = union(defined,{strtok(S(k).lhs,'.')});
end
outStmt = find(strcmp({S.lhs},[OutName,'.f']),1,'last');
if isempty(outStmt)
  error('adigator:fwdtape:parse','could not find %s.f assignment',OutName);
end
need = false(n,1); need(outStmt) = true;
% the wanted set holds base names (dependencies are dot-stripped) plus the
% full dotted output ('y.f'); matching on the FULL lhs keeps 'y.f' and
% excludes 'y.dx'. The dotted-base fallback (for struct-field writers like
% 'r.f' matched through their base) must NEVER admit derivative fields
% ('r.dx' shares the base with 'r.f' but writes d<vod> data), or the
% forward-derivative temp chain gets sliced back in through them.
dxfield = ['.d',VodName];
wanted = union({S(outStmt).lhs},S(outStmt).deps);
for k = outStmt-1:-1:1
  if endsWith(S(k).lhs,dxfield)
    continue % derivative statement: never part of the value slice
  end
  if any(strcmp(S(k).lhs,wanted)) || ...
      (~strcmp(S(k).lhs,strtok(S(k).lhs,'.')) && ...
      any(strcmp(strtok(S(k).lhs,'.'),wanted)))
    need(k) = true;
    wanted = union(wanted,S(k).deps);
  end
end
S = S(need);
n = numel(S);
for k = 1:n
  % safety net: a leaked derivative reference would mean a silently wrong
  % gradient, so refuse loudly instead
  if ~isempty(regexp(S(k).text,['\.d',VodName,'\>'],'once'))
    error('adigator:fwdtape:parse',...
      'internal: derivative statement leaked into the value slice: %s',...
      S(k).text);
  end
end
end
