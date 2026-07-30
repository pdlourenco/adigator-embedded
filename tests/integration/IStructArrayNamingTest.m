classdef IStructArrayNamingTest < matlab.unittest.TestCase
    % IStructArrayNamingTest  B29/B30/B31/B33 regression: the @cadastruct
    % fallback-naming branch.
    %
    % The @cadastruct struct-array overloads name their result from
    % ADIGATOR.VARINFO.NAMELOCS(y.id,1): a user-named result takes the NAMES
    % entry, and an UNNAMED intermediate (a struct-array op whose result is not
    % assigned to a variable — e.g. passed straight to a function) falls to the
    % synthesized-name arm. `transpose`/`reshape`/`repmat` build that name as
    %   sprintf('cada%1.0ds%1.0f', NVAROFDIFF, NAMELOCS(y.id,2))
    % but `vertcat`, `horzcat` and `ctranspose` instead referenced `NDstr`
    % (never assigned in those functions) and `yid` (the variable in scope is
    % `y.id`), so the arm threw "Unrecognized function or variable 'NDstr'".
    % Fail-loud, never a wrong derivative — but it made a legal user program
    % un-differentiable. See docs/analyses/ANALYSIS.md §1.3g (B29-B31, B33).
    %
    % The branch IS user-reachable: in `y = hlp([s; s]')` the **`[s; s]`** concat
    % result is the unnamed intermediate, so this drives **`vertcat`**'s fallback
    % arm (reverting that fix alone re-breaks the first test below — verified).
    % The `ctranspose` result is NOT unnamed: as a function-call input it gets a
    % NAMES entry (`cadainput2_1`) and takes the named arm. So **B29 is the one
    % dynamically pinned**; B30 (ctranspose), B33 (horzcat) and B34 (subsref) are
    % pinned by the static `NDstr`-scope guard below, which does fail on the
    % pre-fix shape.

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
        function unnamedStructArrayConcatGeneratesAndIsCorrect(tc)
            % B29: in y = hlp([s; s]') the **[s; s] concat** result is the
            % unnamed intermediate, which drives vertcat's fallback naming arm.
            % (The ctranspose result is a function-call input and gets a NAMES
            % entry, so it takes the *named* arm — this fixture does not drive
            % ctranspose.) Pre-fix this threw; now it must generate, run, and
            % give the RIGHT derivative (principle 1: not merely not-throw).
            %
            % Both struct-array entries alias the same x, so
            %   y = sum(x) + sum(x) = 2*sum(x)   ->   dy/dx = [2 2 2]
            writeFcn('sa_ctrans', { ...
                'function y = sa_ctrans(s)', ...
                'y = hlp([s; s]'');', ...
                'end', ...
                'function o = hlp(t)', ...
                'o = sum(t(1).a) + sum(t(2).a);', ...
                'end'});
            s.a = adigatorCreateDerivInput([3 1],'x');
            adigatorGenJacFile('sa_ctrans', {s}, ...
                struct('overwrite',1,'echo',0), 'Grd');
            rehash;

            xv = [0.3; -1.2; 2.5];
            sv.a = xv;
            [G, F] = sa_ctrans_Grd(sv);

            tc.verifyEqual(F, 2*sum(xv), 'AbsTol', 1e-12, ...
                'function value wrong');
            tc.verifyEqual(full(G(:)), [2; 2; 2], 'AbsTol', 1e-12, ...
                'gradient of 2*sum(x) must be [2 2 2] — a wrong derivative here is worse than the old throw');

        end

        function synthesizedNameUsesDerNumberNotNvod(tc)
            % Pin the PREFIX CONVENTION. The synthesized name is cada<D>s<k>,
            % and <D> must be DERNUMBER, not NVAROFDIFF: its job is to keep
            % pass-N names out of pass-N+1's namespace when a generated file is
            % re-differentiated (Hessian). NVAROFDIFF is invariant across those
            % passes, so choosing it could alias a live pass-1 variable — a
            % silently wrong derivative replacing a loud throw (principle 1).
            %
            % This needs TWO variables of differentiation to be meaningful: at
            % nvod == DERNUMBER == 1 the two conventions emit the SAME string,
            % so a single-variable fixture cannot discriminate them (a nvod==1
            % assertion would pass under either and pin nothing). Here nvod == 2
            % and DERNUMBER == 1, so the correct prefix is 'cada1s' and the
            % NVAROFDIFF spelling would emit 'cada2s' — hence the negative
            % assertion, which is the half that actually discriminates.
            %
            % FIXTURE CONSTRAINT: the negative assertion is only valid while this
            % fixture stays clear of the three overloads still on NVAROFDIFF
            % (transpose/reshape/repmat — the deferred harmonization, ANALYSIS
            % §1.3g). A struct transpose/reshape/repmat added here would emit a
            % legitimate 'cada2s...' at nvod==2 and fail this test for the wrong
            % reason. Harmonizing those three retires the constraint.
            writeFcn('sa_nvod', { ...
                'function y = sa_nvod(s,p)', ...
                'a = hlp([s; s]'');', ...
                'b = hlp([p; p]'');', ...
                'y = a + b;', ...
                'end', ...
                'function o = hlp(t)', ...
                'o = sum(t(1).a) + sum(t(2).a);', ...
                'end'});
            s.a = adigatorCreateDerivInput([3 1],'x');
            p.a = adigatorCreateDerivInput([2 1],'z');
            adigator('sa_nvod', {s,p}, 'sa_nvod_d', ...
                adigatorOptions('overwrite',1,'echo',0));

            src = fileread('sa_nvod_d.m');
            tc.verifyNotEmpty(regexp(src, 'cada1s\d', 'once'), ...
                ['the synthesized struct name must carry the DERNUMBER prefix ' ...
                 '(cada1s...) — see @cadastruct/vertcat.m on why not NVAROFDIFF']);
            tc.verifyEmpty(regexp(src, 'cada2s\d', 'once'), ...
                ['a cada2s... name means the NVAROFDIFF spelling crept back in: ' ...
                 'with 2 variables of differentiation nvod==2 while DERNUMBER==1, ' ...
                 'and an NVAROFDIFF-based name can alias a pass-1 variable when ' ...
                 'the file is re-differentiated (principle 1)']);
        end

        function namedStructArrayOpsStillGenerate(tc)
            % B29/B33 guard: the vertcat/horzcat struct-array shapes must keep
            % generating (they take the named arm on this surface; the fix
            % aligned their fallback arm with the siblings and must not have
            % perturbed the working path).
            writeFcn('sa_cat', { ...
                'function y = sa_cat(s)', ...
                'tv = [s; s];', ...
                'th = [s, s];', ...
                'y = sum(tv(1).a) + sum(tv(2).a) + sum(th(1).a) + sum(th(2).a);', ...
                'end'});
            s.a = adigatorCreateDerivInput([3 1],'x');
            adigatorGenJacFile('sa_cat', {s}, ...
                struct('overwrite',1,'echo',0), 'Grd');
            rehash;

            xv = [0.3; -1.2; 2.5];
            sv.a = xv;
            [G, F] = sa_cat_Grd(sv);
            tc.verifyEqual(F, 4*sum(xv), 'AbsTol', 1e-12, ...
                'struct-array concat function value wrong');
            tc.verifyEqual(full(G(:)), [4; 4; 4], 'AbsTol', 1e-12, ...
                'struct-array concat gradient wrong');
        end

        function repmatEmptyFlagFieldIsSpelledCorrectly(tc)
            % B31: @cadastruct/repmat.m referenced a MISSPELLED empty-eval flag
            % field, which throws "Unrecognized field" instead of testing it.
            % Static guard over CODE lines only (a comment naming the old typo
            % must not trip this).
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            code = codeLines(fullfile(root,'lib','@cadastruct','repmat.m'));
            tc.verifyEmpty(regexp(code, 'EMTPYFLAG', 'once'), ...
                '@cadastruct/repmat.m code still misspells the empty-eval flag (B31)');
            tc.verifyNotEmpty(regexp(code, 'EMPTYFLAG', 'once'), ...
                'the empty-eval flag guard disappeared entirely');
        end

        function noCadastructUsesUndefinedNDstr(tc)
            % B29/B30/B33/B34 static guard, stated as the real invariant: no
            % @cadastruct file may USE `NDstr` in a function scope that never
            % ASSIGNS it. That is exactly the defect (the fallback-name arms in
            % vertcat/horzcat/ctranspose, and subsref's main body — whose only
            % NDstr assignment lives in the ForSubsRef subfunction).
            % Comment lines are stripped so the fix's own explanation cannot
            % trip the guard. The assignment pattern is line-anchored
            % (`^\s*NDstr\s*=`), so a legitimate MID-STATEMENT assignment
            % (`a = b; NDstr = ...`) would be missed and the guard would trip —
            % a false failure, i.e. the loud direction, which is the acceptable
            % way for a guard like this to be wrong.
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            d = [dir(fullfile(root,'lib','@cadastruct','*.m')); ...
                 dir(fullfile(root,'lib','@cadastruct','private','*.m'))];
            for k = 1:numel(d)
                f = fullfile(d(k).folder, d(k).name);
                lines = codeLinesCell(f);
                % split into function scopes; NDstr must be assigned in any
                % scope that uses it
                bounds = find(~cellfun(@isempty, regexp(lines, '^\s*function\b', 'once')));
                bounds = [bounds, numel(lines)+1]; %#ok<AGROW>
                for b = 1:numel(bounds)-1
                    scope = lines(bounds(b):bounds(b+1)-1);
                    uses    = any(~cellfun(@isempty, regexp(scope, '\<NDstr\>', 'once')));
                    assigns = any(~cellfun(@isempty, regexp(scope, '^\s*NDstr\s*=', 'once')));
                    tc.verifyFalse(uses && ~assigns, sprintf( ...
                        '%s: a function scope uses NDstr without assigning it (B29/B30/B33/B34)', ...
                        d(k).name));
                end
            end
        end
    end
end

function writeFcn(name, lines)
% write a fixture function file into the (temporary) working folder
fid = fopen([name '.m'], 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
rehash;
end

function c = codeLinesCell(file)
% File contents as a cellstr with comments stripped, so a static guard cannot
% be tripped by a comment that names the very pattern it forbids. The strip is
% naive (first '%' to end of line): a '%' inside a STRING LITERAL would also
% truncate the rest of that code line, which would make the guard PERMISSIVE
% (a missed defect), never a false failure. Verified against the current tree:
% every NDstr use in @cadastruct sits before the first '%' on its line, and
% `NDstr = sprintf('%1.0f',...)` still matches the assignment pattern after
% stripping, so no real detection is lost today.
txt = fileread(file);
c = regexp(txt, '\r\n|\n|\r', 'split');
c = regexprep(c, '%.*$', '');
end

function s = codeLines(file)
% codeLinesCell joined back into one char array.
s = strjoin(codeLinesCell(file), newline);
end
