function f=gapfun(w,z)

zaux = setfun(z);
f=w'*conefun(z) +z'*zaux;

end