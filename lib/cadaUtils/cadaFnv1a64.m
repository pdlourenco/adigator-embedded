function h = cadaFnv1a64(str)
%CADAFNV1A64  FNV-1a, 64-bit, as 16 lower-case hex digits (issue #200).
%
%   h = cadaFnv1a64('foobar')   ->  '85944171f73967e8'
%
% Split out of cadaGenerationStamp so it can be pinned against the published
% FNV-1a test vectors. That matters more than it looks: a generation id is
% self-consistent no matter what this function computes, so a wrong basis, a
% wrong prime, a truncating multiply or a byte-order slip would all still yield
% stable-looking 16-hex-digit ids and pass every behavioural test around them.
% Only a known-answer check can tell "this is FNV-1a" from "this is a hash".
%
% One real trap sits in the constants. MATLAB parses a numeric literal as a
% double first UNLESS it is written directly inside an integer conversion, and
% the offset basis 0xCBF29CE484222325 lives where the double ULP is 2048 - so
% the same value reached through any double-valued intermediate silently loses
% its low 11 bits. `uint64(14695981039346656037)` is exact; assigning it via a
% variable, or computing it, need not be. Verified by UGenerationStampTest.
%
% Determinism across releases and platforms is the whole requirement, so the
% input is encoded as UTF-8 explicitly rather than left to the platform default.
%
% COST. This is a per-byte MATLAB loop, so it is slow in absolute terms and the
% quantity that governs it is the DEPENDENCY-CLOSURE SOURCE, not the size of
% the generated artifact. Measured 2026-08-04, R2024a / PCWIN64, by timing
% cadaGenerationStamp over file lists under examples/: 242 kB/s; a typical
% single-function closure (5 files, ~7 kB) costs 0.027 s per stamp, and an
% artificial 460 kB closure costs 1.9 s. Immaterial against generation time at
% realistic sizes. If a pathological closure ever makes it matter, inlining
% mul64's five operations into the loop is the cheap first move.
%
%   Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General
%   Public License version 3.0.

b  = uint64(double(unicode2native(char(str), 'UTF-8')));
hv = uint64(14695981039346656037);      % 0xCBF29CE484222325, exact as written
pr = uint64(1099511628211);             % 0x100000001B3, well under 2^53
for k = 1:numel(b)
    hv = bitxor(hv, b(k));
    hv = mul64(hv, pr);
end
h = lower(dec2hex(hv, 16));
end

%% ---------------------------------------------------------------------- %%
function z = mul64(a, b)
% 64-bit multiply with WRAPAROUND, in 32-bit halves: MATLAB saturates uint64
% arithmetic rather than wrapping it, so a*b directly would peg at intmax and
% every subsequent round would be lost.
%
% NOT a general-purpose 64x64 multiply, and the safety is a property of the
% CALLER rather than of this function. The intermediate lo*hb + hi*lb + carry is
% exact only because `b` here is always the FNV prime: with low32 = 435 and
% high32 = 256 it is bounded by
%
%     (2^32-1)*256 + (2^32-1)*435 + 434 = 2967822401279     (42 bits)
%
% THE CEILING THAT BINDS IS 2^64, not 2^53. Every operand here is uint64 (the
% bitand/bitshift results are), so the arithmetic is exact integer arithmetic up
% to intmax('uint64') and SATURATES past it - it does not wrap, which is the
% whole reason this function exists. 2^53 is the double-exactness limit and does
% not apply: nothing on this path is a double, since the only double in the file
% is the per-byte conversion in the caller, which is immediately narrowed to
% uint64. 42 bits clears both by a wide margin, but the risk being excluded is
% uint64 saturation.
%
% Reached with any larger multiplier the intermediate saturates instead of
% wrapping, and because MATLAB saturates SILENTLY the result would still look
% like a plausible hash. Do not lift this out of here.
lo = bitand(a, uint64(4294967295)); hi = bitshift(a, -32);
lb = bitand(b, uint64(4294967295)); hb = bitshift(b, -32);
z0 = lo*lb;
z1 = bitand(lo*hb + hi*lb + bitshift(z0, -32), uint64(4294967295));
z  = bitor(bitshift(z1, 32), bitand(z0, uint64(4294967295)));
end
