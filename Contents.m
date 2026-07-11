% ADiGator (Automatic DIfferentiation by GATORs) - A source transformation
% via operator overloading tool for automatic differentiation of MATLAB
% functions.
%
% Version 2.0 (2026-07-11) — GMV embedded fork
%
% Copyright 2011-2015 Matthew J. Weinstein and Anil V. Rao
% Copyright 2025-2026 GMV / Pedro Lourenço (embedded fork additions)
% Distributed under the GNU General Public License version 3.0
%
% website:  https://github.com/pdlourenco/adigator-embedded
% upstream: https://github.com/matt-weinstein/adigator
%
% ----------------------------------------------------------------------- %
% FILES:
% adigator.m                 - main adigator function
% adigatorCreateAuxInput.m   - function for identifying auxiliary numerical
%                              inputs
% adigatorCreateDerivInput.m - function for identifying derivative inputs
% adigatorOptions.m          - function for setting adigator options
%                              structure
% startupadigator.m          - path setup for adigator toolbox
%
% ----------------------------------------------------------------------- %
% DIRECTORIES:
% docs     - readme, licensing, user's guide and reference papers
% examples - various example problems
% lib      - ADiGator library of source transformation routines, overloaded
%            classes, etc
% util     - user utility functions to invoke source transformation