@echo off
defint a-z
let primes = 0
let printed = 0
let dividend = 2
let maxdivisor = 2
let maxsquared = 4
let advsquared = 5

15 let divisor = 3

20 if divisor >= maxdivisor then goto 30
if dividend mod divisor = 0 then goto 40
let divisor = divisor + 2
goto 20

30 print dividend;
let primes = primes + 1
let printed = printed + 1
if printed < 5 then goto 40
print
let printed = 0

40 let dividend = (dividend + 1) or 1
if dividend >= 32000 then goto 90
if dividend < maxsquared then goto 15
let maxdivisor = maxdivisor + 1
let maxsquared = maxsquared + advsquared
let advsquared = advsquared + 2
goto 15

90 print
print primes
