classdef IConcatLoopLiteralTest < matlab.unittest.TestCase
    % IConcatLoopLiteralTest  Numeric literal in a vertcat inside a rolled-loop
    % print context (B28, docs/ANALYSIS.md Sec 1.3f; issue #168).
    %
    % A vertical concatenation that contains a numeric literal, e.g.
    % `T = [1; x; x^2]`, emitted while the printer is in a ROLLED-LOOP context
    % (an `unroll=0` `for`, or a subfunction printed as a loop because it is
    % called from >=2 sites) used to print the literal as a bare `.f`:
    %
    %     T.f = [.f; x.f; cada1f1];      % B28 (wrong) - fails to run
    %     T.f = [1;  x.f; cada1f1];      % correct
    %
    % Root cause: `@cada/vertcat.m`'s loop-print path (`ForVertcat`) remapped a
    % `Num2Overloaded` literal (valid name, but `id=[]`) through `cadaPrintReMap`,
    % whose id-less rescue misfired for `[]` (`~[]` is an empty logical), so
    % `cadafuncname([])` returned the spurious `'.f'`. `@cada/horzcat.m` never
    % had the bug - it skips the remap for numerics via an `else` that vertcat
    % lacked (a latent upstream asymmetry). The fix ports that `else` into
    % vertcat, repairs the `cadaPrintReMap` rescue, and makes `cadafuncname`
    % fail loud on an empty id (never silently derive `'.f'`).
    %
    % The generated file must (a) carry no spurious `[.f` in the concat and
    % (b) run and match a finite-difference gradient. The gate is the rolled-loop
    % print context, NOT whether the concat folds - foldedConstRolledLoop pins
    % exactly that (it fully folds yet reproduced pre-fix). horzcatControl guards
    % the sibling that was always correct, so a future change can't quietly break
    % the asymmetry the fix relies on.
    %
    % Note: evaluating 'i' (inline) output in MATLAB may need the coder.*
    % namespace; without it the numeric run is skipped via assumption while the
    % generation + no-spurious-`.f` text assertion always runs.
    %
    % Coverage note: the second B28 trigger the report names - a subfunction
    % printed as a loop (`FunAsLoopFlag`, when called from >=2 sites) - is not
    % pinned separately. FunAsLoop merely sets the rolled-loop print context, so
    % the subfunction's inner `vertcat` reaches the SAME `@cada/vertcat.m`
    % `ForVertcat` remap sites that minimalRolledLoopVertcat already exercises
    % via an explicit `for`; a subfunction fixture that reliably enters that
    % context (rather than being inlined/straight-line printed) proved brittle to
    % construct, and one that doesn't enter it would be coverage theater.

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            testDir = fileparts(mfilename('fullpath'));
            root = fileparts(fileparts(testDir));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib')));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            tc.applyFixture(PathFixture(fullfile(root,'util')));
            tc.applyFixture(PathFixture(fullfile(root,'embedding')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function minimalRolledLoopVertcat(tc)
            % F2 - the minimal repro: a bare unroll=0 `for` with [1; x; x^2].
            % No struct, no subfunction, no .mat needed.
            checkClean(tc, 'f168_loop', { ...
                'y = 0;', ...
                'for k = 1:3', ...
                '  T = [1; x; x^2];', ...
                '  y = y + T.''*T;', ...
                'end'});
        end

        function foldedConstRolledLoopVertcat(tc)
            % F3 - the discriminator: the concat FULLY folds (s has a known
            % value) yet the bug still fired pre-fix, proving the gate is the
            % rolled-loop context, not the fold state.
            checkClean(tc, 'f168_f3', { ...
                'p.c.a = 2.5;', ...
                'y = 0;', ...
                'for k = 1:3', ...
                '  s = p.c.a;', ...
                '  T = [1; s; s^2];', ...
                '  y = y + x*(T.''*T);', ...
                'end'});
        end

        function midListLiteralRolledLoop(tc)
            % Literal NOT in first position: `[x; 1; x^2]` puts the `1` mid-list,
            % so a regression would emit `[x.f;.f;cada1f1]` - a `.f` after a `;`,
            % which the first-position-only text check would miss. Broadens the
            % numeric pin and exercises the mid-list regex.
            checkClean(tc, 'f168_mid', { ...
                'y = 0;', ...
                'for k = 1:3', ...
                '  T = [x; 1; x^2];', ...
                '  y = y + T.''*T;', ...
                'end'});
        end

        function horzcatControlStaysClean(tc)
            % Control - the identical rolled loop with a HORIZONTAL concat was
            % always correct (horzcat has the else vertcat lacked). Guard it so
            % the asymmetry can't silently regress, and confirm vert/horz agree.
            gV = checkClean(tc, 'f168_vv', { ...
                'y = 0;', ...
                'for k = 1:3', ...
                '  T = [1; x; x^2];', ...
                '  y = y + T.''*T;', ...
                'end'});
            gH = checkClean(tc, 'f168_hh', { ...
                'y = 0;', ...
                'for k = 1:3', ...
                '  T = [1, x, x^2];', ...
                '  y = y + T*T.'';', ...
                'end'});
            % checkClean returns a real gradient or aborts the method via
            % assumption (coder.* absent), so both are defined if we reach here.
            tc.verifyEqual(gV, gH, 'AbsTol', 1e-12, ...
                'vertcat and horzcat forms of the same cost must agree');
        end
    end
end

% ---- helpers ----

function grad = checkClean(tc, name, bodyLines)
% Write function y = name(x), generate the embed-'i' gradient, assert the
% generated file has no spurious `[.f`, and (when runnable) return its gradient
% checked against central finite differences. Aborts the method via assumption
% (no return) if the numeric run needs the coder.* namespace.
writeFixture(name, bodyLines);
ax = adigatorCreateDerivInput([1 1],'x');
adigatorGenDerFile_embedded('gradient', name, {ax}, ...
    struct('embed_mode','i','echo',0,'overwrite',1,'unroll',0));
rehash;

body = fileread([name '_Grd.m']);
% A spurious literal-`.f` appears after the opening bracket OR after any element
% separator (`;` / `,`), so catch mid-list literals too - not only `[.f`.
tc.verifyEmpty(regexp(body, '[\[;,]\s*\.f', 'once'), ...
    sprintf('%s: concat prints a numeric literal as a spurious `.f` (B28)', name));

xv = 0.7;
try
    g = feval([name '_Grd'], xv);
catch e
    if strcmp(e.identifier,'MATLAB:UndefinedFunction') && contains(e.message,'coder.')
        tc.assumeFail(['inline mode needs the coder.* namespace to run; ', ...
            'the no-spurious-`.f` text assertion already ran: ', e.message]);
    end
    rethrow(e);
end
gfd = fdgrad(str2func(name), xv);
tc.verifyEqual(g, gfd, 'RelTol', 1e-6, 'AbsTol', 1e-6, ...
    sprintf('%s: generated gradient must match finite differences', name));
grad = g;
end

function writeFixture(name, bodyLines)
fid = fopen([name '.m'],'w');
assert(fid > 0, 'could not create fixture %s', name);
fprintf(fid, 'function y = %s(x)\n', name);
fprintf(fid, '%s\n', bodyLines{:});
fprintf(fid, 'end\n');
fclose(fid);
rehash;
end

function g = fdgrad(f, x)
% central finite-difference gradient of a scalar-in/scalar-out function
h = 1e-6;
g = (f(x+h) - f(x-h)) / (2*h);
end
