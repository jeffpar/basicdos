10 defint a-z
11 let maxdivisor=2:let maxsquared=4:let advsquared=5
12 let primes=0:let printed=0
13 let dividend=2
15 let divisor=3
20 if divisor >= maxdivisor then 30
21 if dividend mod divisor = 0 then 40
22 let divisor = divisor+2:goto 20
30 print dividend;:let printed = printed+1
31 let primes=primes+1
32 if printed < 5 then 40
33 print:let printed=0
40 let dividend = (dividend+1) or 1
41 if dividend >= 32000 then 90
50 if dividend < maxsquared then 15
51 let maxdivisor = maxdivisor+1
52 let maxsquared = maxsquared+advsquared
53 let advsquared = advsquared+2
55 goto 15
90 print:print "TOTAL PRIMES < 32000: ";primes
99 end
