function cfg = adigatorCoderConfig(varargin)
%ADIGATORCODERCONFIG  The recommended strict Embedded Coder (ERT) codegen config.
%
% The single definition of the strict Embedded Coder configuration every
% ADiGator codegen site uses to build an embedded ('l'/'i') derivative. Kept in
% one place so the "strict everywhere" policy (issue #80) cannot drift across
% the sites that consume it — tests/system/SCodegenTest, SRolledErtCodegenTest,
% the Monte-Carlo tests/montecarlo/oracles/oracleCodegenEquivalence, and
% bench/derivShowcaseC — and so an end user embedding a generated derivative can
% ask for the same blessed config.
%
%   cfg = adigatorCoderConfig()                       % strict ERT lib, compiles
%   cfg = adigatorCoderConfig('GenCodeOnly', true)    % emit C only, no C compiler
%
% Strictness, and why it matters (issue #80): plain `coder.config('lib')`
% tolerates code patterns the stricter Embedded Coder target
% (`coder.config('lib','ecoder',true)`) rejects — so the laxer target was
% masking real embedded-codegen gaps. This config:
%   - targets **Embedded Coder (ERT)** — the strict target embedded MCUs use;
%   - **forbids dynamic memory allocation** (`EnableDynamicMemoryAllocation =
%     false`) — no `malloc` on the target; an unbounded-`coder.varsize`
%     derivative then fails codegen as a **test failure** rather than shipping.
%
% Necessary, not sufficient: `EnableDynamicMemoryAllocation=false` rejects
% *unbounded* varsize, but a *bounded-but-large* derivative still code-generates
% and is still not embeddable (the Gap-B "hollow milestone": ERT-clean yet
% O(n^2) stack — 16.9 KB at n=64). Catching that needs a **stack ceiling**, a
% separate gate on top of this config (issue #80a).
%
% `GenCodeOnly=true` emits C without invoking a C compiler — for sites (e.g.
% SRolledErtCodegenTest) that assert ERT *acceptance* without needing a toolchain.

p = inputParser;
p.FunctionName = 'adigatorCoderConfig';
p.addParameter('GenCodeOnly', false, @(x) islogical(x) && isscalar(x));
p.parse(varargin{:});

cfg = coder.config('lib', 'ecoder', true);    % strict Embedded Coder (ERT) target
cfg.EnableDynamicMemoryAllocation = false;     % no malloc — embedded-target safe (#80)
cfg.GenerateReport = false;                    % no HTML report under batch/CI
cfg.GenCodeOnly = p.Results.GenCodeOnly;       % skip the C-compiler step when set
end
