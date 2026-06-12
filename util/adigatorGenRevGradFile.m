function output = adigatorGenRevGradFile(UserFun,UserFunInputs,varargin)
% ADIGATORGENREVGRADFILE  Reverse-mode gradient file generator (prototype).
%
% --------------------------- Usage ------------------------------------- %
% output = adigatorGenRevGradFile(UserFun,UserFunInputs)
% output = adigatorGenRevGradFile(UserFun,UserFunInputs,opts)
%
% Generates <UserFun>_RGrd.m computing [y, grad] = <UserFun>_RGrd(inputs),
% where y is the scalar value of the user function and grad the column
% gradient with respect to the (single) derivative input, by a REVERSE
% (adjoint) sweep: one function-cost forward pass plus one adjoint pass,
% with cost independent of the number of variables (docs/ANALYSIS.md
% section 3; roadmap R4). The derivative input is passed to the generated
% file as a plain numeric array (no seed structure).
%
% Method (ANALYSIS.md 3.4, the standalone source-to-source path): the
% forward derivative file printed by adigator() is a flat program in a
% small regular dialect with all indices constant - a static tape. This
% generator runs adigator() on the user function, extracts the
% function-value statements by backward slicing from the output, executes
% that tape once at generation time on test inputs to learn every
% intermediate's size and to resolve all indexing/concatenation into
% constant linear maps, and then emits the adjoint program: the forward
% statements followed by their adjoints in reverse order. The emitted file
% is self-contained, loading its own .mat of constants with the same
% Gator1Data layout as forward-generated files.
%
% ------------------------ Input Information ---------------------------- %
% UserFun       - string name of the user function file. Exactly one
%                 output, which must be SCALAR (a cost).
% UserFunInputs - cell array of inputs as for adigator(): exactly one
%                 created by adigatorCreateDerivInput (the variable of
%                 differentiation), the rest auxiliary inputs or fixed
%                 numeric values. No vectorized (Inf) sizes.
% opts          - optional adigatorOptions structure; overwrite, path and
%                 echo are honored. Loops in the user code must be
%                 unrolled: pass adigatorOptions('unroll',1) if the
%                 function contains loops (rolled control flow in the
%                 generated file is rejected with a clear error).
%
% ----------------------- Output Information ---------------------------- %
% output.FunctionFile / output.MatFile / output.Path - generated artifacts
%
% --------------------------- Restrictions ------------------------------ %
% Supported ACTIVE operations (operations on the path from the variable of
% differentiation to the output): plus, minus, times, rdivide, power with
% an inactive exponent, mtimes, sum, transpose, reshape, constant-index
% gathers/scatters/concatenations, and the unary functions sin, cos, tan,
% exp, log, sqrt, tanh, sinh, cosh, asin, acos, atan, uminus, uplus.
% Statements off that path pass through untouched, whatever they are.
% Anything unsupported on the active path errors at generation time,
% naming the offending generated statement.
%
% Copyright GMV.
% Changelog:
%   2026-06    Created (roadmap R4, docs/ANALYSIS.md 3.4).
%
% See also adigator adigatorGenJacFile adigatorOptions

% ----------------------------- options --------------------------------- %
opts = adigatorOptions();
opts.overwrite = 1;
if nargin > 2
  optfields = fieldnames(varargin{1});
  for Fcount = 1:length(optfields)
    opts.(lower(optfields{Fcount})) = varargin{1}.(optfields{Fcount});
  end
elseif nargin < 2
  error('adigator:revgrad:inputs','UserFun and UserFunInputs are required');
end
if isempty(opts.path)
  OutDir = cd;
else
  OutDir = opts.path;
end

% --------------------------- validate inputs --------------------------- %
if ~iscell(UserFunInputs)
  error('adigator:revgrad:inputs','UserFunInputs must be a cell array');
end
vodLoc = 0;
for Icount = 1:numel(UserFunInputs)
  ui = UserFunInputs{Icount};
  if isa(ui,'adigatorInput')
    if ~isempty(ui.deriv)
      if vodLoc
        error('adigator:revgrad:inputs',...
          'exactly one derivative input is supported');
      end
      vodLoc = Icount;
    end
    if any(isinf(ui.func.size))
      error('adigator:revgrad:inputs',...
        'vectorized (Inf) inputs are not supported');
    end
  elseif ~isnumeric(ui)
    error('adigator:revgrad:inputs',...
      'inputs must be adigatorInput objects or numeric values');
  end
end
if ~vodLoc
  error('adigator:revgrad:inputs','no derivative input found');
end
vodsize = UserFunInputs{vodLoc}.func.size;

