function y=gapfun(w,z)

zaux = setfun(z);
y=w'*conefun(z) +z'*zaux;

end