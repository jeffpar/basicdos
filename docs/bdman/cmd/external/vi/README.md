---
layout: sheet
title: VI
permalink: /docs/bdman/cmd/external/vi/
---

{% include header.html %}

> VI [/WS] [*file*]

A full-screen text editor with a subset of the commands of the UNIX *vi* editor.  It works on VKD$ consoles and on serial consoles with ANSI or VT100 terminals (but not GENERIC terminals), and it can edit files of up to 64K (65,280 bytes), using only as much memory as the file needs.  Files are saved with CR/LF at the end of every line.

`/WS` adds [WordStar keys](#wordstar-keys).  Without a *file*, VI starts with an empty file, which needs a name when you write it (eg, `:w NEW.TXT`).

VI uses up to 80 columns and 25 rows of the screen, and it needs at least 4 rows, and a console (`Console required`).

### Command Mode

VI starts in command mode, where keys are commands; most commands can be preceded by a count (eg, `3dd` deletes 3 lines).  The cursor keys, Home, End, PgUp, PgDn, Insert, and Delete work as you'd expect, in insert mode too.  The last row of the screen displays messages and the commands that start with `:`, `/`, and `?`.

| Commands | Description |
|----------|-------------|
| `h` `j` `k` `l` | Move left, down, up, or right (also BACKSPACE and SPACE) |
| `w` `b` `e` | Move to the next word, the previous word, or the end of the word (`W`, `B`, and `E` use words separated only by blanks) |
| `0` `^` `$` | Move to the start of the line, its first non-blank, or its end |
| `+` `-` | Move to the first non-blank of the next (also ENTER) or previous line |
| `G` `gg` | Move to the last line (or line *n*, eg, `10G`), or the first line |
| `H` `M` `L` | Move to the top, middle, or bottom line of the screen |
| `f`*c* `F`*c* `t`*c* `T`*c* | Move to the next (or previous) *c* on the line, or just before it; `;` repeats, and `,` repeats in the other direction |
| `%` | Move to the bracket matching the next `(`, `)`, `[`, `]`, `{`, or `}` on the line |
| `/`*text* `?`*text* | Search forward (or backward) for *text*, wrapping around the file; `n` repeats, and `N` repeats in the other direction |
| CTRL-F CTRL-B | Scroll forward or backward a screen |
| CTRL-D CTRL-U | Scroll down or up half a screen |
| CTRL-E CTRL-Y | Scroll down or up a line |
| `i` `a` `I` `A` | Insert before the cursor, after it, before the first non-blank, or at the end of the line |
| `o` `O` | Open a new line below (or above) the current line, and insert |
| `d`*motion* `c`*motion* `y`*motion* | Delete, change, or yank (copy) the text from the cursor to where *motion* would move; `dd`, `cc`, and `yy` use whole lines |
| `x` `X` `D` `C` `s` `S` `Y` | Same as `dl`, `dh`, `d$`, `c$`, `cl`, `cc`, and `yy` |
| `p` `P` | Put the deleted or yanked text after (or before) the cursor, or for whole lines, below (or above) the current line |
| `r`*c* | Replace the character under the cursor with *c* |
| `~` | Toggle the case of the character under the cursor |
| `J` | Join the next line to the current line |
| `u` | Undo the last change (and `u` again redoes it) |
| CTRL-G | Display the file name, whether it's modified, and the current line number |
| CTRL-L | Redraw the screen |
| `ZZ` | Save the file (if modified) and exit |

### Insert Mode

In insert mode, typed characters are inserted, ENTER starts a new line, BACKSPACE erases what was just typed, and ESC (or CTRL-C or Insert) returns to command mode.  On a VKD$ console, insert mode displays a block cursor.

### Colon Commands

| Command | Description |
|---------|-------------|
| `:w` [*file*] | Write the file (or another file) |
| `:wq` [*file*] or `:x` | Write the file (`:x` only if it's modified) and exit |
| `:q` | Exit, unless the file has been modified; `:q!` exits anyway |
| `:`*n* or `:$` | Move to line *n*, or the last line |
| `:s/`*old*`/`*new*`/` | Replace the first *old* on the current line with *new* (add `g` at the end to replace every *old* on the line, and use `:%s` for every line); the text is matched exactly |

### WordStar Keys

`/WS` adds these WordStar keys, which work in insert mode too (and replace the vi commands that use the same keys, such as CTRL-D and CTRL-E).  The key after CTRL-Q can be typed with or without CTRL (eg, CTRL-Q CTRL-R or CTRL-Q R).

| WordStar Keys | Description |
|---------------|-------------|
| CTRL-S CTRL-D | Move left or right |
| CTRL-E CTRL-X | Move up or down |
| CTRL-Q S, CTRL-Q D | Move to the start or end of the line |
| CTRL-Q E, CTRL-Q X | Move to the top or bottom line of the screen |
| CTRL-Q R, CTRL-Q C | Move to the first or last line |
| CTRL-Q F | Find text (like `/`) |
| CTRL-R CTRL-C | Scroll backward or forward a screen |
| CTRL-W CTRL-Z | Scroll up or down a line |
| CTRL-G | Delete the character under the cursor |
| CTRL-Y | Delete the line |
| CTRL-Q Y | Delete to the end of the line |
| CTRL-N | Insert a new line above the current line |
| CTRL-V | Switch between insert mode and command mode |

### Messages

| Message | Meaning |
|---------|---------|
| `Console required` | The output isn't a console, or it has too few rows, so VI exits with ERRORLEVEL set to 1 |
| `File too large` | The file doesn't fit in 65,280 bytes |
| `Out of memory` | There isn't room for the file, or for a change or yank |
| `Read error`, `Write error` | The file couldn't be read or written |
| `No file name` | `:w` needs a name, since the editor has no current file |
| `No write since last change (add ! to override)` | `:q` won't discard changes |
| `Unknown command` | The colon command isn't one of those above |
| `Use :s/old/new/ or :s/old/new/g` | The `:s` command isn't valid |
| `Pattern not found` | The search or `:s` didn't find the text |
| `No previous pattern` | `n` or `N` has nothing to repeat |

Source: [software/src/os/util/vi](https://github.com/jeffpar/basicdos/tree/main/software/src/os/util/vi)

{% include footer.html prev="UNIQ:../uniq/" next="VOL:../vol/" %}
