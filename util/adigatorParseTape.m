function S = adigatorParseTape(body, InNames)
% adigatorParseTape  Parse a generated forward derivative-file body into a
% statement-struct array with dependency sets - the shared front end of the
% forward-tape slicers (the value-tape slice in adigatorForwardTapeSlice, the
% field-granular slice in adigatorFieldSlice; roadmap R4 / R7b, issue #21).
%
% ------------------------------ Inputs --------------------------------- %
%   body    - string array (or cellstr) of the generated function-body lines
%             (the lines between the "Start Derivative Computations" marker
%             and the trailing "function ADiGator_LoadData()" / "end").
%   InNames - cellstr of the generated function's input names.
%
% ------------------------------ Output --------------------------------- %
%   S - n-by-1 struct array (text,lhs,lhsSubs,rhs,deps,active,kind,info), one
%       element per statement in original order:
%         .text    - the statement text (trimmed, with trailing ';')
%         .lhs     - assigned base name, optionally one dotted field
%                    ('y', 'y.f', 'cada1f3')
%         .lhsSubs - scatter subscript text ('1:2' from 'v(1:2)=...'), '' for
%                    a plain assignment
%         .rhs     - right-hand-side expression text (without trailing ';')
%         .deps    - cellstr of the base names this statement reads (dotted
%                    field tails stripped; a scatter also reads its own base)
%         .line    - 1-based index of the statement within `body` (so a slice
%                    can be re-emitted by dropping the corresponding lines)
%         .active/.kind/.info - left empty for a downstream classify/execute
%                    pass (adigatorGenRevGradFile's execAndClassify)
%
% Rolled control flow ('for'/'while'/'if'/'elseif'/'else'/'switch') in the
% body is rejected with adigator:fwdtape:controlflow - the dialect parsed
% here is fully unrolled (generate with adigatorOptions('unroll',1)).
% Unparseable statements raise adigator:fwdtape:parse.
%
% Copyright GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%            Split out of adigatorForwardTapeSlice so the value-tape and
%            field-granular slicers share one parser (roadmap R7b, issue #21).
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorForwardTapeSlice, adigatorFieldSlice, adigatorGenRevGradFile

body = string(body);

% ------------------------- collect statements -------------------------- %
stmts = cell(0,1);
srcline = zeros(0,1);
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
  stmts{end+1,1} = ln;       %#ok<AGROW> statement list is built line by line
  srcline(end+1,1) = Lcount; %#ok<AGROW> 1-based index of ln within body
end

% parse: lhs base name (with optional .f), scatter subscript text, rhs
n = numel(stmts);
S = struct('text',stmts,'lhs',[],'lhsSubs',[],'rhs',[],'deps',[],...
  'line',[],'active',[],'kind',[],'info',[]);
for k = 1:n
  S(k).line = srcline(k); % source line within body (for re-emission)
end
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

% ----------------------------- dependencies ---------------------------- %
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
end
