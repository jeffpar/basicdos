---
layout: sheet
title: HELP
permalink: /docs/bdman/cmd/external/help/
---

{% include header.html %}

> HELP [*keyword*\|ALL\|BASIC\|CORE\|FUNC\|CMD\|EXT]

Displays help for *keyword* (eg, `HELP MID$`), or lists the keywords in a category.  HELP alone displays help for HELP.  Help for a keyword, or a list of keywords, is displayed with a blank line before and after it, and help for a command or function begins with a `Usage:` line, which is followed by a blank line and the rest of its description:

	HELP VOL

	Usage: VOL [drive:]

	Displays the volume label of drive (or the current drive).

If there's no help for *keyword*, HELP displays `No help available`, and ERRORLEVEL is set to 1.

| Argument | Displays |
|----------|----------|
| `ALL` | Every keyword |
| `BASIC` | BASIC statements and commands |
| `CORE` | An explanation of low memory systems, and the keywords they don't support |
| `FUNC` | Functions, like MID$ |
| `CMD` | Internal commands, like DIR |
| `EXT` | External commands, like FORMAT |
| `KEYS` | The keys for editing command lines (see [Typing Commands](../../../intro/#typing-commands)) |

CMD lists the DOS-style commands built into COMMAND.COM; BASIC's own commands (eg, LIST and SAVE) are listed by BASIC.  EXT lists the commands in the EXT directory, and the build tools in the hard disk's TOOLS directory aren't included.

A category hides any keyword with the same name, so a new command can't share a category's name.

HELP was a COMMAND.COM command (along with KEYS, which is now `HELP KEYS`) until it became an external command, so that low memory systems have more room for BASIC programs.

### HELP.TXT

The help text comes from HELP.TXT, in the EXT directory of the drive that COMMAND.COM was loaded from (normally the boot drive), so HELP works from any directory.  HELP finds that drive in the COMSPEC environment variable, which COMMAND.COM passes to every program (if there isn't room for the environment, HELP uses the current drive).

In HELP.TXT, each entry begins with a lower-case letter for its category, in brackets (eg, `[b]PRINT` or `[f]MID$`), followed by `+` if it isn't available on low memory systems (eg, `[b+]CIRCLE`), which HELP doesn't display; an entry without a category (eg, CORE or KEYS) is listed only by HELP ALL.  The first line of an entry with a category is its syntax, which HELP displays after `Usage:`, and since no other command contains this text, a command that's used incorrectly displays only `Syntax error`.

HELP wraps words to the console's width, displays each line of an entry as a paragraph (followed by a blank line) unless it ends with `\`, and indents a line that starts with a tab.  It also adapts the text as it displays it:

- `~` is displayed as the current switch character (eg, `~S` as `/S`)
- `\` is displayed as the current path character
- `*` around a word (eg, `*file*`) isn't displayed, but a `*` used as a wildcard (eg, `B:\*.BAS`) is

Source: [help.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/help.asm) and [HELP.TXT](https://github.com/jeffpar/basicdos/blob/main/software/src/os/cmd/HELP.TXT)

{% include footer.html prev="FORMAT:../format/" next="HEXDUMP:../hexdump/" %}
