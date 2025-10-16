par.H = eye(2);
par.g = ones(2,1);

z = adigatorCreateDerivInput([2 1],'z');
w = adigatorCreateAuxInput([2 1]);

opts.embed_mode = 'l';

adigatorGenDerFile_embedded('hessian','gapfun',{w,z},opts);

w = randn(2,1); z = randn(2,1);

gapfun(w,z)
[H,G,f] = gapfun_Hes(w,z)
[G,f] = gapfun_Grd(w,z)