% ------------------------ generate the forward tape -------------------- %
FwdName = [UserFun,'_ADiGatorRGrdFwd'];
RevName = [UserFun,'_RGrd'];
fwdopts = opts; fwdopts.overwrite = 1;
adigator(UserFun,UserFunInputs,FwdName,fwdopts);
rehash;
FwdFile = fullfile(OutDir,[FwdName,'.m']);
FwdMat  = fullfile(OutDir,[FwdName,'.mat']);
FwdGator = struct();
if exist(FwdMat,'file')
  fwddata = load(FwdMat);
  if isfield(fwddata,FwdName) && isfield(fwddata.(FwdName),'Gator1Data')
    FwdGator = fwddata.(FwdName).Gator1Data;
  end
end

txt = readlines(FwdFile);

% ------------------- locate the header and the body -------------------- %
funline = char(txt(find(startsWith(strtrim(txt),'function'),1)));
[OutNames,InNames] = parseheader(funline);
if numel(OutNames) ~= 1
  error('adigator:revgrad:outputs',...
    'the user function must have exactly one (scalar) output');
end
OutName = OutNames{1};
if numel(InNames) ~= numel(UserFunInputs)
  error('adigator:revgrad:inputs','input count mismatch with %s',UserFun);
end
VodName = InNames{vodLoc};
bodystart = find(contains(txt,'ADiGator Start Derivative Computations'),1);
bodyend   = find(strcmp(strtrim(txt),'function ADiGator_LoadData()'),1);
if isempty(bodystart) || isempty(bodyend)
  error('adigator:revgrad:parse','unrecognized generated-file skeleton');
end
body = txt(bodystart+1:bodyend-1);

% ------------------------- collect statements -------------------------- %
stmts = cell(0,1);
for Lcount = 1:numel(body)
  ln = strtrim(char(body(Lcount)));
  if isempty(ln) || ln(1) == '%'
    continue
  end
  if strcmp(ln,'end') || strcmp(ln,'return')
    break % closing of the generated main function
  end
  if ~isempty(regexp(ln,'^(for|while|if|elseif|else|switch)\>','once'))
    error('adigator:revgrad:controlflow',...
      ['the generated file contains rolled control flow (''%s''); ',...
      'generate with adigatorOptions(''unroll'',1) or remove loops'],ln);
  end
  stmts{end+1,1} = ln; %#ok<AGROW> statement list is built line by line
end

% parse: lhs base name (with optional .f), scatter subscript text, rhs
n = numel(stmts);
S = struct('text',stmts,'lhs',[],'lhsSubs',[],'rhs',[],'deps',[],...
  'active',[],'kind',[],'info',[]);
reserved = {'S','Gator1Data','UserFunInputs','InNames','vodLoc','VodName',...
  'OutName','stmts','reserved','FwdGator','fwddata'};
for k = 1:n
  % split at the first top-level '=' (the dialect has no '==' and no '='
  % inside subscripts); parse the LHS manually rather than with optional
  % regexp groups, whose tokens MATLAB drops when they do not participate
  ln = S(k).text;
  eq = strfind(ln,'=');
  if isempty(eq) || ln(end) ~= ';'
    error('adigator:revgrad:parse','cannot parse generated statement: %s',ln);
  end
  lhsfull = strtrim(ln(1:eq(1)-1));
  S(k).rhs = strtrim(ln(eq(1)+1:end-1));
  par = strfind(lhsfull,'(');
  if isempty(par)
    S(k).lhs     = lhsfull;
    S(k).lhsSubs = '';
  elseif lhsfull(end) == ')'
    S(k).lhs     = strtrim(lhsfull(1:par(1)-1));
    S(k).lhsSubs = lhsfull(par(1)+1:end-1);
  else
    error('adigator:revgrad:parse','cannot parse generated statement: %s',ln);
  end
  if isempty(regexp(S(k).lhs,'^[A-Za-z]\w*(\.\w+)?$','once')) || ...
      isempty(S(k).rhs)
    error('adigator:revgrad:parse','cannot parse generated statement: %s',ln);
  end
  if ~isempty(regexp(ln,'\<cadaRG','once'))
    error('adigator:revgrad:parse','reserved name cadaRG* in generated code');
  end
  if any(strcmp(strtok(S(k).lhs,'.'),reserved))
    error('adigator:revgrad:parse',...
      'variable name ''%s'' collides with a generator-internal name',...
      strtok(S(k).lhs,'.'));
  end
end
if any(ismember(InNames,reserved))
  error('adigator:revgrad:parse',...
    'an input name collides with a generator-internal name');
end

