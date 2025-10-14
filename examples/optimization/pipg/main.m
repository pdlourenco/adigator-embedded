par.H = eye(2);
par.g = ones(2,1);

z = adigatorCreateDerivInput([2 1],'z');
w = adigatorCreateAuxInput([2 1]);

opts.embed_mode = 'c';

adigatorGenDerFile_embedded('jacobian','gapfun',{w,z},opts);