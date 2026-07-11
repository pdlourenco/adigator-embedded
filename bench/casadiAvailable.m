function tf = casadiAvailable()
% casadiAvailable  True if CasADi's MATLAB interface is importable.
%
% Used to gate the independent CasADi oracle (SCasadiOracleTest, ADR-0018) so it
% skips cleanly when CasADi is absent - exactly like the Coder-gated system
% tests skip without a MATLAB Coder license.
%
% CasADi binaries are NOT committed to the repo (50 MB+, platform-specific).
% Provision them out-of-band and make them visible to this function one of two
% ways:
%   * addpath the CasADi MATLAB folder yourself before running, or
%   * set the environment variable CASADI_DIR to that folder - this function
%     addpath's it on demand (handy for CI, where the job exports CASADI_DIR).
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

    tf = exist('casadi.SX', 'class') == 8;
    if tf; return; end

    d = getenv('CASADI_DIR');
    if ~isempty(d) && isfolder(d)
        addpath(d);
        tf = exist('casadi.SX', 'class') == 8;
    end
end
