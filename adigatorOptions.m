function options = adigatorOptions(varargin)
% ADiGator Options Structure Generator: Called in order set/modify default
% ADiGator options.
% 
% ------------------------------ Usage ---------------------------------- %
% options = adigatorOptions(field1,value1,field2,value2,...)
%
% ------------------------ Input Information ---------------------------- %
% field:  string name of option to be modified
% value:  value to set option to
%
% ----------------------- Output Information ---------------------------- %
% options: structure to be passed to adigator, or any of the utility
%          ADiGator generation routines (adigatorGenJacFile,
%          adigatorGenHesFile, adigatorGenFiles4Fmincon,
%          adigatorGenFiles4Ipopt, adigatorGenFiles4gpops2)
%
%                                OPTIONS:  
% ------------------------------------------------------------------------
%    AUXDATA:  1 - auxiliary inputs will always have the same sparsity
%                  pattern but may change numeric values 
%              0 - auxiliary inputs will always have the same numeric
%                  values (required if inputs are a size to be looped on or
%                  a reference index, etc.) (default)
%       ECHO:  1 - echo to screen the transformation progress (default)
%              0 - dont echo
%     UNROLL:  1 - unroll loops and sub functions in derivative program
%              0 - keep loops and sub functions rolled in derivative 
%                  (default)
%   COMMENTS:  1 - print comments to derivative file giving the lines of
%                  user code which correspond to the printed statements
%                  (default)
%              0 - dont print comments
%  OVERWRITE:  1 - if the user supplies a derivative file name which
%                  corresponds to an already existing file, then setting
%                  this option will overwrite the existing file. (default
%                  for adigatorGenFiles4gpops2, adigatorGenJacFile,
%                  adigatorGenHesFile, adigatorGenFiles4Ipopt,
%                  adigatorGenFiles4Fmincon)
%              0 - if a file already exists with the same name as the given
%                  derivative file name, then it will not overwrite and
%                  error out instead (default for adigator)
% MAXWHILEITER:k - maximum number of iterations to attempt to find a static
%                  input/output for WHILE loops (default set to 10) -
%                  increasing this will increase derivative file generation
%                  times when using WHILE loops
%    COMPLEX:  0 - do not expect any variables to be complex, use 
%                  non-complex forms of abs, ctranspose, dot (default)
%              1 - expect variables to be complex, use complex forms of
%                  ctranspose, abs, dot.
% EMBED_MODE: 'c'- Classic. The data on the generated derivatives is stored
%                  in a .mat file that is loaded every time the generated
%                  derivative function is called and stored in a global 
%                  variable. Not suitable for embedded code generation!
%                  DEFAULT OPTION
%             'l'- CoderLoad. The data is still stored in a .mat file. If 
%                  the derivative file is called as an interpreted MATLAB
%                  function, the data is loaded at runtime. If, however,
%                  the function is compiled into C-code through the code
%                  generation utilities of embedded coder, the data is
%                  loaded only at compile-time, and is placed in a persistent
%                  variable as a constant. Suitable for code generation, but
%                  still depends on a persistent variable and an external
%                  binary data file.
%             'i'- Inline. The data is stored in a function, which is 
%                  called as a compile-time constant. In regular execution
%                  the function is called everytime the resulting derivative
%                  function is needed, but in embedded code it is stored as
%                  a constant. Suitable for code generation, no usage of 
%                  external binary files or persistent variables.
%       PATH: [] - if empty the generate files with the derivative functions
%                  are placed in the current calling directory. DEFAULT
%             '' - the user can provide the directory for storing the
%                  generated functions in this field.
%  LOOPBOUND: {} - all loop bounds are fixed at their generation-time trip
%                  counts (default).
%             '' - char/string/cellstr naming input(s) of the
%                  differentiated function which act as RUNTIME loop
%                  bounds (roadmap R3; issue #6 Tier 1). Each named input
%                  must be passed to adigator as a plain numeric positive
%                  integer scalar: its value is the MAXIMUM trip count,
%                  used for the analysis. Every outermost rolled loop in
%                  the main differentiated function (and every inner
%                  rolled loop with a constant analyzed bound) whose trip
%                  count equals that value is then printed with the named
%                  input as its bound, guarded by assert(name <= max), and
%                  its exit variables take the union over all iterations.
%                  The generated file may be called with any 1 <= n <= max.
%                  PADDED-PROGRAM SEMANTICS: the file differentiates the
%                  max-padded program. Generated code references the named
%                  input BY NAME, so arrays the user code sizes directly
%                  by it (e.g. zeros(N,1)) are allocated at the runtime
%                  value; arrays with literal analyzed sizes keep the max
%                  size, with exact structural zeros beyond the executed
%                  prefix; derivative buffers and the output sparsity
%                  pattern always use the fixed max-trip-count pattern.
%                  Results agree with the true n-sized program iff
%                  post-loop code is padding-benign (sums, dot products,
%                  scatter/gather over the loop-written entries: yes;
%                  length/end/mean/max over a FIXED-size buffer's padded
%                  tail: no - they see max). Loops are matched BY
%                  TRIP-COUNT VALUE: give each runtime-bound parameter a
%                  distinct max value that no fixed loop in the code
%                  shares. Not compatible with 'unroll'.
% ------------------------------------------------------------------------
%
% NOTES:    The default value of the OVERWRITE option changes depending
%           upon whether the basic adigator file is being called or one of
%           the wrapper generation files.
%
% If desired, the defaults of each option may be changed by editing this
% file.
%
% Copyright 2011-2014 Matthew J. Weinstein and Anil V. Rao
% Distributed under the GNU General Public License version 3.0
%
% See also adigator, adigatorGenFiles4gpops2
%
%   Modifications as described below are Copyright GMV.
%   2025-10  PEDRO LOURENÇO (PADL) - palourenco@gmv.com
%
%   Changelog:
%   2025-10 Pedro Lourenço  v1.5    Add option to generate streamlined code
%                                   that can be accepted for embedded code
%                                   use, e.g., without runtime loading of 
%                                   files/data/options.
%                                   Add option for user to provide the path
%                                   to the directory where the generated
%                                   files should be stored
%   2026-06                         Normalize EMBED_MODE aliases
%                                   (c/classic, l/coderload, i/inline) at
%                                   parse time (B11, PR #8).
%                                   Add the LOOPBOUND option: runtime loop
%                                   bounds with the padded-program
%                                   contract documented above (roadmap R3,
%                                   issue #6 Tier 1, PR #15).

% Set Defaults
options.embed_mode   = 'c'; % v1.5 - 'c(lassic)' | '(coder)l(oad)' | 'i(nline)'
options.path         = []; % v1.5 - user provided path; default: calling dir
options.auxdata      = 0;
options.echo         = 1;
options.unroll       = 0;
options.comments     = 1;
options.overwrite    = 0;
options.optoutput    = 0;
options.maxwhileiter = 10;
options.complex      = 0;
options.loopbound    = {}; % roadmap R3 (issue #6 Tier 1): runtime loop bounds

if nargin/2 ~= floor(nargin/2)
  error('Inputs to adigatorOptions must come in field/value pairs')
end

% Set user wanted options
for i = 1:nargin/2
  field = lower(varargin{2*(i-1)+1});
  value = varargin{2*i};
  switch field
    case {'auxdata','echo','unroll','comments','overwrite','genpat',...
        'optoutput','complex'}
      options.(field) = logical(value);
      case 'embed_mode' % v1.5 (B11 fix): accept c/classic, l/coderload, i/inline
      options.embed_mode = adigatorNormalizeEmbedMode(value);
      case 'loopbound' % roadmap R3 (issue #6 Tier 1)
      if ischar(value)
        value = {value};
      elseif isstring(value)
        value = cellstr(value);
      elseif ~iscell(value) || ~all(cellfun(@ischar,value(:)))
        error('adigator:loopbound:option',...
          ['loopbound must be a char, string, or cellstr naming ',...
          'input(s) of the differentiated function']);
      end
      options.loopbound = value;
      case {'maxwhileiter','path'} % v1.5
      options.(field) = value;
    otherwise
      warning(['Invalid option field: ',field])
  end
end