% --------------- dependencies and backward slice from out.f ------------ %
defined = [InNames(:); {'Gator1Data'}];
for k = 1:n
  % strip dotted tails so field names are not mistaken for variables
  depsrc = regexprep([S(k).rhs,' ',char(S(k).lhsSubs)],'\.\w+','');
  ids = regexp(depsrc,'[A-Za-z]\w*','match');
  S(k).deps = intersect(ids,defined);
  if ~isempty(S(k).lhsSubs)
    S(k).deps = union(S(k).deps,{strtok(S(k).lhs,'.')}); % scatter reads old
  end
  defined = union(defined,{strtok(S(k).lhs,'.')});
end
outStmt = find(strcmp({S.lhs},[OutName,'.f']),1,'last');
if isempty(outStmt)
  error('adigator:revgrad:parse','could not find %s.f assignment',OutName);
end
need = false(n,1); need(outStmt) = true;
% the wanted set holds base names (dependencies are dot-stripped) plus the
% full dotted output ('y.f'); matching on the FULL lhs keeps 'y.f' and
% excludes 'y.dx'. The dotted-base fallback (for struct-field writers like
% 'r.f' matched through their base) must NEVER admit derivative fields
% ('r.dx' shares the base with 'r.f' but writes d<vod> data), or the
% forward-derivative temp chain gets sliced back in through them.
dxfield = ['.d',VodName];
wanted = union({S(outStmt).lhs},S(outStmt).deps);
for k = outStmt-1:-1:1
  if endsWith(S(k).lhs,dxfield)
    continue % derivative statement: never part of the value slice
  end
  if any(strcmp(S(k).lhs,wanted)) || ...
      (~strcmp(S(k).lhs,strtok(S(k).lhs,'.')) && ...
      any(strcmp(strtok(S(k).lhs,'.'),wanted)))
    need(k) = true;
    wanted = union(wanted,S(k).deps);
  end
end
S = S(need);
n = numel(S);
for k = 1:n
  % safety net: a leaked derivative reference would mean a silently wrong
  % gradient, so refuse loudly instead
  if ~isempty(regexp(S(k).text,['\.d',VodName,'\>'],'once'))
    error('adigator:revgrad:parse',...
      'internal: derivative statement leaked into the value slice: %s',...
      S(k).text);
  end
end

% ------------------ execute the tape; classify; resolve ---------------- %
S = execAndClassify(S,FwdGator,UserFunInputs,InNames,vodLoc,VodName);
if ~isequal(S(n).info.lsz,[1 1])
  error('adigator:revgrad:outputs',...
    'the output %s of %s must be scalar for a reverse gradient',...
    OutName,UserFun);
end

% ----------------------------- emit ------------------------------------ %
[revtxt,RevGator] = emitReverse(S,FwdGator,RevName,InNames,VodName,...
  OutName,vodsize,UserFun);

RevFile = fullfile(OutDir,[RevName,'.m']);
RevMat  = fullfile(OutDir,[RevName,'.mat']);
if exist(RevFile,'file') && ~opts.overwrite
  error('adigator:revgrad:overwrite','%s exists; set overwrite',RevFile);
end
fid = fopen(RevFile,'w');
fprintf(fid,'%s\n',revtxt{:});
fclose(fid);
% .mat layout matches forward-generated files: <RevName>.Gator1Data
revdata = struct();
revdata.(RevName) = struct('Gator1Data',RevGator);
if ~isfield(revdata,RevName)
  error('adigator:revgrad:io','internal error assembling %s',RevMat);
end
save(RevMat,'-struct','revdata');
% the reverse file is self-contained: remove the forward intermediate
delete(FwdFile); delete(FwdMat);
clear('global',['ADiGator_',FwdName]);
clear('global',['ADiGator_',RevName]);
rehash;
if opts.echo
  fprintf(['<strong>adigatorGenRevGradFile</strong> successfully ',...
    'generated reverse gradient file: ''%s'';\n'],RevName);
end
output.FunctionFile = RevFile;
output.MatFile      = RevMat;
output.Path         = OutDir;
end

%% ------------------------------------------------------------------- %%
function [OutNames,InNames] = parseheader(funline)
tok = regexp(funline,...
  '^function\s*\[?([^\]=]*)\]?\s*=\s*\w+\s*\(([^)]*)\)','tokens','once');
if isempty(tok)
  error('adigator:revgrad:parse','cannot parse function line: %s',funline);
end
OutNames = strtrim(strsplit(tok{1},','));
InNames  = strtrim(strsplit(tok{2},','));
end

