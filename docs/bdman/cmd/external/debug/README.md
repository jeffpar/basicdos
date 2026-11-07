---
layout: sheet
title: DEBUG
permalink: /docs/bdman/cmd/external/debug/
---

{% include header.html %}

> DEBUG [/H] [*program* [*arguments*]]  
> DEBUG /*command*  
> DEVICE=EXT\DEBUG.COM COM*n*:*baud*,*parity*,*databits*,*stopbits*[,*options*] [/H] [/*command*]...

DEBUG.COM is a debugger that can be used in two ways:

- [As a program](#running-debug-as-a-program), run from the prompt, it debugs a program that it loads, using the session's console
- [As a device driver](#loading-debug-as-a-driver), loaded by a line in CONFIG.SYS, it debugs the whole system (other drivers, BASIC-DOS itself, and the programs in every session), using a terminal connected to a serial port

Either way, it displays the registers and the next instruction, and then accepts [commands](#commands) at a `-` prompt.

### Running DEBUG as a Program

`DEBUG EXT\SLEEP.COM 5` loads the program without starting it (the program's name must be a full filename, including its extension, and PATH$ isn't searched), with the rest of the line as its command tail, and displays the registers as of the program's start:

	DEBUG EXT\SLEEP.COM 5
	AX=0000 BX=0000 CX=0000 DX=0000 SP=055E BP=0000 SI=0000 DI=0000
	DS=0E2F ES=0E2F SS=0E2F CS=0E2F IP=0100 NV UP EI PL ZR NA PE NC
	0E2F:0100 BE8100        MOV     SI,0081
	-

G runs the program, and when it terminates, DEBUG reports `Program terminated normally` and exits with the program's exit code.  Q ends the program and DEBUG at any time.  A change to a register before the program's first G, T, or P isn't applied, since the program always starts at its loaded entry point.

If the program can't be loaded, DEBUG displays `Unable to find` or `Unable to load` and its name (or `Invalid drive`, if its drive doesn't exist), and exits.

Without a program, the registers are DEBUG's own, and since CS:IP holds a RET, G exits; the [L](#l) command then loads a program, as if it had been named on DEBUG's command line.

A command can also be given as a switch, which DEBUG performs (without displaying the registers) before exiting; eg, `DEBUG /DB 40:0` dumps the BIOS data area, `DEBUG /DM` displays the memory map, and `DEBUG /?` lists the commands.  `/H` changes nothing, since DEBUG always halts at the prompt.

Since the console uses DOS, breakpoints in DOS itself should be set only with the driver, and INT 00h is the only vector that [VT](#vt) can trap in program mode.  CTRL-C cancels a line that's being typed at DEBUG's prompt, and while the program is running, it ends the program, and DEBUG, too.

### Loading DEBUG as a Driver

As a driver, DEBUG.COM is loaded by a [DEVICE](../../../cfg/#device) line in CONFIG.SYS.  Its first argument is the settings of the serial port that the terminal is connected to, using the same format as a COM [CON](../../../cfg/#con):

	DEVICE=EXT\DEBUG.COM COM2:9600,N,8,1,VT100

The debugger claims the port, so no other program or console can open it.  Once installed, it displays this on the terminal:

	BASIC-DOS Debugger 2.10
	CTRL-C or BREAK to stop, ? for help

Any switches after the port's settings (using the current [SWITCHAR](../../../cfg/#switchar)) are commands, which the debugger performs on the terminal as soon as it's installed, before startup continues; eg, `DEVICE=EXT\DEBUG.COM COM2:9600,N,8,1,VT100 /BP 70:100` sets a breakpoint.  Breakpoints should be set only in code that's already loaded (eg, in other device drivers or the operating system), since loading a program over one replaces it.

- `/H` stops the machine after those commands, instead of continuing startup, so that more commands can be typed (G resumes it), and makes the debugger stop at a DBGBRK, too (an INT 3 that DEBUG builds of BASIC-DOS can use to mark a spot); without `/H`, it stops only at its breakpoints, an assertion failure, an exception that VT traps or that would stop the machine, or a CTRL-C (or BREAK)
- `/G` is ignored

On the terminal, CTRL-C (or BREAK) stops the machine as soon as it arrives, as do breakpoints, single-steps, any other INT 1 or INT 3, and the exceptions that VT traps.  The debugger then displays the registers and the instruction at CS:IP (preceded by `Assertion failure` if the INT 3 was a failed assertion in a DEBUG build, `V0000: Division error` for a divide error, `V0400: Overflow error` for an overflow, or `Vvv00: CPU fault vv (EC=xxxx) at cccc:iiii` for a protected-mode fault, with its vector and error code), and waits for commands.

The driver's device name is DEBUG$, and data written to it is sent to the terminal; DEBUG builds of BASIC-DOS send their diagnostic (DPRINTF) messages there.

See the [DEBUG demo](/demos/debug/at/) for a machine with the driver loaded, and a VT100 terminal.

### Typing Commands

A command line can have up to 79 characters.  BACKSPACE (or DEL) erases a character, CTRL-C cancels the line, and any other control characters and non-ASCII keys (eg, cursor keys) are ignored.  Letters are converted to upper case, except inside quotes.  A command that isn't valid displays `?`.

All numbers in commands are hexadecimal, and any number may also be a 16-bit register name, such as DS or DX.  An *address* is [*segment*:]*offset* (eg, `DS:DX`), and a *range* is *address* [*end* \| L *count*].  Bytes that can't be read (eg, past the end of a segment) are displayed as `??`.

On an 80286 or later, when protected mode is requested (see [CPU](../../../cfg/#cpu)), the debugger works in either of the processor's modes: an *address* may start with `&` for a real-mode segment (eg, `&40:0`) or `#` for a protected-mode selector (eg, `#20:0`), and otherwise has the processor's current mode, and every address it displays starts with `&` or `#`.  On any processor, an *address* may also be any 32-bit physical address, preceded by `%` (eg, `%100000`, or on an 8088, any address below 1Mb), which D, E, LN, and U accept (but BP and G don't, since a breakpoint needs a segment).

### Commands

The L and Q commands exist only in program mode, the commands marked "Driver" exist only in the driver, and the commands marked "Not at ring 3" aren't available in program mode in [protected mode](#ring-3).  [?](#help) lists the commands that are available.

| Command | Description | Available |
|---------|-------------|-----------|
| [BC](#bc) | Clear breakpoints | Always |
| [BL](#bl) | List breakpoints | Always |
| [BP](#bp) | Set a breakpoint | Always |
| [D, DB, DW](#d-db-and-dw) | Display memory as bytes or words | Always |
| [DG](#dg) | Display the GDT, or a selector's descriptor | Driver, in protected mode |
| [DI](#di) | Display the IDT | Driver, in protected mode |
| [DL](#dl) | Display a session's LDT | Driver, in protected mode |
| [DM](#dm) | Display the memory map | Always |
| [E](#e) | Store bytes and strings in memory | Always |
| [G](#g) | Resume, optionally to an address | Always |
| [GT](#gt) | Pass on the exception that stopped the debugger | Not at ring 3 |
| [L](#l) | Load a program or disk sectors | Program mode |
| [LN](#ln) | Name the memory at an address | Not at ring 3 |
| [P, PR](#p-and-pr) | Step over an instruction | Always |
| [Q](#q) | Quit | Program mode |
| [R](#r) | Display or change the registers | Always |
| [T, TR](#t-and-tr) | Trace an instruction | Always |
| [U](#u) | Disassemble instructions | Always |
| [VC](#vc) | Clear traps | Not at ring 3 |
| [VL](#vl) | List traps | Not at ring 3 |
| [VT](#vt) | Set traps | Not at ring 3 |
| [?](#help) | List the commands | Always |
| [CTRL-A](#ctrl-a) | Repeat the last command | Always |
| [CTRL-C](#ctrl-c) | Stop a command's output | Driver |

#### BC

> BC *n* [*n*...]  
> BC \*

Clears the listed breakpoints (0 is the temporary one), or with `*`, all of them.

#### BL

> BL

Lists the breakpoints, including the temporary one (0), with the instruction at each:

	-BL
	1 0E2F:0111 7217          JB      012A
	5 0E2F:0120 E303          JCXZ    0125

#### BP

> BP [*n*] *address*

Sets breakpoint *n* (1-9, or 0 for the temporary breakpoint), or the first free one (1-9), at *address*, whose default segment is CS.  If none is free, BP displays `?`.  Breakpoints are stored in memory only while the machine is running, so they don't appear in what D or U displays.

#### D, DB, and DW

> DB [*range*]  
> DW [*range*]  
> D [*range*]

DB displays memory as hex bytes, and DW as hex words; D uses the last format (initially bytes).  They display 128 bytes by default, continuing from the last D; the default segment is DS as of the last stop.  Each row has up to 16 bytes, starting at a multiple of 16 (or for words, one more than a multiple of 16, if that keeps each word whole), and ends with the same bytes as characters, with a period for each byte outside 20h-7Eh.

	-DB 40:0 L20
	0040:0000 F8 03 F8 02 00 00 00 00-00 00 00 00 00 00 00 00  ................
	0040:0010 61 04 A0 80 02 00 00 00-00 00 1E 00 1E 00 00 00  a...............
	-DW CS:100 L10
	0E2F:0100 81BE AC00 203C FB74 093C F774 B44E CD0B  ....< t.<.t.N...

#### DG

> DG [*selector*]

Displays the entries of the GDT that are in use (those that are present, other than the interrupt and trap gates of the IDT, which the GDT's limit also covers), each as its selector, a colon, and what its descriptor holds, as the PCjs Debugger's DS command does: its base and limit (or for a gate, its selector, offset, and parameter count), its type and what that means, the 80386 flags in its extended byte, and its DPL.  It then displays the number of entries in use, the number of entries, and the size of the table in bytes (all in hex).

With a *selector*, which can be a register name (eg, `DG ES`), it displays just that entry, without the totals, whichever table it's in: an LDT selector is in the LDT of the session that was interrupted (use [DL](#dl) for another session's).  The entry's selector is displayed with its low 2 bits (the RPL) cleared.  An entry that isn't in use, or isn't in the table, displays `?`.  DG exists only in the driver, and only in protected mode.

	-DG 60
	0060: seg=0058 off=00C0 cnt=00 type=04 (call gate) ext=0000 dpl=03

#### DI

> DI [*vector*]

Displays the entries of the IDT that are in use, or just the one for *vector*, as [DG](#dg) does, with the vector in place of a selector.

	-DI 21
	0021: seg=0188 off=06D8 cnt=00 type=06 (int gate286) ext=0000 dpl=03

#### DL

> DL [*session* [*selector*]]

Without arguments, lists each session with a program: its number, its console, and its program, with `*` beside the session that was interrupted, if it has any LDT entries.  These are the same session numbers that [KILL](../../system/#kill) displays, starting at 1, but in hex, as all of DEBUG's numbers are (eg, 0A for KILL's session 10).  They're each 1 more than the session number in a [DM](#dm) owner (eg, 8000 for the first session's COMMAND.COM).

Otherwise, displays the entries of a session's LDT that are in use, or just the one for *selector*, as [DG](#dg) does (*session* is in hex).  An LDT holds only the selectors of the ring 3 programs in its session, so a session whose programs all run at ring 0 (with `RING=0`) has no entries.  A number from 1 to 20 (hex) that isn't in the list displays nothing, and any other number displays `?`.

	-DL
	 01 VKD$     COMMAND
	*02 VKD$     COMMAND
	-DL 1
	0004: base=00100000 limit=B22F type=13 (data,writable,accessed) ext=0000 dpl=03
	000C: base=00100000 limit=B22F type=1B (code,readable,accessed) ext=0000 dpl=03
	0002 of 0020 entries in use, 0100 bytes

#### DM

> DM

Displays memory in address order, as the CPU$ driver describes it: each block's address, length (in bytes), and owner (a PSP, or in protected mode, a ring 3 program's session number plus 80h, then its program number; eg, 8000 for session 0's COMMAND.COM), and its name (eg, COMMAND, DEBUG, or DEBUG$) or type (eg, FREE, SYS, RSVD for video memory and ROMs, CPU$ for the CPU$ system area at the top of conventional memory, one of COMMAND's VAR, STR, TEXT, or CODE blocks (CODE also being the copy of itself that DEBUG runs at ring 3), ENV for the environment COMMAND builds for programs, or DATA for any other memory a program allocated).  The system's memory is shown as a row for each driver in it (eg, CPU$, VKD$, or FDC$, from the driver chain), DOS for the memory DOS is in, and SYS for the rest, including, on an 8088 (or with [CPU](../../../cfg/#cpu)=8088), the memory below the blocks (the interrupt vectors, the BIOS data, and BASIC-DOS's low memory).  A driver loaded by a DEVICE line owns its block, which is named after its device (eg, DEBUG$) once the driver has been initialized; until then (eg, at a `/H` stop), the block is still SYS.

As a program at [ring 3](#ring-3), DEBUG gets the blocks from DOS, and reads the driver chain by address, so it displays the same rows.

	-DM
	Addr   Length Own  Name
	000000 000970 0008 <SYS>
	000970 000510 0008 CPU$
	000E90 000020 0008 NUL
	000EB0 000CA0 0008 COM1
	001B50 000050 0008 COM2
	001BA0 0003F0 0008 CLOCK$
	001F90 0008A0 0008 FDC$
	002830 0001F0 0008 PIPE$
	002A20 0017A0 0008 FPU$
	0041D0 005B70 0008 <DOS>
	009D50 0001B0 0008 <SYS>
	009F10 001090 09F1 COMMAND
	00AFB0 003330 0AFB DEBUG
	00E2F0 091C50 0000 <FREE>
	09FF50 0000B0 09F1 <ENV>

#### E

> E *address* [*list*]

Stores a list of bytes and quoted strings (with `"` or `'`) at *address*, whose default segment is the one that D would use (eg, `E 200 "Hi" 21`).  Without a list, E displays each byte and prompts for its replacement, which can be a list, too; an empty line ends.

#### G

> G [*address*]

Resumes, after setting the breakpoints.  An *address* (whose default segment is CS) sets the temporary breakpoint (0) there, replacing any earlier one (see [P](#p-and-pr)), and the temporary breakpoint stays set until the debugger stops at its address, however it gets there.

#### GT

> GT

Passes on the exception that stopped the debugger (see [Exceptions and Faults](#exceptions-and-faults)).  If an exception didn't stop it, GT displays `?`.

#### L

> L *program* [*arguments*]  
> L *drive*: *sector* *count* *address*

Available only in program mode.  The first form loads a program, if none is loaded, as if it had been named on DEBUG's command line.  If it can't be loaded, the error is displayed, and DEBUG stops again, with no program.

The second form reads disk sectors, whether or not a program is loaded (eg, `L A: 0 1 2000:0`): it opens the drive for reading, reads *count* 512-byte sectors, starting at logical sector *sector* of the drive's volume (0 is its boot sector), into memory at *address*, and closes the drive.  As with E, an *address* without a segment uses DS, which is DEBUG's own without a program, so choose an address that's free.  `Invalid drive` means that there's no such drive, and `Unable to read A:` means that the drive couldn't be opened (eg, a file on it is open for writing) or a sector couldn't be read (eg, it's past the end of the volume), in which case any earlier sectors have been stored.  An empty drive displays the usual `Abort, Retry, Fail?` prompt first.  An invalid *count* or *address* (eg, sectors that wouldn't fit in the segment) displays `?`.

#### LN

> LN [*address*]

"List near" displays *address* (CS:IP by default), its linear address, and the name of the memory it's in, as DM shows it (eg, `0E2F:0106 00E3F6 SLEEP`).

#### P and PR

> P [*count*]  
> PR [*count*]

Steps as T (or TR) does, except that a CALL, INT, LOOP (or LOOPZ or LOOPNZ), or string instruction with a REP prefix (eg, REP MOVSB) runs to completion: P sets the temporary breakpoint after it (or for an INT 2Bh that prints, after the format string that follows it, as the PRINTF macro stores it) and resumes, with the other breakpoints set, too (so a stop at another one ends the P, and the temporary breakpoint stays set).

#### Q

> Q

Available only in program mode.  Ends the loaded program, if any, and exits.

#### R

> R  
> R *reg* [*value*]  
> R F

R displays the registers, and the instruction at CS:IP, followed, if it has a memory operand, by the operand's effective address, using any segment override (eg, `; EA = 0AC6:0120`).  On an 80286 or later, when protected mode is requested (see [CPU](../../../cfg/#cpu)), it also displays the MSW, GDTR, and IDTR.  In protected mode, it uses the PCjs Debugger's format: each segment register's base and limit, as `[base,limit]`, A20, the LDTR, GDTR, IDTR, TR, MSW, and the flags as 0 or 1, eg, `Z1`:

	-R
	AX=1000 BX=00A6 CX=4FB0 DX=0128 SP=57FB BP=580D SI=2463 DI=580D
	DS=0178[00CEC0,2A2F] ES=0130[089890,FFFF] SS=0130[089890,FFFF] A20=ON
	CS=0180[00CEC0,2A2F] LD=0010[0928E0,02FF] GD=[0900E0,F807] ID=[0908E0,07FF]
	TR=0068 MS=FFF1 PS=0246 V0 D0 I1 T0 S0 Z1 A0 P1 C0
	#0180:237F 803E1F2448   CMP     BYTE PTR [241F],48	; EA = #0178:241F

R *reg* changes a register (AX, BX, CX, DX, SP, BP, SI, DI, DS, ES, SS, CS, or IP), displaying it and prompting if there's no *value*; an empty line leaves it unchanged.

R F displays the flags and prompts for new flag names (eg, `CY ZR`).  An empty line leaves them unchanged.

| Flag | Clear | Set |
|------|-------|-----|
| Overflow | `NV` | `OV` |
| Direction | `UP` | `DN` |
| Interrupt | `DI` | `EI` |
| Sign | `PL` | `NG` |
| Zero | `NZ` | `ZR` |
| Auxiliary carry | `NA` | `AC` |
| Parity | `PO` | `PE` |
| Carry | `NC` | `CY` |

#### T and TR

> T [*count*]  
> TR [*count*]

Executes *count* instructions (default 1), displaying the next instruction after each (TR displays the registers, too, as R does).  Like DEBUG, T steps into an INT by simulating it, except that it steps over an INT 3 (or any other INT the debugger handles itself), as if it had returned; an INT that VT can report (eg, INT 13h) goes straight to its previous handler, without a report.

#### U

> U [*range*]

Disassembles instructions as the processor runs them: 80286 instructions on an 80286 or later (even in real mode), and 8086 instructions on an 8088 or 8086 (where, for example, opcode 0Fh is POP CS).  U displays 32 bytes by default, continuing from the last U, or from CS:IP.  An INT 2Bh that prints (eg, from the PRINTF macro) is followed by a tab, a semicolon, and its format string in quotes (with `\r`, `\n`, `\t`, or `\x`*nn* for each character that isn't printable), and the next instruction starts after the string.

	-U
	0E2F:0100 BE8100        MOV     SI,0081
	0E2F:0103 AC            LODSB
	0E2F:0104 3C20          CMP     AL,20
	0E2F:0106 74FB          JZ      0103

#### VC

> VC *number* [*number*...]  
> VC \*

Clears the listed traps (see [VT](#vt)), or with `*`, all of them.

#### VL

> VL [*vector*]

Lists the vectors that VT can trap, or only what belongs to one *vector* (hex, or decimal with a trailing period), with `*` before whatever it's trapping, and what each one is.  INT 13h and INT 21h get one line each, with `*` if any of their functions is trapped, and `VL 13` or `VL 21` lists those functions.  In real mode, only exceptions 00 and 04 reach the debugger, and the other exceptions occur only in protected mode.

	-VL
	  00:   Division error
	  02:   Nonmaskable interrupt
	  04:   Overflow error
	  06:   Invalid opcode
	  07:   No coprocessor
	  08:   Double fault
	  09:   Coprocessor overrun
	  0A:   Invalid TSS
	  0B:   Segment not present
	  0C:   Stack fault
	* 0D:   General protection
	* 13:   BIOS disk functions (see VL 13)
	  21:   DOS functions (see VL 21)
	-VL 13
	* 1302: BIOS disk reads
	  1303: BIOS disk writes

#### VT

> VT *number* [*number*...]

Traps what VL lists: an exception's vector (hex, or decimal with a trailing period; eg, `VT 0D` or `VT 13.`), so that it stops the debugger instead of being passed on (see [Exceptions and Faults](#exceptions-and-faults)), or a software interrupt's function (eg, `VT 1302`), so that each call is reported (see [Function Reports](#function-reports)).  A vector that has functions in the list selects all of them (eg, `VT 21` for all of INT 21h's functions, or `VT 13` for INT 13h's), and `VC` accepts the same numbers.

#### ? {#help}

> ?

Lists the commands that are available.

#### CTRL-A

At an empty prompt, CTRL-A displays the last command and performs it again, so pressing CTRL-A repeatedly repeats a command (eg, T or P).

#### CTRL-C

In the driver, CTRL-C (or a BREAK) while a command is displaying something stops the command and returns to the prompt (eg, a long D, U, or [DI](#di), or a T or P with steps remaining), even if the terminal has paused the output with XOFF.  Anything else typed since the command started is discarded.  While the system is running, CTRL-C stops it and displays the prompt, as usual.

### Exceptions and Faults

An exception (eg, a divide error, or in protected mode, a general protection fault) is passed on to DOS, which ends the program (as it would without the debugger), unless VT traps its vector.  After a trapped exception, GT passes it on, since resuming would only run the instruction again (eg, a DIV, on an 80286 or later; an 8086 or 8088 reports the instruction after the DIV instead), while T, P, and G resume at CS:IP (eg, after changing IP with R).

A protected-mode fault that DOS can't handle (one outside the current program's own code, eg, in a driver or the operating system) would stop the machine, so the debugger stops for it first, whether or not VT traps it: G runs the instruction again (eg, after you fix the problem), and GT has the system report the fault and stop (`System halted`).  The debugger then keeps control, displaying the fault and `System halted`, and waits for CTRL-C (or BREAK) before displaying the registers and its prompt; G, P, and T then resume at CS:IP (eg, after you fix the problem), and GT keeps the system halted (the debugger displays the fault and `System halted` and waits again), so the debugger never gives up control.  Fixing the problem (eg, the register that the faulting instruction uses) is safer than skipping the code that faulted, which can leave the system in an inconsistent state.

### Function Reports

A software interrupt function that VT traps doesn't stop the machine: the driver displays a report on the terminal as each call is made, with values from the caller's registers (in hex), and the call then proceeds as usual.  Each report starts with `Vxxyy:`, where *xx* is the interrupt and *yy* is the function, as the messages for trapped exceptions do, with 00 for *yy*.

`VT 1302` and `VT 1303` report INT 13h's functions 02h and 03h, disk reads and writes, with the drive, the number of sectors, the cylinder, head, and sector, and the address of the buffer (eg, `V1302: Disk 00 reading 09 sectors at 0008:01:01 into 0D19:3300` or `V1303: Disk 00 writing 01 sectors at 0000:00:06 from 0A88:0010`).  In protected mode, the address is the one that BASIC-DOS gives the ROM, which isn't the program's own (eg, `0040:3AFE` for a diskette).

INT 21h's file functions are reported as shown below (eg, `V213D: DOS Open "A:\CONFIG.SYS"`).  Names are in quotes, and an FCB's name is shown with its drive, unless that's the default drive (eg, `"A:FOO.TXT"`), for an extended FCB, too.  A name is empty if its address isn't valid, and a name that would reach column 68 is cut off, so that a report fits on one line.  Reports include the calls that BASIC-DOS itself makes (eg, opening a program to load it), which can repeat a name.  While any INT 21h function is trapped, every DOS call is slower, until VC clears the trap.

| Number | Report (values in hex) |
|--------|------------------------|
| 210F, 2110 | `FCB Open` or `FCB Close` *"name"* |
| 2111, 2112 | `FCB FindFirst` or `FCB FindNext` *"name"* |
| 2113, 2116 | `FCB Delete` or `FCB Create` *"name"* |
| 2114, 2115 | `FCB SeqRead` or `FCB SeqWrite` *"name"* `at` *block*`:`*record* `size` *recordsize* |
| 2117 | `FCB Rename` *"name"* `to` *"newname"* |
| 2121, 2122 | `FCB RandRead` or `FCB RandWrite` *"name"* `at` *record* `size` *recordsize* |
| 2123 | `FCB Size` *"name"* `size` *recordsize* |
| 2124 | `FCB SetRandom` *"name"* `at` *block*`:`*record* `size` *recordsize* |
| 2127, 2128 | `FCB BlockRead` or `FCB BlockWrite` *"name"* *count* `records at` *record* `size` *recordsize* |
| 2139, 213A, 213B | `DOS MkDir`, `DOS RmDir`, or `DOS ChDir` *"name"* |
| 213C | `DOS Create` *"name"* `attr` *attributes* |
| 213D, 2141 | `DOS Open` or `DOS Delete` *"name"* |
| 213E | `DOS Close #`*handle* |
| 213F, 2140 | `DOS Read` or `DOS Write #`*handle* *count* `bytes at` *segment*`:`*offset* |
| 2142 | `DOS Seek #`*handle* `to` *high*`:`*low* `from` *method* |
| 2143 | `DOS Attr` *AL* *"name"* `attr` *attributes* (AL is 0 to get them, and 1 to set them) |
| 2144 | `DOS IOCTL #`*handle* `func` *AL* *CX* *DX* |
| 214E | `DOS FindFirst` *"name"* `attr` *attributes* |
| 214F | `DOS FindNext` |
| 2156 | `DOS Rename` *"name"* `to` *"newname"* |
| 2157 | `DOS FileTime` *AL* `#`*handle* *CX* *DX* (AL is 0 to get the time and date, which CX and DX then don't hold, and 1 to set them) |

Each report shows the call as it's made, before DOS has acted on it, so it doesn't show the result, and values that DOS returns (eg, an FCB's file size) aren't known yet.

Interrupts are disabled while a report is sent, so a slow terminal can make the system lose clock ticks.

### Ring 3 {#ring-3}

In protected mode, DEBUG.COM run from the prompt runs at ring 3, as other programs do (unless CONFIG.SYS has [RING](../../../cfg/#ring)=0), and so does the program it loads, so it can't use the CPU$ driver, and it has fewer commands than the driver: it can write only memory that a ring 3 program can (eg, the program's own memory, including its code, but not DOS's, the drivers', or the BIOS data area), though it can also read any selector in the GDT whose memory is below 1Mb (eg, `D 40:0`), R displays the registers as it does in real mode (with no system registers, or segment bases and limits), and there's no GT, LN, VC, VL, or VT, and no `&`, `#`, or `%` addresses.  T steps over an INT instruction, as P does, since the INT's handler runs at ring 0.  The driver has none of these limits, and can debug ring 3 programs, too.

Source: [dbgdev.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/dd/dbg/dbgdev.asm), [dbgvec.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/dd/dbg/dbgvec.asm), [dbgdis.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/dd/dbg/dbgdis.asm), and [dbginit.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/dd/dbg/dbginit.asm)

{% include footer.html prev="COMP:../comp/" next="DISKCOPY:../diskcopy/" %}
