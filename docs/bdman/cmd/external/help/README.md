---
layout: sheet
title: HELP
permalink: /docs/bdman/cmd/external/help/
---

{% include header.html %}

> HELP [*keyword*\|ALL\|BASIC\|CORE\|DISK\|EXT\|FUNC\|SYSTEM]

Displays help for *keyword* (eg, `HELP MID$`), or lists the keywords in a category.  HELP alone displays help for HELP.  If there's no help for *keyword*, HELP displays `No help available`, and ERRORLEVEL is set to 1.

| Argument | Displays |
|----------|----------|
| `ALL` | Every keyword |
| `BASIC` | BASIC statements and commands |
| `CORE` | An explanation of low memory systems, and the keywords they don't support |
| `DISK` | Disk commands, like DIR |
| `EXT` | External commands and drivers, like FORMAT |
| `FUNC` | Functions, like MID$ |
| `KEYS` | The keys for editing command lines (see [Typing Commands](../../../intro/#typing-commands)) |
| `SYSTEM` | System commands, like MEM |

A category hides any keyword with the same name, which is why the system category is SYSTEM, rather than SYS (the name of a utility).

HELP was a COMMAND.COM command (along with KEYS, which is now `HELP KEYS`) until it became an external command, so that low memory systems have more room for BASIC programs.

### HELP.TXT

The help text comes from HELP.TXT, in the EXT directory of the drive that COMMAND.COM was loaded from (normally the boot drive), so HELP works from any directory.  HELP finds that drive in the COMSPEC environment variable, which COMMAND.COM passes to every program (if there isn't room for the environment, HELP uses the current drive).

In HELP.TXT, each entry begins with a lower-case letter for its category, in brackets (eg, `[b]PRINT` or `[f]MID$`), followed by `+` if it isn't available on low memory systems (eg, `[b+]CIRCLE`), which HELP doesn't display; an entry without a category (eg, CORE or KEYS) is listed only by HELP ALL.

HELP wraps words to the console's width, displays each line of an entry as a paragraph (followed by a blank line) unless it ends with `\`, and indents a line that starts with a tab.  It also adapts the text as it displays it:

- `~` is displayed as the current switch character (eg, `~S` as `/S`)
- `\` is displayed as the current path character
- `*` around a word (eg, `*file*`) isn't displayed, but a `*` used as a wildcard (eg, `B:\*.BAS`) is

Source: [help.asm](https://github.com/jeffpar/basicdos/blob/main/software/src/os/util/misc/help.asm) and [HELP.TXT](https://github.com/jeffpar/basicdos/blob/main/software/src/os/cmd/HELP.TXT)

{% include footer.html prev="FORMAT:../format/" next="HEXDUMP:../hexdump/" %}
