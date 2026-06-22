% This code was generated using ADiGator version 1.5
% ©2010-2014 Matthew J. Weinstein and Anil V. Rao
% ©2025 Pedro Lourenço @ GMV
% This version of ADiGator may be obtained at https://github.com/pdlourenco/adigator-embedded 
% Contact: mweinstein@ufl.edu
% Bugs/suggestions may be reported to the github issues.
%                    DISCLAIMER
% ADiGator is a general-purpose software distributed under the GNU General
% Public License version 3.0. While the software is distributed with the
% hope that it will be useful, both the software and generated code are
% provided 'AS IS' with NO WARRANTIES OF ANY KIND and no merchantability
% or fitness for any purpose or application.

function f = gapfun_ADiGatorGrd(w,z)
global ADiGator_gapfun_ADiGatorGrd
if isempty(ADiGator_gapfun_ADiGatorGrd); ADiGator_LoadData(); end
Gator1Data = ADiGator_gapfun_ADiGatorGrd.gapfun_ADiGatorGrd.Gator1Data;
% ADiGator Start Derivative Computations
cadainput3_1.dz = z.dz; cadainput3_1.f = z.f;
%User Line: cadainput3_1 = z;
cadaoutput3_1 = ADiGator_setfun(cadainput3_1);
% Call to function: setfun
zaux.dz = cadaoutput3_1.dz; zaux.f = cadaoutput3_1.f;
%User Line: zaux = cadaoutput3_1;
cadainput2_1.dz = z.dz; cadainput2_1.f = z.f;
%User Line: cadainput2_1 = z;
cadaoutput2_1 = ADiGator_conefun(cadainput2_1);
% Call to function: conefun
cada1f1 = w.';
cada1td1 = zeros(2,2);
cada1td1(Gator1Data.Index1) = cadaoutput2_1.dz;
cada1td1 = cada1f1*cada1td1;
cada1td1 = cada1td1(:);
cada1f2dz = cada1td1(Gator1Data.Index2);
cada1f2 = cada1f1*cadaoutput2_1.f;
cada1f3dz = z.dz;
cada1f3 = z.f.';
cada1td2 = zeros(2,2);
cada1td2(Gator1Data.Index3) = cada1f3dz;
cada1td2 = zaux.f.'*cada1td2;
cada1td1 = cada1td2(Gator1Data.Index4);
cada1td1 = cada1td1(:);
cada1td2 = zeros(2,2);
cada1td2(Gator1Data.Index5) = zaux.dz;
cada1td2 = cada1f3*cada1td2;
cada1td2 = cada1td2(:);
cada1td1 = cada1td1 + cada1td2(Gator1Data.Index6);
cada1f4dz = cada1td1;
cada1f4 = cada1f3*zaux.f;
cada1td1 = cada1f2dz;
cada1td1 = cada1td1 + cada1f4dz;
f.dz = cada1td1;
f.f = cada1f2 + cada1f4;
%User Line: f=w'*cadaoutput2_1 +z'*zaux;
f.dz_size = 2;
f.dz_location = Gator1Data.Index7;
end
function y = ADiGator_conefun(z)
global ADiGator_gapfun_ADiGatorGrd
Gator1Data = ADiGator_gapfun_ADiGatorGrd.ADiGator_conefun.Gator1Data;
% ADiGator Start Derivative Computations
H.f = eye(2);
%User Line: H=eye(2);
g.f = ones(2,1);
%User Line: g=ones(2,1);
cadainput3_1.dz = z.dz; cadainput3_1.f = z.f;
%User Line: cadainput3_1 = z;
cadaoutput3_1 = ADiGator_setfun(cadainput3_1);
% Call to function: setfun
cada1td1 = zeros(2,2);
cada1td1(Gator1Data.Index1) = cadaoutput3_1.dz;
cada1td1 = H.f*cada1td1;
cada1td1 = cada1td1(:);
cada1f1dz = cada1td1(Gator1Data.Index2);
cada1f1 = H.f*cadaoutput3_1.f;
y.dz = cada1f1dz;
y.f = cada1f1 - g.f;
%User Line: y=H*cadaoutput3_1-g;
end
function y = ADiGator_setfun(z)
global ADiGator_gapfun_ADiGatorGrd
Gator1Data = ADiGator_gapfun_ADiGatorGrd.ADiGator_setfun.Gator1Data;
% ADiGator Start Derivative Computations
y.dz = z.dz; y.f = z.f;
%User Line: y = z;
end


function ADiGator_LoadData()
global ADiGator_gapfun_ADiGatorGrd
ADiGator_gapfun_ADiGatorGrd = load('gapfun_ADiGatorGrd.mat');
return
end