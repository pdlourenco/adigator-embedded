% =====================================================================
% DEPRECATED EXAMPLE -- demonstrates the inherited-upstream
% adigatorGenFiles4* solver wrappers (ADR-0037).
%
% This family is shipped for CONTINUITY with the upstream repository only.
% It is NOT maintained, and its functionality may be REDUCED OR REMOVED in
% a future release without a further deprecation period.
%
% The wrappers emit HOST-ONLY derivative files, so -- unlike every other
% example here -- this one is NOT expected to be embeddable: it is exempt
% from the rule the other examples are held to, that the differentiated
% user function must itself code-generate under the strict embedded
% profile (adigatorCoderConfig). It still runs.
%
% Writing new code? Use the core generators (adigatorGenJacFile,
% adigatorGenHesFile, adigatorGenDerFile_embedded) and build the
% solver-shaped wrapper yourself. See ADR-0037 and issue #156.
% =====================================================================
% In this example we use MATLAB's fmincon function to solve the objective
% function in the file objfun.m with the inequality constraints in function
% confun.m.
% This calls the function adigatorGenFiles4Fmincon to generate derivative
% files.
% If the user does not have MATLAB's optimization package
% installed, then fmincon will not be called, but the derivative file
% creation will still be performed.
% Copyright 2011-2014 Matthew J. Weinstein and Anil V. Rao
% Distributed under the GNU General Public License version 3.0
fprintf ('AdiGator example: %s\n', mfilename ('fullpath')) ;
clear all
xi = [-1,1];
solveflag = exist('fmincon','file');
% --------------------- Call adigatorGenFiles4Fmincon ------------------- %
setup.order = 2;
setup.numvar = 2;
setup.objective  = 'objfun';
setup.constraint = 'confun';

adifuncs = adigatorGenFiles4Fmincon(setup);

if solveflag
  % ------------------- Solve Without Derivatives ----------------------- %
  tic;
  options = optimset('Algorithm','interior-point','Display','iter');
  [x0,fval0] = ...
    fmincon(@objfun,xi,[],[],[],[],[],[],@confun,options);
  time0 = toc;
  
  % ------------------- Solve With 1st Derivatives ---------------------- %
  tic;
  options = optimset('Algorithm','interior-point');
  options = optimset(options,'GradObj','on','GradConstr','on','Display','iter');
  [x1,fval1] = fmincon(adifuncs.objgrd,xi,[],[],[],[],[],[],...
    adifuncs.consgrd,options);
  time1 = toc;
  
  % ------------------- Solve With 2nd Derivatives ---------------------- %
  tic;
  options = optimset('Algorithm','interior-point',...
    'Display','iter','GradObj','on','GradConstr','on',...
    'Hessian','user-supplied','HessFcn',adifuncs.hessian);
  [x2,fval2] = fmincon(adifuncs.objgrd,xi,[],[],[],[],[],[],...
    adifuncs.consgrd,options);
  time2 = toc;
  
  % -------------------- Display Solve Times ---------------------------- %
  fprintf(['Solve time using no derivatives',...
    ':  ',num2str(time0),'\n'])
  fprintf(['Solve time using 1st derivatives',...
    ': ',num2str(time1),'\n'])
  fprintf(['Solve time using 2nd derivatives',...
    ': ',num2str(time2),'\n'])
end
