function tnz = cadaOverMapTargetNz(varID,Vcount,zsize)
% Returns the FOR-loop overmap derivative pattern that variable varID is about
% to be remapped into, or [] when no such remap is going to happen.
%
% Syntax: tnz = cadaOverMapTargetNz(varID,Vcount,zsize)
%
% ------------------------ Input Information ---------------------------- %
% varID:  .id of the variable the calling operation is building
% Vcount: variable-of-differentiation counter
% zsize:  .func.size of the variable being built
% ------------------------ Output Information --------------------------- %
% tnz:    nzlocs of the overmap varID will be remapped into, or [] if none
%
% ----------------------------------------------------------------------- %
% Why this exists (#217).
%
% A rolled FOR loop is processed twice. The OVERMAP run walks the body once per
% iteration with the EXACT per-iteration derivative patterns and unions them
% (cadaOverMap -> cadaUnionVars, which unions exact locations). The PRINTING run
% walks the body ONCE, and every loop-body operand carries its overmap rather
% than its per-iteration pattern - it has to, since one printed body serves all
% iterations. An operation in the printing run therefore composes two unions as
% if they were independent, which loses any correlation between them and can
% yield a pattern far larger than the union of the per-iteration results.
%
% The measured case: sum_k exp(x(k)) written as a subscripted loop. Per
% iteration the second derivative of exp(x(k)) has ONE nonzero, at (k,k); the
% union over the loop is the n-nonzero diagonal, which is what the tool exports.
% But in the printing run both operands of the product rule are n-wide overmaps,
% so `times` produces the full n-by-n cross product - and the generated code
% gathers n^2 doubles onto the stack to hold it. cadaOverMap/cadaPrintReMap then
% squeeze it straight back down to the n-entry diagonal, one statement later.
% 37.5 KB of stack at n=64 for an answer that is n numbers.
%
% Handing the target overmap to the emitting operation lets it drop the doomed
% locations BEFORE it prints them. The truncation is not new: it is exactly the
% one cadaPrintReMap performs a statement later, which is why this returns []
% unless that remap is actually going to happen (same OverLoc/SubsFlag test as
% cadaOverMap's printing branch, plus a size match so the caller never has to
% reason about cadaPrintReMap's changing-size xref/oref mapping). A caller that
% prunes on a non-empty answer can only ever remove locations the tool was
% already about to discard.
%
% Correctness rests on the overmap being the union of the per-iteration
% patterns: a location outside it is one the overmap run found zero in EVERY
% iteration, so it is structurally zero, not merely small. Note the operands
% themselves are safe to compose this way at run time because their overmap
% slots that are not live in the current iteration hold zero - that is what the
% per-iteration re-zeroing of the derivative temporaries buys.
%
% Copyright Pedro Lourenço and GMV.  2026-07  (#217)
% Distributed under the GNU General Public License version 3.0
%
% see also cadaOverMap, cadaPrintReMap, cadaUnionVars, cadaRepDers

global ADIGATOR ADIGATORVARIABLESTORAGE
tnz = [];

% Printing run of a FOR loop only - the overmap does not exist yet during the
% overmap run, and outside a loop there is nothing to remap into.
if ADIGATOR.RUNFLAG ~= 2 || ADIGATOR.EMPTYFLAG || ~ADIGATOR.FORINFO.FLAG
  return
end
if isempty(ADIGATOR.VARINFO.OVERMAP.FOR) || isempty(varID) || varID < 1 || ...
    varID > size(ADIGATOR.VARINFO.OVERMAP.FOR,1) || ...
    varID > size(ADIGATOR.VARINFO.NAMELOCS,1)
  return
end

% Same two conditions cadaOverMap's printing branch uses to decide whether it
% will call cadaPrintReMap at all. If it will not, nothing gets discarded and
% the caller must keep its full pattern.
OverLoc = ADIGATOR.VARINFO.OVERMAP.FOR(varID,1);
if ~OverLoc || ~ADIGATOR.VARINFO.NAMELOCS(varID,3)
  return
end
xOver = ADIGATORVARIABLESTORAGE.OVERMAP{OverLoc};
if ~isa(xOver,'cada')
  return
end

% Sizes must agree. When they do not, cadaPrintReMap maps locations through
% xref/oref before comparing them, so the raw nzlocs of the overmap are not
% directly comparable with the caller's - decline rather than guess.
if ~isequal(xOver.func.size(:).',zsize(:).')
  return
end

tnz = xOver.deriv(Vcount).nzlocs;
end