%% ------------------------------------------------------------------- %%
function S = execAndClassify(S,Gator1Data,UserFunInputs,InNames,vodLoc,VodName)
% Executes the sliced tape once with test inputs to learn sizes, resolve
% every indexing/concatenation into constant linear maps, and classify
% each statement. Tape statements are eval'd in THIS workspace; all
% generator locals are cadaRG_-prefixed (names checked by the caller).
assert(isstruct(Gator1Data)); % referenced by the eval'd tape statements
for cadaRG_i = 1:numel(InNames)
  cadaRG_ui = UserFunInputs{cadaRG_i};
  if isa(cadaRG_ui,'adigatorInput')
    cadaRG_sz = cadaRG_ui.func.size;
    if cadaRG_i == vodLoc
      cadaRG_v = struct('f',0.1+rand(cadaRG_sz),'dx',ones(prod(cadaRG_sz),1));
    else
      cadaRG_v = 0.1 + rand(cadaRG_sz);
    end
  else
    cadaRG_v = cadaRG_ui;
  end
  assert(isstruct(cadaRG_v) || isnumeric(cadaRG_v)); % consumed by eval below
  eval([InNames{cadaRG_i},' = cadaRG_v;']);
end

% atom: NAME | NAME.field | numeric literal
cadaRG_atom = ['(?:[A-Za-z]\w*(?:\.\w+)?|',...
  '[-+]?\d+\.?\d*(?:[eE][-+]?\d+)?)'];
cadaRG_unary = {'sin','cos','tan','exp','log','sqrt','tanh','sinh','cosh',...
  'asin','acos','atan','uminus','uplus'};
