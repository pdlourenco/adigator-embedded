function c = mcGenNegative(uid)
%MCGENNEGATIVE  Random malformed fixture that must fail generation cleanly.
%
% Negative-testing generator (ADR-0007 Phase B): produces a user function
% that ADiGator must reject with a clean error while leaving the session
% hygienic (REQ-T-07). Paired with oracleHygiene, which expects the failure
% and checks the path/file-handle/global invariants. Tagged negative=true so
% it is only ever run through oracleHygiene, never the value oracles.
if nargin < 1, uid = 0; end

n = randi([2 5]);
x0 = randn(n, 1);

kind = randi(2);
switch kind
    case 1   % undefined variable on the active path
        body = {'y = sum(x) + zzUndefinedVar_mc;'};
        reason = 'undefined variable';
    case 2   % incompatible dimensions in an active operation
        m = n + randi([1 3]);
        body = {sprintf('y = x + %s;', mat2str(ones(m,1)))};
        reason = 'dimension mismatch';
end

name = sprintf('mc_neg_%d', uid);
c = mcCase('name', name, 'body', body, 'xsize', [n 1], ...
    'deriv', 'jacobian', 'x0', x0, ...
    'tags', struct('gen','negative','negative',true,'reason',reason, ...
                   'inShape',[n 1],'outShape',[n 1], ...
                   'density','dense','order',1));
end
