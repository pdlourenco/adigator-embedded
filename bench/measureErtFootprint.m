function fp = measureErtFootprint(clibDir, wrapper)
%MEASUREERTFOOTPRINT  Compiled footprint of an ERT-generated derivative function.
%
%   fp = measureErtFootprint(clibDir, wrapper) compiles the Embedded-Coder
%   generated C in clibDir and returns fp.rom / fp.ram / fp.stack (bytes):
%     ROM  = .text + .rdata   (MinGW COFF: read-only data is .rdata)
%     RAM  = .data + .bss     via `size -A`
%     stack= max frame        via `gcc -Os -fstack-usage` (.su)
%
%   Measures the CORE derivative object(s) only - `<wrapper>.c` and
%   `<wrapper>_data.c` (the static index tables, where the ROM that differs
%   between modes/forms/trip-counts actually lives) - deliberately EXCLUDING the
%   lifecycle stubs (`_initialize`/`_terminate`), the `examples/` main and the
%   `interface/` MEX gateway, none of which deploy to the embedded target.
%
%   Why the compiled object and not the codegen report: the ERT static-code-
%   metrics tables silently do not populate for generated AD code (a ~574 B stub
%   vs a full report for a hand function) and GlobalVariables is empty for inline
%   mode (const tables are .rdata, not globals) - so `size`/stack on the object
%   is the reliable source (ADR-0027).
%
%   Honest-or-nothing: rom/ram/stack stay -1 (a caller renders that as an em dash
%   / skip) when the standalone gcc/size toolchain is absent, and a gcc/size
%   failure warns + returns unmeasured rather than a silent 0.
%
%   Copyright GMV.  2026-07  (extracted from derivShowcaseC's coreFootprint,
%   R17c / ADR-0027, so the R17 padding-penalty measurement shares one copy).
%   Distributed under the GNU General Public License version 3.0

fp = struct('rom',-1,'ram',-1,'stack',-1);
mingw = getenv('MW_MINGW64_LOC');
if isempty(mingw); mingw = fullfile(matlabroot,'bin',computer('arch'),'mingw64'); end
gcc  = fullfile(mingw,'bin','gcc.exe');
sizx = fullfile(mingw,'bin','size.exe');
if ~isfile(gcc) || ~isfile(sizx); return; end
inc  = fullfile(matlabroot,'extern','include');   % tmwtypes.h etc.
want = {[wrapper '.c'], [wrapper '_data.c']};
rom = 0; ram = 0; stack = 0; got = false;
for w = want
    cpath = fullfile(clibDir, w{1});
    if ~isfile(cpath); continue; end
    obj = [cpath '.o']; su = regexprep(obj,'\.o$','.su');
    % compile from the clib dir so the generated headers resolve and the .su
    % lands predictably next to the object
    cmd = sprintf('cd /d "%s" && "%s" -Os -fstack-usage -c "%s" -I"%s" -I"%s" -o "%s"', ...
        clibDir, gcc, w{1}, clibDir, inc, obj);
    [st, out] = system(cmd);
    if st ~= 0
        warning('bench:footprint','gcc failed on %s: %s', w{1}, strtrim(out));
        return   % partial measure would be misleading; report unmeasured
    end
    [sz, so] = system(sprintf('"%s" -A "%s"', sizx, obj));
    if sz ~= 0
        warning('bench:footprint','size failed on %s: %s', w{1}, strtrim(so));
        return   % symmetric with the gcc path: unmeasured, not a silent 0
    end
    got = true;
    rom = rom + sectBytes(so,{'.text','.rdata'});   % MinGW COFF: read-only is .rdata
    ram = ram + sectBytes(so,{'.data','.bss'});
    if isfile(su)
        T = string(splitlines(fileread(su)));
        for i = 1:numel(T)
            m = regexp(T(i),'\t(\d+)\t','tokens','once');
            if ~isempty(m); stack = max(stack, str2double(m(1))); end
        end
    end
end
if got; fp.rom = rom; fp.ram = ram; fp.stack = stack; end
end

function b = sectBytes(sizeOut, sects)
% sum the size column of the named sections from `size -A` output
b = 0; L = splitlines(sizeOut);
for i = 1:numel(L)
    p = regexp(strtrim(L{i}), '\s+', 'split');
    if numel(p) >= 2 && any(strcmp(p{1}, sects))
        v = str2double(p{2}); if ~isnan(v); b = b + v; end
    end
end
end