cadaRG_known = [InNames(:).',{'Gator1Data'}]; % defined variable bases

for cadaRG_k = 1:numel(S)
  cadaRG_rhs = S(cadaRG_k).rhs;
  cadaRG_info = struct();
  % activity: resolves each dependency to its most recent writer.
  % Creation and metadata statements (zeros/ones/eye/size/length/numel)
  % are value-independent of the differentiation variable: never active,
  % even when an active variable appears in a size argument.
  if isempty(S(cadaRG_k).lhsSubs) && ~isempty(regexp(cadaRG_rhs,...
      '^(zeros|ones|eye|size|length|numel)\(','once'))
    cadaRG_act = false;
  else
    cadaRG_act = false;
    for cadaRG_d = 1:numel(S(cadaRG_k).deps)
      cadaRG_dn = S(cadaRG_k).deps{cadaRG_d};
      if strcmp(cadaRG_dn,VodName)
        cadaRG_act = true;
      else
        for cadaRG_j = cadaRG_k-1:-1:1
          if strcmp(strtok(S(cadaRG_j).lhs,'.'),cadaRG_dn)
            cadaRG_act = cadaRG_act || S(cadaRG_j).active;
            break
          end
        end
      end
    end
  end
  S(cadaRG_k).active = cadaRG_act;

  % --------------------------- classify -------------------------------- %
  cadaRG_kind = 'passive';
  if ~isempty(S(cadaRG_k).lhsSubs)
    cadaRG_kind = 'scatter';
    cadaRG_info.src = cadaRG_rhs;
    if isempty(regexp(cadaRG_rhs,['^',cadaRG_atom,'$'],'once'))
      cadaRG_kind = 'passive'; % non-atomic scattered rhs: unsupported
    end
  elseif ~isempty(regexp(cadaRG_rhs,['^',cadaRG_atom,'$'],'once'))
    cadaRG_kind = 'copy';
    cadaRG_info.src = cadaRG_rhs;
  else
    cadaRG_tok = regexp(cadaRG_rhs,['^(',cadaRG_atom,...
      ')\s*(\+|\-|\.\*|\*|\./|/|\.\^|\^)\s*(',cadaRG_atom,')$'],...
      'tokens','once');
    if ~isempty(cadaRG_tok)
      cadaRG_kind = 'binary';
      cadaRG_info.a  = cadaRG_tok{1};
      cadaRG_info.op = cadaRG_tok{2};
      cadaRG_info.b  = cadaRG_tok{3};
    else
      cadaRG_tok = regexp(cadaRG_rhs,['^(\w+)\((',cadaRG_atom,')\)$'],...
        'tokens','once');
      if ~isempty(cadaRG_tok) && any(strcmp(cadaRG_tok{1},cadaRG_unary))
        cadaRG_kind = 'unary';
        cadaRG_info.fun = cadaRG_tok{1};
        cadaRG_info.a   = cadaRG_tok{2};
      else
        cadaRG_tok = regexp(cadaRG_rhs,...
          ['^sum\((',cadaRG_atom,')(,\d)?\)$'],'tokens','once');
        if ~isempty(cadaRG_tok)
          cadaRG_kind = 'sum';
          cadaRG_info.a = cadaRG_tok{1};
        else
          cadaRG_tok = regexp(cadaRG_rhs,['^(',cadaRG_atom,')\.''$'],...
            'tokens','once');
          if ~isempty(cadaRG_tok)
            cadaRG_kind = 'transpose';
            cadaRG_info.a = cadaRG_tok{1};
          else
            cadaRG_tok = regexp(cadaRG_rhs,...
              ['^reshape\((',cadaRG_atom,'),.*\)$'],'tokens','once');
            if ~isempty(cadaRG_tok)
              cadaRG_kind = 'reshape';
              cadaRG_info.a = cadaRG_tok{1};
            else
              cadaRG_tok = regexp(cadaRG_rhs,...
                '^([A-Za-z]\w*(?:\.\w+)?)\(([^=]*)\)$','tokens','once');
              if ~isempty(cadaRG_tok) && ...
                  any(strcmp(strtok(cadaRG_tok{1},'.'),cadaRG_known))
                % indexing into a known variable (a function call with an
                % unknown base stays 'passive' and errors only if active)
                cadaRG_kind = 'gather';
                cadaRG_info.a    = cadaRG_tok{1};
                cadaRG_info.subs = cadaRG_tok{2};
              elseif ~isempty(regexp(cadaRG_rhs,'^\[.*\]$','once'))
                cadaRG_kind = 'concat';
              end
            end
          end
        end
      end
    end
  end
  if strcmp(cadaRG_kind,'passive') && cadaRG_act
    error('adigator:revgrad:unsupported',...
      ['unsupported operation on the differentiation path: ''%s'' ',...
      '(see the help for the supported set)'],S(cadaRG_k).text);
  end

  % ------- structural maps via reference-code arrays (active only) ----- %
  if cadaRG_act
    switch cadaRG_kind
      case 'gather'
        cadaRG_src = eval(cadaRG_info.a);
        cadaRG_ref = zeros(size(cadaRG_src));
        cadaRG_ref(:) = 1:numel(cadaRG_src);
        assert(isnumeric(cadaRG_ref)); % consumed by the eval'd index text
        cadaRG_map = eval(['cadaRG_ref(',cadaRG_info.subs,')']);
        cadaRG_info.map  = cadaRG_map(:);
        cadaRG_info.asz  = size(cadaRG_src);
        cadaRG_info.dups = numel(unique(cadaRG_info.map)) < ...
          numel(cadaRG_info.map);
      case 'scatter'
        cadaRG_old = eval(S(cadaRG_k).lhs); % full name incl. any .f field
        cadaRG_ref = zeros(size(cadaRG_old));
        cadaRG_ref(:) = 1:numel(cadaRG_old);
        assert(isnumeric(cadaRG_ref)); % consumed by the eval'd index text
        cadaRG_map = eval(['cadaRG_ref(',S(cadaRG_k).lhsSubs,')']);
        cadaRG_info.map   = cadaRG_map(:);
        cadaRG_info.srcsz = size(eval(cadaRG_info.src));
      case 'concat'
        % resolve the per-source linear maps by SHADOWING each operand
        % variable with its (offset) reference codes and evaluating the
        % original bracket text unchanged - no textual substitution, so
        % any operand form the printer emits (fields, indexing,
        % transposes) is handled uniformly
        cadaRG_inner = S(cadaRG_k).rhs;
        if ~isempty(regexp(cadaRG_inner,'(?<![\w.])\d','once'))
          error('adigator:revgrad:unsupported',...
            ['numeric literals inside an active concatenation are not ',...
            'supported: %s'],S(cadaRG_k).text);
        end
        cadaRG_ops = unique(regexp(cadaRG_inner(2:end-1),...
          '[A-Za-z]\w*(?:\.\w+)?','match'),'stable');
        cadaRG_off = 0;
        cadaRG_srcs = cell(numel(cadaRG_ops),1);
        cadaRG_sav = cell(numel(cadaRG_ops),1);
        for cadaRG_j = 1:numel(cadaRG_ops)
          try
            cadaRG_v = eval(cadaRG_ops{cadaRG_j});
          catch
            error('adigator:revgrad:unsupported',...
              ['unsupported operand form inside an active ',...
              'concatenation: %s'],S(cadaRG_k).text);
          end
          cadaRG_r = zeros(size(cadaRG_v));
          cadaRG_r(:) = cadaRG_off + (1:numel(cadaRG_v));
          cadaRG_srcs{cadaRG_j} = struct('name',cadaRG_ops{cadaRG_j},...
            'off',cadaRG_off,'num',numel(cadaRG_v),'sz',size(cadaRG_v));
          cadaRG_sav{cadaRG_j} = cadaRG_v;
          assert(isnumeric(cadaRG_r) && iscell(cadaRG_sav)); % eval'd below
          eval([cadaRG_ops{cadaRG_j},' = cadaRG_r;']);
          cadaRG_off = cadaRG_off + numel(cadaRG_v);
        end
        cadaRG_codes = eval(cadaRG_inner);
        for cadaRG_j = 1:numel(cadaRG_ops)
          eval([cadaRG_ops{cadaRG_j},' = cadaRG_sav{cadaRG_j};']);
        end
        cadaRG_info.srcs  = cadaRG_srcs;
        cadaRG_info.codes = cadaRG_codes(:);
    end
  end

  % --------------------------- execute --------------------------------- %
  try
    eval(S(cadaRG_k).text);
  catch cadaRG_err
    error('adigator:revgrad:exec',...
      'tape execution failed at ''%s'': %s',...
      S(cadaRG_k).text,cadaRG_err.message);
  end
  cadaRG_known = union(cadaRG_known,{strtok(S(cadaRG_k).lhs,'.')});
  cadaRG_val = eval(strtok(S(cadaRG_k).lhs,'('));
  S(cadaRG_k).kind = cadaRG_kind;
  cadaRG_info.lsz = size(cadaRG_val);
  if isfield(cadaRG_info,'a')
    cadaRG_info.asz2 = size(eval(cadaRG_info.a));
  end
  if isfield(cadaRG_info,'b')
    cadaRG_info.bsz = size(eval(cadaRG_info.b));
  end
  S(cadaRG_k).info = cadaRG_info;
end
end

%% ------------------------------------------------------------------- %%
function [txt,RevGator] = emitReverse(S,FwdGator,RevName,InNames,VodName,...
  OutName,vodsize,UserFun)
% Emits the reverse file text and assembles its constant data struct.
n = numel(S);
RevGator = struct();
for k = 1:n % copy every referenced forward constant
  flds = regexp(S(k).text,'Gator1Data\.(\w+)','tokens');
  for j = 1:numel(flds)
    RevGator.(flds{j}{1}) = FwdGator.(flds{j}{1});
  end
end

% multiply-written base names need their non-final versions snapshotted in
% the forward sweep so the reverse sweep sees the right values
bases = cell(n,1);
for k = 1:n
  bases{k} = strtok(S(k).lhs,'.');
end
snap = false(n,1);
for k = 1:n
  snap(k) = any(strcmp(bases{k},bases(k+1:end)));
end

txt = cell(6*n+40,1);
c = 0;
ridx = 0;
GlobalVar = ['ADiGator_',RevName];
bar = cell(n,1);
for k = 1:n
  bar{k} = sprintf('cadaRGb%d',k);
end
vbar = 'cadaRGbx';
init = false(n,1);
vinit = false;

  function emit(s)
    c = c + 1;
    txt{c} = s;
  end

  function ensureinit(j)
    % zero-initialize an adjoint buffer at its (statement-shaped) size
    if j == 0
      if ~vinit
        emit(sprintf('%s = zeros(%d,%d);',vbar,vodsize(1),vodsize(2)));
        vinit = true;
      end
    elseif ~init(j)
      emit(sprintf('%s = zeros(%d,%d);',bar{j},...
        S(j).info.lsz(1),S(j).info.lsz(2)));
      init(j) = true;
    end
  end

  function addbar(j,expr)
    % accumulate a (broadcast-compatible) contribution into adjoint j
    ensureinit(j);
    if j == 0
      emit([vbar,' = ',vbar,' + ',expr,';']);
    else
      emit([bar{j},' = ',bar{j},' + ',expr,';']);
    end
  end

  function [src,isconst] = whobar(atom,k)
    % resolve an operand atom at statement k to its adjoint target:
    % 0 = variable of differentiation, j = statement index, const = none
    isconst = false; src = -1;
    base = strtok(atom,'.(');
    if strcmp(base,VodName)
      src = 0;
      return
    end
    for jn = k-1:-1:1 % own loop variable: the parent workspace is shared
      if strcmp(bases{jn},base)
        if S(jn).active
          src = jn;
        else
          isconst = true;
        end
        return
      end
    end
    isconst = true; % literal, Gator constant, or inactive input
  end

  function t = restext(atom,k)
    % forward-value text of an operand atom as seen at statement k: the
    % snapshot name if that version was later overwritten, else the
    % original name (with <vod>.f referenced as the plain input)
    base = strtok(atom,'.(');
    if strcmp(base,VodName)
      t = VodName; % inputs are never reassigned by generated code
      return
    end
    for jn = k-1:-1:1 % own loop variable: the parent workspace is shared
      if strcmp(bases{jn},base)
        if snap(jn)
          % snapshots copy the base variable; keep any field suffix (.f)
          t = [sprintf('cadaRGsv%d',jn),atom(numel(base)+1:end)];
        else
          t = atom;
        end
        return
      end
    end
    t = atom; % literal or constant
  end

  function t = selftext(k)
    % forward value of statement k's own result, as seen in reverse
    if snap(k)
      t = [sprintf('cadaRGsv%d',k),S(k).lhs(numel(bases{k})+1:end)];
    elseif strcmp(S(k).lhs,[OutName,'.f'])
      t = OutName; % the output statement is emitted with its .f stripped
    else
      t = S(k).lhs;
    end
  end

  function expr = sumto(expr,esz,tsz)
    % reduce a contribution shaped esz onto a target shaped tsz
    if esz(1) > tsz(1) && esz(2) > tsz(2)
      expr = ['sum(sum(',expr,'))'];
    elseif esz(1) > tsz(1)
      expr = ['sum(',expr,',1)'];
    elseif esz(2) > tsz(2)
      expr = ['sum(',expr,',2)'];
    end
  end

  function scatteradd(j,fldname,srcexpr)
    % adjoint scatter-add of srcexpr (a column) through linear map fldname
    ensureinit(j);
    if j == 0
      tb = vbar;
    else
      tb = bar{j};
    end
    emit([tb,'(Gator1Data.',fldname,') = ',tb,'(Gator1Data.',fldname,...
      ') + ',srcexpr,';']);
  end

% ------------------------------ header --------------------------------- %
emit(sprintf('function [%s, %s_grad] = %s(%s)',OutName,OutName,RevName,...
  strjoin(InNames,',')));
emit(['% ',RevName,' - reverse-mode (adjoint) gradient of ''',UserFun,'''']);
emit('% Generated by adigatorGenRevGradFile (roadmap R4, issue #6/#11 companion)');
emit(sprintf('%% Returns the scalar value and the %d x 1 gradient w.r.t. %s,',...
  prod(vodsize),VodName));
emit(sprintf('%% which is passed as a plain %d x %d numeric array.',...
  vodsize(1),vodsize(2)));
emit(['global ',GlobalVar]);
emit(['if isempty(',GlobalVar,'); ADiGator_LoadData(); end']);
emit(['Gator1Data = ',GlobalVar,'.',RevName,'.Gator1Data;']);
emit('% ADiGator Start Derivative Computations');
emit('% ----------------- forward (function value) sweep ----------------- %');

for k = 1:n
  ln = S(k).text;
  ln = regexprep(ln,['\<',VodName,'\.f\>'],VodName);
  if k == n
    ln = regexprep(ln,['^',OutName,'\.f\>'],OutName);
  end
  emit(ln);
  if snap(k)
    emit(sprintf('cadaRGsv%d = %s;',k,bases{k}));
  end
end

emit('% -------------------------- reverse sweep -------------------------- %');
emit(sprintf('%s = 1;',bar{n}));
init(n) = true;

for k = n:-1:1
  if ~S(k).active
    continue
  end
  cb = bar{k};
  info = S(k).info;
  switch S(k).kind
    case 'copy'
      [s,iscst] = whobar(info.src,k);
      if ~iscst
        addbar(s,cb);
      end
    case 'unary'
      [s,iscst] = whobar(info.a,k);
      if ~iscst
        a = restext(info.a,k);
        y = selftext(k);
        switch info.fun
          case 'sin',    e = [cb,'.*cos(',a,')'];
          case 'cos',    e = ['-',cb,'.*sin(',a,')'];
          case 'tan',    e = [cb,'.*(1+',y,'.^2)'];
          case 'exp',    e = [cb,'.*',y];
          case 'log',    e = [cb,'./',a];
          case 'sqrt',   e = [cb,'./(2*',y,')'];
          case 'tanh',   e = [cb,'.*(1-',y,'.^2)'];
          case 'sinh',   e = [cb,'.*cosh(',a,')'];
          case 'cosh',   e = [cb,'.*sinh(',a,')'];
          case 'asin',   e = [cb,'./sqrt(1-',a,'.^2)'];
          case 'acos',   e = ['-',cb,'./sqrt(1-',a,'.^2)'];
          case 'atan',   e = [cb,'./(1+',a,'.^2)'];
          case 'uminus', e = ['-',cb];
          otherwise,     e = cb; % uplus
        end
        addbar(s,e);
      end
    case 'binary'
      a = restext(info.a,k);
      b = restext(info.b,k);
      [sa,ca] = whobar(info.a,k);
      [sb,cbn] = whobar(info.b,k);
      switch info.op
        case '+'
          if ~ca;  addbar(sa,sumto(cb,info.lsz,info.asz2)); end
          if ~cbn; addbar(sb,sumto(cb,info.lsz,info.bsz)); end
        case '-'
          if ~ca;  addbar(sa,sumto(cb,info.lsz,info.asz2)); end
          if ~cbn; addbar(sb,sumto(['(-',cb,')'],info.lsz,info.bsz)); end
        case {'.*','*'}
          if strcmp(info.op,'*') && ~isequal(info.asz2,[1 1]) && ...
              ~isequal(info.bsz,[1 1])
            % true matrix product
            if ~ca;  addbar(sa,[cb,'*(',b,').''']); end
            if ~cbn; addbar(sb,['(',a,').''*',cb]); end
          else
            if ~ca;  addbar(sa,sumto([cb,'.*',b],info.lsz,info.asz2)); end
            if ~cbn; addbar(sb,sumto([cb,'.*',a],info.lsz,info.bsz)); end
          end
        case {'./','/'}
          y = selftext(k);
          if ~ca;  addbar(sa,sumto([cb,'./',b],info.lsz,info.asz2)); end
          if ~cbn
            addbar(sb,sumto(['(-',cb,'.*',y,'./',b,')'],info.lsz,info.bsz));
          end
        case {'.^','^'}
          if ~cbn
            error('adigator:revgrad:unsupported',...
              'power with an active exponent is not supported: %s',...
              S(k).text);
          end
          if ~ca
            addbar(sa,sumto([cb,'.*(',b,'.*',a,'.^(',b,'-1))'],...
              info.lsz,info.asz2));
          end
      end
    case 'sum'
      [s,iscst] = whobar(info.a,k);
      if ~iscst
        addbar(s,cb); % implicit expansion restores the summed shape
      end
    case 'transpose'
      [s,iscst] = whobar(info.a,k);
      if ~iscst
        addbar(s,[cb,'.''']);
      end
    case 'reshape'
      [s,iscst] = whobar(info.a,k);
      if ~iscst
        addbar(s,sprintf('reshape(%s,%d,%d)',cb,...
          info.asz2(1),info.asz2(2)));
      end
    case 'gather'
      [s,iscst] = whobar(info.a,k);
      if ~iscst
        ridx = ridx + 1;
        fld = sprintf('RIndex%d',ridx);
        RevGator.(fld) = info.map;
        if info.dups
          addbar(s,sprintf(...
            'reshape(accumarray(Gator1Data.%s,%s(:),[%d 1]),%d,%d)',...
            fld,cb,prod(info.asz),info.asz(1),info.asz(2)));
        else
          scatteradd(s,fld,[cb,'(:)']);
        end
      end
    case 'scatter'
      ridx = ridx + 1;
      fld = sprintf('RIndex%d',ridx);
      RevGator.(fld) = info.map;
      [ss,iscst] = whobar(info.src,k);
      if ~iscst
        if prod(info.srcsz) == 1 && numel(info.map) > 1
          addbar(ss,['sum(',cb,'(Gator1Data.',fld,'))']);
        else
          addbar(ss,sprintf('reshape(%s(Gator1Data.%s),%d,%d)',...
            cb,fld,info.srcsz(1),info.srcsz(2)));
        end
      end
      [sp,iscstp] = whobar(bases{k},k); % pre-state of the scattered array
      if ~iscstp
        emit(['cadaRGtmp = ',cb,';']);
        emit(['cadaRGtmp(Gator1Data.',fld,') = 0;']);
        addbar(sp,'cadaRGtmp');
      end
    case 'concat'
      for j = 1:numel(info.srcs)
        src = info.srcs{j};
        [s,iscst] = whobar(src.name,k);
        if iscst
          continue
        end
        P = find(info.codes > src.off & info.codes <= src.off+src.num);
        Sidx = info.codes(P) - src.off;
        ridx = ridx + 1;
        fldP = sprintf('RIndex%d',ridx);
        RevGator.(fldP) = P;
        ridx = ridx + 1;
        fldS = sprintf('RIndex%d',ridx);
        RevGator.(fldS) = Sidx;
        if numel(unique(Sidx)) < numel(Sidx)
          addbar(s,sprintf(...
            'reshape(accumarray(Gator1Data.%s,%s(Gator1Data.%s),[%d 1]),%d,%d)',...
            fldS,cb,fldP,prod(src.sz),src.sz(1),src.sz(2)));
        else
          ensureinit(s);
          if s == 0
            tb = vbar;
          else
            tb = bar{s};
          end
          emit([tb,'(Gator1Data.',fldS,') = ',tb,'(Gator1Data.',fldS,...
            ') + ',cb,'(Gator1Data.',fldP,');']);
        end
      end
  end
end

if ~vinit
  emit(sprintf('%s = zeros(%d,%d);',vbar,vodsize(1),vodsize(2)));
end
emit(sprintf('%s_grad = %s(:);',OutName,vbar));
emit('end');
emit('');
emit('');
emit('function ADiGator_LoadData()');
emit(['global ',GlobalVar]);
emit([GlobalVar,' = load(''',RevName,'.mat'');']);
emit('return');
emit('end');
txt = txt(1:c);
end
