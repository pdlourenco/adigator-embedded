function writeFixtureFile(name, body)
%WRITEFIXTUREFILE  Write a single-input fixture function to pwd.
%
% Shared test helper. Writes `function y = <name>(x)` with the given body
% line(s) and a trailing `end` into the current folder, then rehashes so the
% function is immediately callable. `body` may be a char, a string, or a
% cellstr of lines.
if ischar(body) || isstring(body)
    body = cellstr(body);
end
fid = fopen([name,'.m'],'w');
assert(fid > 0, 'writeFixtureFile:open', 'could not create fixture %s', name);
closer = onCleanup(@() fclose(fid));
fprintf(fid, 'function y = %s(x)\n', name);
fprintf(fid, '%s\n', body{:});
fprintf(fid, 'end\n');
clear closer
rehash;
end
