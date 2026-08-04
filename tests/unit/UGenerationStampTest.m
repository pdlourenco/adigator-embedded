classdef UGenerationStampTest < matlab.unittest.TestCase
    % UGenerationStampTest  The provenance stamp carried by every generated
    % file (issue #200; CI plan TS-U-21).
    %
    % The stamp answers "from what source, with which options, when" for a
    % generated artifact found in a firmware repository, and its id is shared by
    % every file of one generation so that a mismatch across a
    % wrapper/derivative/data triplet means MIXED VINTAGES - the staleness
    % failure ANALYSIS §2.4(10) names.
    %
    % The properties below are the ones that make it usable rather than
    % decorative. Two are easy to lose in a refactor and would not show up as a
    % failure anywhere else:
    %
    %   PORTABILITY - the id must not depend on absolute paths, or two users
    %   generating from the same sources get different ids and the stamp
    %   certifies nothing about a committed file.
    %
    %   STABILITY UNDER IRRELEVANT CHANGE - line endings and trailing
    %   whitespace must not move it. The tree is LF since #212, but a
    %   contributor's editor is not a reason to invalidate a stamp.
    %
    % License-free: no Coder, no generation - these exercise the stamp helper
    % directly.
    %
    %   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
    %   Public License version 3.0.

    properties (Constant)
        Opts = struct('unroll',0,'embed_mode','i','slim_embed',1,'complex',0)
    end

    methods (TestClassSetup)
        function addPaths(tc)
            import matlab.unittest.fixtures.PathFixture
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            tc.applyFixture(PathFixture(root));
            tc.applyFixture(PathFixture(fullfile(root,'lib','cadaUtils')));
            % util/ holds adigatorNormalizeEmbedMode, which
            % adigatorReconstructCall canonicalises embed_mode with. Omitting
            % it passed locally (a startup.m had it on the path) and failed on
            % the hosted runner's clean path - the #81/#82 failure mode, and
            % the reason validation must run through ci_local rather than an
            % ad-hoc addpath.
            tc.applyFixture(PathFixture(fullfile(root,'util')));
        end
    end

    methods (TestMethodSetup)
        function workInTempFolder(tc)
            import matlab.unittest.fixtures.WorkingFolderFixture
            tc.applyFixture(WorkingFolderFixture);
        end
    end

    methods (Test)
        function sameInputsGiveTheSameId(tc)
            writeSrc('s1.m', 'y = sum(exp(x));');
            a = cadaGenerationStamp('2.0', tc.Opts, {'s1.m'});
            b = cadaGenerationStamp('2.0', tc.Opts, {'s1.m'});
            tc.verifyEqual(a.id, b.id, ...
                'the same version, options and sources must give the same id');
            tc.verifyMatches(a.id, '^[0-9a-f]{16}$', 'id must be 16 hex digits');
        end

        function changedSourceMovesTheId(tc)
            writeSrc('s2.m', 'y = sum(exp(x));');
            before = cadaGenerationStamp('2.0', tc.Opts, {'s2.m'});
            writeSrc('s2.m', 'y = sum(exp(x)) + 1;');
            after  = cadaGenerationStamp('2.0', tc.Opts, {'s2.m'});
            tc.verifyNotEqual(after.id, before.id, ...
                ['a changed source must move the id - this is the staleness ', ...
                 'check a committed derivative is worth having']);
        end

        function changedOptionsOrVersionMoveTheId(tc)
            writeSrc('s3.m', 'y = sum(exp(x));');
            base = cadaGenerationStamp('2.0', tc.Opts, {'s3.m'});
            o = tc.Opts; o.unroll = 1;
            tc.verifyNotEqual(cadaGenerationStamp('2.0', o, {'s3.m'}).id, base.id, ...
                'different emission options must give a different id');
            tc.verifyNotEqual(cadaGenerationStamp('2.1', tc.Opts, {'s3.m'}).id, base.id, ...
                'a different tool version must give a different id');
        end

        function lineEndingsAndTrailingSpaceDoNotMoveTheId(tc)
            % The stamp must not move for a reason a reader cannot see in the
            % file. Post-#212 the tree is LF, but a checkout or an editor can
            % still hand us CRLF.
            body = 'y = sum(exp(x));';
            writeSrc('lf.m', body);
            lf = cadaGenerationStamp('2.0', tc.Opts, {'lf.m'});

            crlf = strrep(fileread('lf.m'), newline, sprintf('\r\n'));
            writeBytes('crlf.m', crlf);
            tc.verifyEqual(cadaGenerationStamp('2.0', tc.Opts, {'crlf.m'}).id, lf.id, ...
                'CRLF vs LF source must not move the id');

            trail = regexprep(fileread('lf.m'), '\n', ['   ' newline]);
            writeBytes('trail.m', trail);
            tc.verifyEqual(cadaGenerationStamp('2.0', tc.Opts, {'trail.m'}).id, lf.id, ...
                'trailing whitespace must not move the id');
        end

        function theIdIsIndependentOfPathAndOrder(tc)
            % PORTABILITY. Hashing paths would make the id machine-specific,
            % and `mydepfun` does not promise a stable closure order.
            writeSrc('a.m', 'y = sum(exp(x));');
            writeSrc('b.m', 'y = sum(sin(x));');
            mkdir('sub');
            copyfile('a.m', fullfile('sub','a.m'));

            here  = cadaGenerationStamp('2.0', tc.Opts, {'a.m'});
            there = cadaGenerationStamp('2.0', tc.Opts, {fullfile('sub','a.m')});
            tc.verifyEqual(there.id, here.id, ...
                ['same content at a different path must give the same id, or ', ...
                 'two machines generating the same artifact disagree']);

            ab = cadaGenerationStamp('2.0', tc.Opts, {'a.m','b.m'});
            ba = cadaGenerationStamp('2.0', tc.Opts, {'b.m','a.m'});
            tc.verifyEqual(ba.id, ab.id, 'closure order must not move the id');
        end

        function anUnreadableSourceDoesNotThrow(tc)
            % Provenance must never be the reason a differentiation fails.
            writeSrc('ok.m', 'y = x;');
            s = cadaGenerationStamp('2.0', tc.Opts, {'ok.m','does_not_exist.m'});
            tc.verifyMatches(s.id, '^[0-9a-f]{16}$', ...
                'a missing source must degrade to a still-valid stamp');
        end

        function theTimestampIsIso8601Utc(tc)
            s = cadaGenerationStamp('2.0', tc.Opts, {});
            tc.verifyMatches(s.when, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$', ...
                'timestamp must be ISO 8601 UTC');
        end

        function theHashIsActuallyFnv1a(tc)
            % KNOWN ANSWERS, against the published FNV-1a 64-bit vectors.
            %
            % Everything else in this class would pass identically if the hash
            % were a wrong-basis, truncating or byte-swapped variant - a
            % generation id is self-consistent whatever it computes, so
            % determinism and sensitivity tests cannot tell "this is FNV-1a"
            % from "this is a hash". Only fixed vectors can, and they pin the
            % offset basis, the prime, the wraparound multiply, the byte order,
            % the UTF-8 encoding and dec2hex's uint64 handling in one go.
            %
            % The basis is the fragile part: 0xCBF29CE484222325 sits where the
            % double ULP is 2048, so any double-valued intermediate drops its
            % low 11 bits silently.
            tc.verifyEqual(cadaFnv1a64(''),       'cbf29ce484222325');
            tc.verifyEqual(cadaFnv1a64('a'),      'af63dc4c8601ec8c');
            tc.verifyEqual(cadaFnv1a64('foobar'), '85944171f73967e8');
        end

        function everyEmissionAffectingOptionIsSigned(tc)
            % The signing list is a DENY-list for a reason (#200 review): as an
            % allow-list it silently missed auxdata and optoutput, and an
            % unsigned option produces no error - just two different artifacts
            % sharing one id. This test fails when a new emission-affecting
            % option is added and left unsigned, which is the failure mode that
            % otherwise reaches a user as a wrong staleness verdict.
            EXCLUDED = {'echo','overwrite','path'};
            signed   = fieldnames(adigatorStampOptions(adigatorOptions()));
            all      = fieldnames(adigatorOptions());
            for k = 1:numel(all)
                if any(strcmp(all{k}, EXCLUDED)); continue; end
                tc.verifyTrue(any(strcmp(all{k}, signed)), sprintf( ...
                    ['option ''%s'' is not signed by the generation id. Either ', ...
                     'sign it, or add it to the documented exclusion list with ', ...
                     'a reason it cannot change the artifact.'], all{k}));
            end
            % ...and the exclusions really are excluded.
            for k = 1:numel(EXCLUDED)
                tc.verifyFalse(any(strcmp(EXCLUDED{k}, signed)), ...
                    [EXCLUDED{k} ' must not move the generation id']);
            end
        end

        function howAFlagWasSpelledDoesNotMoveTheId(tc)
            % A flag arrives as numeric 1 when a user set it and as logical
            % true when an entry point resolved a default - and
            % adigatorGenDerFile_embedded resolves several. mat2str renders
            % those '1' and 'true', which moved the id between two runs that
            % emit byte-identical code. The id must move when the ARTIFACT
            % changes and only then, so an id that moves on spelling is
            % strictly a false staleness alarm.
            writeSrc('fl.m', 'y = sum(exp(x));');
            oNum = tc.Opts; oNum.slim_embed = 1;
            oLog = tc.Opts; oLog.slim_embed = true;
            tc.verifyEqual( ...
                cadaGenerationStamp('2.0', adigatorStampOptions(oLog), {'fl.m'}).id, ...
                cadaGenerationStamp('2.0', adigatorStampOptions(oNum), {'fl.m'}).id, ...
                'logical true and numeric 1 are the same option value');
        end

        function auxdataMovesTheId(tc)
            % The concrete miss the allow-list produced. auxdata reaches
            % ADIGATOR.OPTIONS.AUXDATA (adigator.m) and is read in
            % adigatorFunctionInitialize, where it switches auxiliary inputs
            % between fixed-value and fixed-pattern - two materially different
            % derivative files that used to share one id.
            writeSrc('ax.m', 'y = sum(exp(x));');
            o0 = tc.Opts; o0.auxdata = 0;
            o1 = tc.Opts; o1.auxdata = 1;
            tc.verifyNotEqual( ...
                cadaGenerationStamp('2.0', adigatorStampOptions(o1), {'ax.m'}).id, ...
                cadaGenerationStamp('2.0', adigatorStampOptions(o0), {'ax.m'}).id, ...
                'auxdata changes the emitted artifact, so it must move the id');
        end

        function theReconstructCallNamesTheFileItIsPrintedIn(tc)
            % The reconstruct line's entire value is that pasting it reproduces
            % THIS file. Two ways it silently named a different one (#200
            % review), both of which shipped in the first draft:
            %
            %   NAME - adigatorGenJacFile's 4th argument selects the role. With
            %   'Grd' it writes <fn>_Grd returning [Grd,Fun]; without it,
            %   <fn>_Jac returning [Jac,Fun]. Dropping it turns the recipe into
            %   one for a different file with a different signature.
            %
            %   ENTRY POINT - in embed_mode 'l'/'i' the artifact is finished by
            %   adigatorGenDerFile_embedded (prune, data inlining, %#codegen
            %   patch, join). adigatorGenJacFile does none of that, so naming it
            %   yields an unprocessed file while the printed 'embed_mode','i'
            %   makes the line look authoritative.
            classic = struct('embed_mode','c');
            inline  = struct('embed_mode','i','slim_embed',0);

            grd = strjoin(adigatorReconstructCall('f','f_Grd',classic, ...
                'adigatorGenJacFile','Grd'), ' ');
            tc.verifySubstring(grd, '''Grd''', ...
                'a gradient wrapper must print the name appendix that produces it');

            emb = strjoin(adigatorReconstructCall('f','f_Grd',inline, ...
                {'adigatorGenDerFile_embedded','gradient'}), ' ');
            tc.verifySubstring(emb, 'adigatorGenDerFile_embedded', ...
                'an embedded artifact must name the entry point that finished it');
            tc.verifySubstring(emb, '''gradient''', ...
                'the embedded entry point takes the derivative type first');

            % Unknown provenance for an embedded file: say nothing rather than
            % something wrong (REVIEW_CONTEXT principle 1, applied to claims).
            tc.verifyEmpty(adigatorReconstructCall('f','f_Jac',inline, ...
                'adigatorGenJacFile'), ...
                ['a wrapper generator must not claim to reconstruct an ', ...
                 'embedded artifact it did not finish producing']);

            % SIGNED BUT NOT PRINTED is its own defect: auxdata shapes the
            % artifact (it switches auxiliary inputs between fixed-value and
            % fixed-pattern), so a recipe omitting it silently constant-folds
            % them and rebuilds a different derivative. The printed and signed
            % exclusion lists must not drift apart.
            aux = strjoin(adigatorReconstructCall('f','f_Jac', ...
                struct('embed_mode','c','auxdata',1),'adigatorGenJacFile','Jac'), ' ');
            tc.verifySubstring(aux, 'auxdata', ...
                'an option that moves the generation id must appear in the recipe');

            % The recipe has to RUN. Every wrapper/embedded entry point forces
            % overwrite only when the caller passes no overwrite field, and a
            % printed adigatorOptions(...) always has one - so without this the
            % line dies on "file already exists", beside the file it came from.
            tc.verifySubstring(aux, '''overwrite'',1', ...
                'the reconstruct call must be runnable over the existing file');

            % An UNRECOGNISABLE mode must suppress too. This is the direction
            % the guard fails in, and it is the whole safety property: the
            % first version defaulted to "not embedded, print the recipe" when
            % it could not canonicalise the mode, and that fired for real -
            % the canonicaliser lives in util/, a caller reached it with util/
            % off the path, the catch swallowed it, and an embedded artifact
            % got a recipe naming a generator that does not produce it.
            tc.verifyEmpty(adigatorReconstructCall('f','f_Jac', ...
                struct('embed_mode','!!unrecognisable'),'adigatorGenJacFile'), ...
                'an undeterminable embed mode must suppress the recipe, not print one');

            % A plain Jacobian is the one case that needs no appendix.
            jac = strjoin(adigatorReconstructCall('f','f_Jac',classic, ...
                'adigatorGenJacFile','Jac'), ' ');
            tc.verifySubstring(jac, 'adigatorGenJacFile');
            tc.verifyEmpty(strfind(jac, '''Jac'''), ...
                'the default appendix is noise in the recipe');
        end

        function theHeaderCarriesTheAgreedContent(tc)
            % Pins what #200 actually asked for, so a future edit that drops one
            % of these is a failure rather than a silent regression.
            s = struct('id','0123456789abcdef','when','2026-08-04T12:00:00Z','version','2.0');
            fid = fopen('hdr.txt','w');
            closer = onCleanup(@() fcloseIfOpen(fid));   % B16 hygiene
            cadaPrintGeneratedHeader(fid, 'foo_Grd', s, {'someCall(...)'});
            clear closer
            h = fileread('hdr.txt');

            tc.verifySubstring(h, 'GENERATED FILE',  'must say it is generated');
            tc.verifySubstring(h, 'Do not edit',     'must say not to edit it');
            tc.verifySubstring(h, s.id,              'must carry the generation id');
            tc.verifySubstring(h, s.when,            'must carry the timestamp');
            tc.verifySubstring(h, 'Reconstruct with:','must say how to regenerate');
            tc.verifySubstring(h, 'github.com/pdlourenco/adigator-embedded', ...
                'must route questions to this fork');
            tc.verifySubstring(h, 'General Public License', 'must state the tool licence');

            % The defect #200 opened with: generated files routed fork users to
            % upstream's support channels.
            tc.verifyEmpty(strfind(h, 'mweinstein'), ...
                'must not route users to the upstream maintainer''s email');
            tc.verifyEmpty(strfind(h, 'sourceforge'), ...
                'must not route users to the upstream forums');
        end
    end
end

%% ---------------------------------------------------------------------- %%
function writeSrc(name, bodyLine)
fid = fopen(name, 'w');
assert(fid > 0, 'could not create %s', name);
closer = onCleanup(@() fcloseIfOpen(fid));   % B16 hygiene
fprintf(fid, 'function y = %s(x)\n%s\nend\n', erase(name, '.m'), bodyLine);
end

function writeBytes(name, bytes)
fid = fopen(name, 'w');
assert(fid > 0, 'could not create %s', name);
closer = onCleanup(@() fcloseIfOpen(fid));   % B16 hygiene
fwrite(fid, bytes);
end

function fcloseIfOpen(fid)
% A failed verify must not leave a handle open: on Windows that makes
% WorkingFolderFixture teardown fail too, turning one failure into a cascade.
%
% Just try to close it. Asking `fopen('all')` whether it is open is the obvious
% form and the wrong one - that syntax is being removed, and on a newer release
% it throws from inside an onCleanup destructor, which surfaces as a warning
% attributed to whatever test happens to be finishing.
if isempty(fid) || fid <= 2; return; end
try
    fclose(fid);
catch
    % already closed, which is the normal path
end
end
