function out = mcEval(wrapper, nout, x)
%MCEVAL  Evaluate a generated wrapper in the current folder.
%
%   out = mcEval(wrapper, nout, x) clears any cached definition (function and,
%   for classic mode, its constant-data global), rehashes, and calls
%   [out{1:nout}] = wrapper(x), returning the outputs as a cell.
%
% Classic-mode wrappers cache their constant index/data in a global on first
% call (`global ADiGator_<name>_ADiGator<Kind>`); clearing it forces a fresh
% load from the current folder's .mat, so evaluating the same-named wrapper in
% a different folder (the cross-mode 'c' baseline) cannot reuse another
% folder's data. Mirrors IEmbedModesTest's explicit global clear. Coderload /
% inline wrappers keep their data in a persistent, which clear(wrapper) drops.
clear(wrapper);
clearClassicGlobal(wrapper);
rehash;
out = cell(1, nout);
[out{1:nout}] = feval(wrapper, x);
end

function clearClassicGlobal(wrapper)
kinds = {'Jac','Grd','Hes'};
for i = 1:numel(kinds)
    suff = ['_' kinds{i}];
    if endsWith(wrapper, suff)
        base = wrapper(1:end-numel(suff));
        clear('global', ['ADiGator_' base '_ADiGator' kinds{i}]);
        return;
    end
end
end
