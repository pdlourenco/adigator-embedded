function r = oracleHygiene(c)
%ORACLEHYGIENE  Clean error + session hygiene on a bad input (REQ-T-07).
%
% For a negative case (a deliberately malformed fixture), generation must (a)
% raise an error rather than produce a file, and (b) leave the MATLAB path
% restored, no file handles leaked, and no stray globals — the robustness
% contract of REQ-T-07, fuzzed. Skips non-negative cases.
r = struct('name','hygiene','pass',true,'skipped',false,'message','');

if ~(isfield(c.tags,'negative') && c.tags.negative)
    r.skipped = true; r.message = 'not a negative case'; return;
end

ax = adigatorCreateDerivInput(c.xsize, 'x');
p0 = path;
f0 = fopen('all');
g0 = sort(who('global'));

threw = false;
try
    adigatorGenJacFile(c.name, {ax}, struct('echo',0,'overwrite',1));
catch
    threw = true;
end

if ~threw
    r.pass = false;
    r.message = 'generation of a malformed function did not error';
elseif ~strcmp(path, p0)
    r.pass = false;
    r.message = 'MATLAB path not restored after a generation error';
elseif ~isequal(fopen('all'), f0)
    r.pass = false;
    r.message = 'file handle(s) leaked after a generation error';
elseif ~isequal(sort(who('global')), g0)
    r.pass = false;
    r.message = 'global variable(s) leaked after a generation error';
end
end
