function error_restore_path(original_path,msg) % always restore path when issuing an error
% v1.5 - restore the path to its original state, then re-raise the error.
% M5: raise under the fork's adigator:* id (the load-bearing fix) - `error(msg)`
% raised with an EMPTY identifier, so callers could not catch it by id. The '%s'
% format is defensive: single-arg `error(msg)` is already literal in current
% MATLAB (a composed message with Windows '\' or a literal '%' is NOT treated as
% a printf template), but '%s' keeps it literal on runtimes that do interpret it
% (e.g. Octave) and guards against future multi-arg misuse.
path(original_path);
error('adigator:generationError','%s',msg);
end