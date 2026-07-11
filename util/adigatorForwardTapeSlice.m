function S = adigatorForwardTapeSlice(body, InNames, OutName, VodName)
% adigatorForwardTapeSlice  Parse a generated forward derivative-file body and
% backward-slice it to the VALUE tape: the statements needed to produce
% <OutName>.f, with the derivative chain (the '.d<VodName>' field writers)
% excluded.
%
% This is the value-tape slicer used by the reverse-mode generator
% (adigatorGenRevGradFile, roadmap R4). Parsing is shared with the
% field-granular slicer (adigatorFieldSlice) through adigatorParseTape; this
% function adds the backward slice from <OutName>.f, excluding the
% '.d<VodName>' derivative chain.
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
% Copyright Pedro Lourenço and GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%            Extracted from adigatorGenRevGradFile for reuse (roadmap R7a
%            follow-up; foundation for the R7b field-slice, issue #21).
%            Parsing later split out to adigatorParseTape (R7b).
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorParseTape, adigatorFieldSlice, adigatorGenRevGradFile

% ------------------------- parse the tape ------------------------------ %
S = adigatorParseTape(body, InNames);
n = numel(S);

% --------------- backward slice from out.f, excluding .d<vod> ---------- %
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
