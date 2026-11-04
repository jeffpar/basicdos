---
layout: sheet
title: SED
permalink: /docs/bdman/cmd/external/sed/
---

{% include header.html %}

> SED [/I] [/N] *script* [*file*]

A [filter](../#filters) that runs the commands in *script* on each line of input (or *file*), and then displays the line, unless `/N` is given, like a simple version of the UNIX `sed` command (eg, `DIR | SED s/BAS/BAK/`).

- `/I` ignores case when matching
- `/N` displays only what the commands display

As with FIND's *string*, *script* needs quotes only if it contains spaces or starts with the switch character (eg, `DIR | SED "/^D/d"`), and it can be a string variable.  Also quote the script if it contains other characters that BASIC-DOS treats specially (eg, `|`, `>`, `:`, or `'`); it can't contain a double quote.

### Commands

The commands in a script are separated by semicolons, and each has the form:

	[address[,address]][!]command

A command with no address applies to every line, a command with one address applies to each line that the address selects, and a command with two applies to each range of lines, from a line that the first address selects through the next line that the second selects (or just the one line, if the second address is a line number that's already been reached).  A `!` applies the command to the lines that *aren't* selected instead.  An address is:

- *n*: line *n* (the first line is 1)
- `$`: the last line
- `/regex/`: each line that the [regular expression](../#regular-expressions) *regex* matches

The commands are:

- `s/regex/text/[g][p]`: replaces the first match of *regex* with *text*, or with `g`, every match (eg, `s/  */ /g` changes each run of spaces to one space); in *text*, `&` is the match, `\1` through `\9` are the parts of the match that `\(` and `\)` marked in *regex*, and `\` makes any other character ordinary (eg, `\&` or `\\`).  With `p`, the line is displayed if anything was replaced.  Any character can be used instead of `/` (eg, `s,/,\\,g` replaces each `/` with `\`).
- `d`: deletes the line (skipping the rest of the commands)
- `p`: displays the line
- `q`: quits, after displaying the line (unless `/N` was given)
- `=`: displays the line number

### Examples

	SED 10q README.TXT                   displays the first 10 lines
	SED /N "$=" README.TXT               displays the number of lines
	SED /N "/BASIC/p" README.TXT         displays the lines containing "BASIC"
	SED "/^$/d" README.TXT               removes empty lines
	SED "s/\(.*\)=\(.*\)/\2=\1/" X.TXT   swaps the two sides of each "="
	SED "1,/^$/d" MAIL.TXT               removes the lines through the first empty one

### Limits and Messages

As in every filter, a line longer than 254 characters is split, and if an `s` command would make a line longer than that, the extra characters are dropped.  A script is limited to what fits on a command line.

ERRORLEVEL is set to 0, or 2 if *script* is missing (`Missing script`) or invalid (`Invalid script`), or *file* couldn't be opened (eg, `Unable to find X.TXT`).

Source: [sed.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/sed.asm)

{% include footer.html prev="MORE:../more/" next="SLEEP:../sleep/" %}
