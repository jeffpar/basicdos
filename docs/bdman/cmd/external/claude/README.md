---
layout: sheet
title: CLAUDE
permalink: /docs/bdman/cmd/external/claude/
---

{% include header.html %}

> CLAUDE [/N] [*question*]

Asks Claude a *question* and displays the answer.  With no *question*, CLAUDE prompts (with `>`) for one question after another, until an empty line.  For example (answers vary):

	CLAUDE how do I list only the BAS files on drive B:
	Use DIR with a wildcard:

	  DIR B:*.BAS

	Add /W for a wide listing.

Each question continues the conversation, so a question can refer to an earlier answer (eg, `CLAUDE how do I sort that list`).  `/N` starts a new conversation.  Answers are plain text, wrapped to fit the console (or 80 columns, when the output is redirected to a file).  To stop an answer, press CTRL-C; the next question ends that answer, without adding it to the conversation.

A *question* on the command line is limited to about 120 characters (the most a DOS command line can hold), and loses any quotation marks, since they only group words into arguments; at the `>` prompt, a question is sent as typed, and can be any length: CLAUDE reads the keys itself (so the usual line editing keys and command history aren't available), and ENTER sends the question.  BACKSPACE erases the last character, but only on the cursor's row.

### The Claude Gateway

CLAUDE doesn't run Claude itself: an IBM PC can't make the encrypted connection that Claude's API requires, so the question goes through COM2 to a gateway program on another computer, which asks Claude (using its own Claude API key) and sends the answer back.  The gateway, [gateway.js](https://github.com/jeffpar/basicdos/blob/main/tools/claude/gateway.js), is a Node.js program in the BASIC-DOS repository's tools folder, which reads the serial port's data from its standard input, and writes the answers to its standard output.  Before starting it, install the repository's packages (`npm install`), and set the `ANTHROPIC_API_KEY` environment variable to your Claude API key.

In PCjs, pc.js's `--com2` option starts the gateway and connects it to the machine's COM2:

	pc.js ibm5160 --com2="node tools/claude/gateway.js"

On a real PC, connect its COM2 port to the other computer with a null-modem cable, and connect the gateway to that computer's serial port (eg, on macOS, with a USB serial adapter and [socat](http://www.dest-unreach.org/socat/)):

	socat /dev/cu.usbserial,raw,echo=0,b9600 EXEC:"node tools/claude/gateway.js"

CLAUDE.BAS is on the BASIC-DOS diskette and hard disk, but not on the demo diskettes.  It always uses COM2 at 9600 baud, with no parity, 8 data bits, and 1 stop bit.  The gateway's options include `--model` (the default is claude-opus-5-5) and `--effort` (low, medium, high, xhigh, or max; the default is low).  The gateway includes BASIC-DOS's [HELP.TXT](../help/#helptxt) with every question, so Claude's answers about commands and statements use the BASIC-DOS versions.

### On the Demo Pages

On the [20Mb Drive](../../../../../machines/demos/bd/hd/xt/) demo pages (PC XT, PC AT, and DeskPro 386) and the [Terminal](../../../../../machines/demos/bd/term/xt/) demo's PC XT page, the page itself is the gateway: it calls Claude's API from your browser, using your own API key.  Add the key to the page's address as a fragment, after a `#` (eg, `/machines/demos/bd/hd/xt/#claudekey=sk-ant-...`), or paste it when the first question asks for it.  The page removes the fragment from the address bar right away, and keeps the key only until you close the tab; a key that Claude's API rejects is forgotten, so the next question asks again.

Browsers never send a fragment to the web server (unlike a query, such as `?key=...`), so the key doesn't appear in the server's logs.  Still, anything running in the page can see the key, so use one that you can revoke or give a spending limit.  When the first question is asked, the page loads Anthropic's JavaScript SDK from the jsDelivr CDN, and HELP.TXT from the BASIC-DOS repository on GitHub.

### Errors

If the gateway doesn't respond within 5 seconds, CLAUDE displays `Device timeout` and sets ERRORLEVEL to 24, and if the machine has no COM2, it displays `Device unavailable` and sets ERRORLEVEL to 68.  Errors that the gateway reports (eg, that it has no API key, that no key was entered on a demo page, or that Claude's API couldn't be reached) are displayed in place of the answer, and set ERRORLEVEL to 1.  An unknown switch is a [usage error](../../#usage-errors).

Source: [CLAUDE.BAS](https://github.com/jeffpar/basicdos/blob/main/src/os/util/bas/CLAUDE.BAS)

{% include footer.html prev="CHKDSK:../chkdsk/" next="COMMAND.COM:../command/" %}
