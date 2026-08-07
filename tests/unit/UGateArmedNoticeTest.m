classdef UGateArmedNoticeTest < AdigatorTestCase
    % UGateArmedNoticeTest  The unarmed-pre-push-gate notice (#82/#245;
    % CI plan TS-U-22).
    %
    % The notice is advisory, but its states are still a documented failure
    % direction - and REVIEW_CONTEXT.md §Red flags says a direction documented
    % and not asserted is a red flag. These pin it without mutating a real
    % `core.hooksPath` or the environment, which is why ci_gateArmedNotice
    % takes its inputs rather than reading them.
    %
    % License-free.
    %
    %   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
    %   Public License version 3.0.

    methods (Test)
        function silentWhenArmed(tc)
            tc.verifyEmpty(ci_gateArmedNotice('.githooks', false));
            tc.verifyEmpty(ci_gateArmedNotice(sprintf('.githooks\n'), false), ...
                'git config output carries a trailing newline');
            tc.verifyEmpty(ci_gateArmedNotice('/repo/.githooks/', false), ...
                'an absolute path with a trailing separator is still armed');
        end

        function silentOnCI(tc)
            % Hooks are irrelevant on a runner, so an unset hooksPath there is
            % not a finding - and a notice on every CI lint run is noise that
            % teaches people to skim ci_lint output.
            tc.verifyEmpty(ci_gateArmedNotice('', true));
        end

        function warnsWhenUnarmed(tc)
            msg = ci_gateArmedNotice('', false);
            tc.verifyNotEmpty(msg, 'an unset core.hooksPath must be reported');
            tc.verifySubstring(msg, 'not armed');
            tc.verifySubstring(msg, 'git config core.hooksPath .githooks', ...
                'the notice must carry the one-line fix, or it is just a nag');
        end

        function aLookalikePathIsNotArmed(tc)
            % Substring matching would read this as armed. It is not: the hook
            % would never run, and the notice would go quiet about it - the
            % failure this whole notice exists to make visible.
            tc.verifyNotEmpty(ci_gateArmedNotice('.githooks-disabled', false));
            tc.verifyNotEmpty(ci_gateArmedNotice('/tmp/my.githooks.bak', false));
        end
    end
end
