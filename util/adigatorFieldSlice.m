function [S, keep, Sall] = adigatorFieldSlice(body, InNames, demanded)
% adigatorFieldSlice  Field-granular backward slice of a generated forward
% derivative-file body: keep only the statements needed to produce a given
% set of demanded outputs, where an output may be an individual struct field
% (e.g. 'cadaoutput1.dy') so that UNread sibling fields of the same struct
% (e.g. 'cadaoutput1.dy_location' / '..._size') and the constant index tables
% they reference are dropped. This is the core of the R7b interprocedural
% field-slice (issue #21); the interprocedural driver computes the demanded
% field set per function and wires the slice into the embedded pipeline.
%
% ------------------------------ Inputs --------------------------------- %
%   body     - string array (or cellstr) of the generated function-body lines
%              (between the "Start Derivative Computations" marker and the
%              trailing "function ADiGator_LoadData()" / "end").
%   InNames  - cellstr of the generated function's input names.
%   demanded - cellstr (or string array) of demanded outputs; each entry is
%              either a base name 'v' (the whole variable is kept) or a
%              dotted field 'v.fld' (only that field of v is kept).
%
% ------------------------------ Outputs -------------------------------- %
%   S    - the SLICED statement-struct array (live statements, original
%          order; same fields as adigatorParseTape).
%   keep - logical column vector over the PARSED statements (before slicing),
%          true where the statement is live - so a caller can map the slice
%          back onto the parsed tape.
%   Sall - the full parsed statement array BEFORE slicing (keep indexes it),
%          for a downstream dependency-closure check.
%
% Correctness model. The slice is the standard monotone backward reachability
% with one refinement at struct boundaries: a field write 'v.fld = ...' is
% live only when 'v.fld' is demanded (or v is demanded whole), while a whole
% write or scatter of v is live when v - or ANY demanded field of v - is
% wanted.
%   SOUNDNESS (always holds, independent of the dialect): right-hand-side
% dependencies are taken at base-name granularity (adigatorParseTape
% dot-strips them), so the moment any kept statement reads ANY field of v,
% the whole base v enters the demand set and every 'v.*' writer becomes live.
% A statement that feeds a demanded output therefore can never be dropped; the
% only inexactness is keeping a dead statement, which the generation-time
% round-trip check (the R7b driver) reports as "no size reduction", never as a
% wrong result.
%   PRECISION (why the per-field gating actually pays off here): a generated
% output struct is only WRITTEN (assembled) in the body, never read back, so
% no internal statement re-introduces a whole-struct demand on it - which is
% what lets undemanded sibling fields ('.dy_location'/'.dy_size') and their
% index tables drop instead of being pulled back in.
%
% Rolled 'for...end' is handled conservatively AS A UNIT (via adigatorParseTape
% with allowBlocks): the whole loop is one statement that writes the union of
% the bases it assigns and reads the externally defined bases it references, so
% the slice keeps or drops the entire loop together (no per-field precision
% inside a loop, but a wholly dead loop still drops). Top-level 'while'/'if'/
% 'switch' are still rejected with adigator:fwdtape:controlflow.
%
% Copyright GMV.
%   2026-06  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%            R7b field-granular slice (issue #21).
% Distributed under the GNU General Public License version 3.0
%
% see also adigatorParseTape, adigatorForwardTapeSlice, adigatorGenDerFile_embedded

demanded = cellstr(string(demanded));
demanded = demanded(:).';

% ------------------------- parse the tape ------------------------------ %
% allowBlocks: fold a rolled 'for...end' into one atomic .block statement
Sall = adigatorParseTape(body, InNames, true);
S = Sall;
n = numel(S);

% ----------------------- seed the demand sets -------------------------- %
% wantFull: base names whose WHOLE value is demanded.
% wantField: dotted 'v.fld' field demands.
isDotted = contains(demanded,'.');
wantFull  = unique(demanded(~isDotted));
wantField = unique(demanded(isDotted));

% ------------------------- backward slice ------------------------------ %
keep = false(n,1);
for k = n:-1:1
  if S(k).block
    % a rolled loop is atomic and whole-base: it is live when ANY base it
    % assigns is demanded whole OR has any demanded field (no per-field
    % precision inside the loop)
    live = false;
    for w = reshape(S(k).writes,1,[])
      bw = w{1};
      if any(strcmp(bw,wantFull)) || any(startsWith(wantField,[bw,'.']))
        live = true; break
      end
    end
  else
    T = S(k).lhs;
    b = strtok(T,'.');
    fieldWrite = ~strcmp(T,b);              % LHS is 'b.fld'
    scatter    = ~isempty(S(k).lhsSubs);    % LHS is 'b(subs)'
    if fieldWrite && ~scatter
      % a field write satisfies only its own field demand (or a whole demand)
      live = any(strcmp(T,wantField)) || any(strcmp(b,wantFull));
    else
      % a whole write or scatter of b satisfies a whole demand on b OR any
      % field demand whose base is b
      live = any(strcmp(b,wantFull)) || any(startsWith(wantField,[b,'.']));
    end
  end
  if live
    keep(k) = true;
    if ~isempty(S(k).deps)
      wantFull = union(wantFull,S(k).deps); % RHS bases demanded (conservative)
    end
  end
end

S = Sall(keep);
end
