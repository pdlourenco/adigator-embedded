function c = mcGenNegative(uid)
%MCGENNEGATIVE  Random MALFORMED fixture that must fail generation cleanly.
%
% Produces a deliberately broken scalar fixture (tags.negative = true) so the
% hygiene oracle (oracleHygiene) can assert REQ-T-07 / B16: derivative
% generation must raise an error AND leave the session hygienic -- no stray
% transformation-state globals, the MATLAB path restored, no adigator-owned
% file handles left open. NEVER feed a negative case to the value oracles;
% run it as its own campaign (see oracleHygiene / MCSmokeTest).
%
% Each variant fails at adigator's initial user-function eval (the most common
% real failure mode), which is reached after the temp dir is created/added to
% the path -- so it exercises the global + path + handle cleanup.
if nargin < 1, uid = 0; end

n  = randi([2 5]);
x0 = 0.4*randn(n, 1);

variants = {'undefinedVar', 'dimMismatch', 'badCall'};
v = variants{1 + mod(uid, numel(variants))};

switch v
    case 'undefinedVar'   % references a name that does not exist
        body = {'y = sum(x) + thisVariableDoesNotExist;'};
    case 'dimMismatch'    % column*column -> inner-dimension mismatch
        body = {'y = x*x;'};
    case 'badCall'        % calls a function that does not exist
        body = {'y = sum(adigatorNoSuchFunction42(x));'};
end

name = sprintf('mc_neg_%d', uid);
c = mcCase('name', name, 'body', body, 'xsize', [n 1], ...
    'deriv', 'jacobian', 'x0', x0, ...
    'tags', struct('gen','negative', 'negative',true, ...
                   'inShape',[n 1], 'variant',v));
end
