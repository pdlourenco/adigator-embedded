function dydt = mybrussode(t,y,N)
% function dydt = mybrussode(t,y,N)
% Taken from MATLAB function brussode.m
% Derivative function
%
% Embeddability note. The grid size N is an ordinary runtime input here, and
% the state arrays are sized from it. That is fine for a host run, but it means
% this function -- on its own, before any derivative exists -- does not
% code-generate under static memory allocation, the setting an embedded target
% requires: nothing bounds N, so no array sized from it has a compile-time
% bound. Fixing the problem size makes it embeddable, e.g. by passing N as a
% coder.Constant, which is the natural configuration when the grid is decided
% at build time.
%
% Wanting ONE generated file to serve several grid sizes is a different
% question, and the obvious answer is the wrong one here: `loopbound` matches a
% declared bound against a LOOP TRIP COUNT, and this function has no loop over
% N to match. It would also be unsafe even if it did -- `loopbound` pads to
% Nmax, and padding is only benign if nothing reads the tail, whereas the
% N-derived index sets here (3:2:2*N-3, 2*N-1) would address the padded
% region (see adigatorOptions). The result would be wrong numbers at
% n < Nmax rather than an error.
%
% The mechanism that does leave a size free for vectorized code is vectorized
% mode -- see examples/optimization/vectorized/allocation/, where one generated
% file serves any N and K. Adopting it means writing the function against that
% pattern, which is a larger change than pinning the size.
c = 0.02 * (N+1)^2;
dydt = zeros(2*N,size(y,2));      % preallocate dy/dt

% Evaluate the 2 components of the function at one edge of the grid
% (with edge conditions).
i = 1;
dydt(i,:) = 1 + y(i+1,:).*y(i,:).^2 - 4*y(i,:) + c*(1-2*y(i,:)+y(i+2,:));
dydt(i+1,:) = 3*y(i,:) - y(i+1,:).*y(i,:).^2 + c*(3-2*y(i+1,:)+y(i+3,:));

% Evaluate the 2 components of the function at all interior grid points.
i = 3:2:2*N-3;
dydt(i,:) = 1 + y(i+1,:).*y(i,:).^2 - 4*y(i,:) + ...
  c*(y(i-2,:)-2*y(i,:)+y(i+2,:));
dydt(i+1,:) = 3*y(i,:) - y(i+1,:).*y(i,:).^2 + ...
  c*(y(i-1,:)-2*y(i+1,:)+y(i+3,:));

% Evaluate the 2 components of the function at the other edge of the grid
% (with edge conditions).
i = 2*N-1;
dydt(i,:) = 1 + y(i+1,:).*y(i,:).^2 - 4*y(i,:) + c*(y(i-2,:)-2*y(i,:)+1);
dydt(i+1,:) = 3*y(i,:) - y(i+1,:).*y(i,:).^2 + c*(y(i-1,:)-2*y(i+1,:)+3);
end