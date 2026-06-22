function result = prune_shrink_offline_checks()
%PRUNE_SHRINK_OFFLINE_CHECKS  License-free core for the slice-before-prune data
% half (issue #21, ADR-0010). Exercises the REAL embedding/adigatorReferencedIndex
% and embedding/prune_adigator_mat (both char/cellstr + regexp, so they run in
% base MATLAB and GNU Octave alike) on hand-written generated-derivative
% snippets and on the committed slim1 fixture. Errors on any mismatch, so it
% fails a bare Octave run and the matlab.unittest wrapper (IPruneShrinkTest)
% alike. See ADR-0008 for the offline-core / matlab.unittest-wrapper split.
%
% Usage (license-free, from the repo root):
%   octave --quiet --eval "addpath(fullfile(pwd,'tests','offline')); prune_shrink_offline_checks"

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
addpath(fullfile(root, 'embedding'));

n = 0;

%% ---- adigatorReferencedIndex: per-function token mapping ---------------
deriv = { ...
    'function f = myfun_ADiGatorGrd(z)'
    '%#codegen'
    'ADiGator_x = coder.const(data_myfun_ADiGatorGrd());'
    'Gator1Data = coder.const(ADiGator_x.Gator1Data);'
    'cada1td1 = zeros(2,2);'
    'cada1td1(Gator1Data.Index1) = z.dz;'
    'cada1f1dz = cada1td1(Gator1Data.Index2);'
    'f.dz = cada1f1dz;'
    'end'
    'function y = ADiGator_sub(z)'
    '%#codegen'
    'Gator1Data = coder.const(ADiGator_x.Gator1Data);'
    'y.dz = z.dz;'
    'end' };
ref = adigatorReferencedIndex(deriv, {'myfun_ADiGatorGrd','ADiGator_sub'});
n = check(n, isfield(ref,'myfun_ADiGatorGrd'), 'main function mapped');
n = check(n, ismem('Gator1Data.Index1', ref.myfun_ADiGatorGrd.index), 'main keeps Index1');
n = check(n, ismem('Gator1Data.Index2', ref.myfun_ADiGatorGrd.index), 'main keeps Index2');
n = check(n, numel(ref.myfun_ADiGatorGrd.index) == 2, 'main references exactly 2');
n = check(n, ismem('Gator1Data', ref.myfun_ADiGatorGrd.table), 'main references the table');
n = check(n, isfield(ref,'ADiGator_sub'), 'subfunction mapped');
n = check(n, isempty(ref.ADiGator_sub.index), 'subfunction references no index');
n = check(n, ismem('Gator1Data', ref.ADiGator_sub.table), 'subfunction references the table (boilerplate)');

%% ---- comments ignored; bracketed signature; commented header ----------
rc = adigatorReferencedIndex({ ...
    'function f = m(z)'
    'Gator1Data = coder.const(d.Gator1Data);'
    'a = z(Gator1Data.Index1);  % trailing Gator1Data.Index9'
    '%User Line: dead Gator1Data.Index8'
    'f.dz = a;'
    'end' }, {'m'});
n = check(n, ismem('Gator1Data.Index1', rc.m.index), 'comment: keeps real Index1');
n = check(n, ~ismem('Gator1Data.Index9', rc.m.index), 'comment: ignores trailing-comment Index9');
n = check(n, ~ismem('Gator1Data.Index8', rc.m.index), 'comment: ignores full-comment Index8');

rb = adigatorReferencedIndex({ ...
    '% function [Jac,Fun] = wrap(w,z)  -- doc header'
    'function [Jac,Fun] = wrap(w,z)'
    'Gator1Data = coder.const(d.Gator1Data);'
    'Jac = z.dz(Gator1Data.Index1);'
    'end' }, {'wrap'});
n = check(n, isfield(rb,'wrap'), 'bracketed signature + commented header: block parsed');
n = check(n, ismem('Gator1Data.Index1', rb.wrap.index), 'bracketed signature: keeps Index1');

ri = adigatorReferencedIndex({ ...
    'function f = wanted(z)'
    'Gator1Data = coder.const(d.Gator1Data);'
    'f.dz = z.dz(Gator1Data.Index1);'
    'end'
    'function y = ignored(z)'
    'Gator1Data = coder.const(d.Gator1Data);'
    'y.dz = z.dz(Gator1Data.Index5);'
    'end' }, {'wanted'});
n = check(n, isfield(ri,'wanted'), 'function in list mapped');
n = check(n, ~isfield(ri,'ignored'), 'function not in list ignored');

%% ---- unsafe -> keep-all (function dropped from the map) ----------------
ru = adigatorReferencedIndex({ ...
    'function f = bad(z)'
    'Gator1Data = coder.const(d.Gator1Data);'
    'x = Gator1Data.(fld);'
    'f.dz = x;'
    'end' }, {'bad'});
n = check(n, ~isfield(ru,'bad'), 'dynamic field -> keep-all');
ra = adigatorReferencedIndex({ ...
    'function f = bad2(z)'
    'Gator1Data = coder.const(d.Gator1Data);'
    'g = Gator1Data;'
    'f.dz = z.dz(g.Index1);'
    'end' }, {'bad2'});
n = check(n, ~isfield(ra,'bad2'), 'aliased bare table -> keep-all');

% defensive: a chained parent.Gator<d>Data.Index<n> (not in today's dialect)
% still records its index, so it can never be under-kept
rch = adigatorReferencedIndex({ ...
    'function f = chain(z)'
    'f.dz = z.dz(ADiGator_x.Gator1Data.Index3);'
    'end' }, {'chain'});
n = check(n, ismem('Gator1Data.Index3', rch.chain.index), 'chained parent.table.index recorded (no under-keep)');

%% ---- prune_adigator_mat with the referenced map -----------------------
% dead index drops, live index kept, still down-cast
s = struct(); s.myfun.Gator1Data.Index1 = [1 2 3]; s.myfun.Gator1Data.Index2 = [4 5];
mref = struct(); mref.myfun.index = {'Gator1Data.Index1'}; mref.myfun.table = {'Gator1Data'};
out = prune_adigator_mat(s, {'myfun'}, mref);
n = check(n, isfield(out.myfun.Gator1Data,'Index1'), 'prune keeps referenced Index1');
n = check(n, ~isfield(out.myfun.Gator1Data,'Index2'), 'prune drops unreferenced Index2');
n = check(n, isa(out.myfun.Gator1Data.Index1,'uint32'), 'prune still down-casts');

% unshrunk fallback: referenced table, no referenced index -> keep unshrunk
s = struct(); s.myfun.Gator1Data.Index1 = [1 2];
mref = struct(); mref.myfun.index = {}; mref.myfun.table = {'Gator1Data'};
out = prune_adigator_mat(s, {'myfun'}, mref);
n = check(n, isfield(out.myfun,'Gator1Data'), 'fallback keeps referenced table');
n = check(n, isfield(out.myfun.Gator1Data,'Index1'), 'fallback is unshrunk (no zero-field struct)');

% wholly-unreferenced table dropped
s = struct(); s.myfun.Gator1Data.Index1 = [1 2];
mref = struct(); mref.myfun.index = {}; mref.myfun.table = {};
out = prune_adigator_mat(s, {'myfun'}, mref);
n = check(n, ~isfield(out.myfun,'Gator1Data'), 'unreferenced table dropped');

% Data* untouched by the map
s = struct(); s.myfun.Gator1Data.Index1 = [1 2]; s.myfun.Gator1Data.Data1 = [2 0;0 2];
mref = struct(); mref.myfun.index = {}; mref.myfun.table = {'Gator1Data'};
out = prune_adigator_mat(s, {'myfun'}, mref);
n = check(n, isfield(out.myfun.Gator1Data,'Data1'), 'Data1 kept (non-empty rule)');
n = check(n, isa(out.myfun.Gator1Data.Data1,'double'), 'Data1 stays double');

% absent function / empty map == 2-arg keep-all
s = struct(); s.myfun.Gator1Data.Index1 = [1 2]; s.myfun.Gator1Data.Index2 = [3 4];
out3 = prune_adigator_mat(s, {'myfun'}, struct());
out2 = prune_adigator_mat(s, {'myfun'});
n = check(n, isequal(out3,out2), 'empty map == 2-arg behaviour');
n = check(n, isfield(out3.myfun.Gator1Data,'Index2'), 'empty map keeps all Index*');

%% ---- end-to-end on the committed slim1 fixture ------------------------
fixLines = strsplit(fileread(fullfile(root,'tests','fixtures','gen_dialect','slim1','gapfun_Grd.m')), sprintf('\n'));
funcs = {'gapfun_ADiGatorGrd','ADiGator_conefun','ADiGator_setfun'};
fref = adigatorReferencedIndex(fixLines(:), funcs);
n = check(n, ~ismem('Gator1Data.Index7', fref.gapfun_ADiGatorGrd.index), 'fixture: gapfun does NOT reference the orphan Index7');
n = check(n, numel(fref.gapfun_ADiGatorGrd.index) == 6, 'fixture: gapfun references exactly Index1..6');
n = check(n, numel(fref.ADiGator_conefun.index) == 2, 'fixture: conefun references Index1,2');
n = check(n, isempty(fref.ADiGator_setfun.index), 'fixture: setfun references no index');

% prune a struct matching the real pre-prune .mat layout
S = struct();
for i = 1:7, S.gapfun_ADiGatorGrd.Gator1Data.(sprintf('Index%d',i)) = [1 2]; end
for i = 1:2, S.ADiGator_conefun.Gator1Data.(sprintf('Index%d',i)) = [1 4]; end
S.ADiGator_setfun.Gator1Data.Index1 = zeros(0,0,'uint32');
P = prune_adigator_mat(S, funcs, fref);
n = check(n, ~isfield(P.gapfun_ADiGatorGrd.Gator1Data,'Index7'), 'fixture prune: Index7 dropped');
n = check(n, numel(fieldnames(P.gapfun_ADiGatorGrd.Gator1Data)) == 6, 'fixture prune: gapfun keeps 6 indices');
n = check(n, isfield(P.ADiGator_setfun,'Gator1Data'), 'fixture prune: setfun table kept (fallback)');
n = check(n, isfield(P.ADiGator_setfun.Gator1Data,'Index1'), 'fixture prune: setfun unshrunk (no zero-field struct)');

result = struct('checks', n);
fprintf('prune_shrink_offline_checks: PASS  (%d checks)\n', n);
end

% ----------------------------------------------------------------------- %
function n = check(n, cond, msg)
n = n + 1;
if ~cond
    error('prune_shrink_offline_checks:fail', 'check %d FAILED: %s', n, msg);
end
end

% ----------------------------------------------------------------------- %
function tf = ismem(needle, hay)
% membership that tolerates [] / {} / cellstr in both engines
tf = ~isempty(hay) && any(strcmp(needle, hay));
end
