% This file uses both MATLAB finite differences as well as adigator in order
% to compute derivatives of the arrowhead function. User can change N to
% see the effects of increasing problem size.
% Copyright 2011-2014 Matthew J. Weinstein and Anil V. Rao
% Distributed under the GNU General Public License version 3.0
clc; clear;
fprintf ('AdiGator example: %s\n', mfilename ('fullpath')) ;
N = 100;
numeval = 20;
x = rand(N,1);
% ------------------------------ ADiGator ------------------------------- %

opts = adigatorOptions();

opts.path = 'generated';
opts.overwrite = 1;

gx = adigatorCreateDerivInput([N, 1],'x'); % Create Deriv Input
genout = adigatorGenJacFile('arrowhead',{gx},opts);
% v2.0 (#192, ADR-0030): CSC is the sole pattern metadata; reconstruct the
% sparse pattern from it for the timing/plots below.
S = adigatorCSCToSparse(genout.JacobianCSC, ones(genout.JacobianCSC.Nnz,1));

addpath(fullfile(pwd,opts.path));
tic;
for i = 1:numeval
  [Jac,y] = arrowhead_Jac(x);
end
adigatortime = toc/numeval;
rmpath(fullfile(pwd,opts.path));

% -------------------------- Finite Differences ------------------------- %
TOL = 1e-8;% Can change this to make numjac more/less accurate
tic
for i = 1:numeval
  dfdx = numjac(@arrowhead4numjac,0,x,y,TOL*ones(N,1),[],0);
end
fdtime = toc/numeval;

display(['Average deriv eval time using Finite Differences:           ',num2str(fdtime)]);
display(['Average deriv eval time using ADiGator:                     ',num2str(adigatortime)]);

xs.f = x;
xs.dx = ones(N,1);
