	' CLAUDE.BAS: asks Claude a question
	'
	'   CLAUDE [/N] [question]
	'
	' Sends the question to the gateway on COM2 (tools/claude/gateway.js)
	' and displays the answer; with no question, prompts for questions (of
	' any length) until an empty line.  /N starts a new conversation.
	' Options start with the switch char (W$).  Protocol (see gateway.js):
	' ENQ/ACK, then columns (C), NEW (M$), CR, question, EOT; each answer
	' chunk ends with ETB (reply ACK) or EOT, and a NAK starts an error
	' message (E = 1).
	'
	DEFINT A-Z
	DOS &H3700 : W$ = CHR$(DOS(3) AND 255)
	I = 1 : A$ = ARG$(1)
	WHILE A$ <> ""
	IF UCASE$(A$) = W$ + "N" THEN M$ = " NEW" : GOTO 10
	' Any other option is an error
	IF LEFT$(A$, 1) = W$ THEN GOTO 990
	Q$ = Q$ + " " + A$
10	I = I + 1 : A$ = ARG$(I)
	WEND
	Q$ = MID$(Q$, 2)
	' Lines fit the console, or 80 columns if the output isn't a console
	C = 80
	ON ERROR GOTO 910
	DOS &H44D1, 1 : C = DOS(3) AND 255
20	ON ERROR GOTO 900
	OPEN "COM2:9600,N,8,1" AS #1
	IF Q$ <> "" THEN GOSUB 100 : PRINT #1, Q$; CHR$(4); : GOSUB 200 : CLOSE : END E
	' A question can be any length: keys are echoed as typed, and when Q$
	' fills, its first 128 characters go to the gateway (so BACKSPACE can
	' erase at least 127, but only on the cursor's row); N counts them all
30	GOSUB 100 : PRINT "> "; : N = 0
40	K$ = INPUT$(1) : K = ASC(K$)
	IF K = 13 THEN 50
	' An extended key (a null and a scan code) is ignored
	IF K = 0 THEN K$ = INPUT$(1) : GOTO 40
	IF K <> 8 AND K <> 127 THEN 45
	IF Q$ <> "" AND POS(0) > 1 THEN Q$ = LEFT$(Q$, LEN(Q$) - 1) : N = N - 1 : PRINT CHR$(8); " "; CHR$(8);
	GOTO 40
45	IF K < 32 THEN 40
	PRINT K$; : Q$ = Q$ + K$ : N = N + 1
	IF LEN(Q$) = 255 THEN PRINT #1, LEFT$(Q$, 128); : Q$ = MID$(Q$, 129)
	GOTO 40
50	PRINT : IF N = 0 THEN CLOSE : END E
	PRINT #1, Q$; CHR$(4); : Q$ = "" : GOSUB 200 : PRINT : GOTO 30
100	' Start a question (waiting at most 5 seconds for the ACK)
	PRINT #1, CHR$(5); : T = TIMER
110	IF LOC(1) THEN 120
	IF ABS(TIMER - T) < 5 THEN 110
	GOTO 920
120	IF INPUT$(1, #1) <> CHR$(6) THEN 110
	PRINT #1, C; M$; CHR$(13); : M$ = ""
	RETURN
	' Display the answer
200	L = LOC(1) : IF L = 0 THEN 200
	R$ = INPUT$(L, #1) : B = ASC(RIGHT$(R$, 1))
	K = INSTR(R$, CHR$(21))
	IF K THEN E = 1 : R$ = LEFT$(R$, K - 1) + MID$(R$, K + 1)
	IF B = 4 OR B = 23 THEN R$ = LEFT$(R$, LEN(R$) - 1)
	PRINT R$;
	IF B = 23 THEN PRINT #1, CHR$(6);
	IF B <> 4 THEN 200
	RETURN
900	' Report a runtime error, whose number (ERR) is the exit code
	CLOSE
	IF ERR = 68 THEN PRINT "Device unavailable" : END ERR ' BERR_NODEVICE
	PRINT "Unable to reach Claude" : END ERR
910	RESUME 20
920	' The gateway didn't answer
	CLOSE
	PRINT "Device timeout" : END 24 ' BERR_TIMEOUT
990	END 80 ' BERR_USAGE
