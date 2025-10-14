function y = conefun(z)

H=eye(2);
g=ones(2,1);

y=H*setfun(z)-g;

end