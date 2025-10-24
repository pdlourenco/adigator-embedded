function error_restore_path(original_path,msg) % always restore path when issuing an error
% v1.5 - restore the path to its original state
path(original_path);
error(msg);
end