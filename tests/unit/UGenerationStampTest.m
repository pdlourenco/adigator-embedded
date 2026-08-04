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
            fid = fopen('crlf.m','w'); fwrite(fid, crlf); fclose(fid);
            tc.verifyEqual(cadaGenerationStamp('2.0', tc.Opts, {'crlf.m'}).id, lf.id, ...
                'CRLF vs LF source must not move the id');

            trail = regexprep(fileread('lf.m'), '\n', ['   ' newline]);
            fid = fopen('trail.m','w'); fwrite(fid, trail); fclose(fid);
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

        function theHeaderCarriesTheAgreedContent(tc)
            % Pins what #200 actually asked for, so a future edit that drops one
            % of these is a failure rather than a silent regression.
            s = struct('id','0123456789abcdef','when','2026-08-04T12:00:00Z','version','2.0');
            fid = fopen('hdr.txt','w');
            cadaPrintGeneratedHeader(fid, 'foo_Grd', s, {'someCall(...)'});
            fclose(fid);
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
fprintf(fid, 'function y = %s(x)\n%s\nend\n', erase(name, '.m'), bodyLine);
fclose(fid);
end
