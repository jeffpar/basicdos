# BROGUE

[BROGUE.BAS](BROGUE.BAS) is a dungeon crawl in the spirit of Rogue: levels of rooms joined by hallways, full of stones that roll when they're pushed. It's a start, to which other elements and challenges can be added. (The Daleks it used to have are now in [DALEKS.BAS](DALEKS.BAS), the classic chase in one room.) This file records the rules, how maps are made, how multiplayer works, and an example level. The drawings use the Unicode versions of the PC characters that the game prints.

## Rules

- A level is 2 to 4 rooms joined in a single path by hallways. The player (`u`) starts on the stairs up (`<`) in the first room, and the stairs down (`>`) are in the last room. Stepping on `>` starts the next level.
- The player moves one cell in any of 8 directions: the cursor keys, or `h` `j` `k` `l` (left, down, up, right), plus Home, PgUp, End, and PgDn, or `y` `u` `b` `n`, for the diagonals.
- Walking into a stone (`O`) pushes it. It rolls one cell per clock tick until the next cell is anything but floor, and the player doesn't move. A stone that can't move at all isn't pushed.
- Bricks (`▒`) never move.
- `R` restarts the level (the same map), `N` makes a new map at the same level, and `Q` quits.
- In [multiplayer](#multiplayer), a stone that another player pushes into you squashes you.

## Symbols

| Game | Here | Meaning |
|---|---|---|
| `CHR$(196)`, `CHR$(179)`, and the corners | `─` `│` `┌` `┐` `└` `┘` | Walls |
| `CHR$(177)` | `▒` | Brick |
| blank | blank | A door, or the inside of a hallway |
| `.` | `.` | Floor |
| `O` | `O` | Stone |
| `<` `>` | `<` `>` | Stairs up and down |
| `u` | `u` | Player |
| `1`-`9`, `A`-`W` | the same | Other players (in multiplayer) |

A VT100 console shows the same line-drawing characters, with a checkerboard for the bricks.

Each cell of the map is every other column of the screen (1, 3, ..., 79), so a cell is about as wide as it is tall, and a diagonal move looks diagonal. The columns between cells are blank, except inside a wall or a row of bricks, so floor looks like `. . . .`.

A door is a gap in a wall with a corner on either side, turned outward. A hallway is drawn as two walls that join those corners, with nothing inside. The stairs sit in a wall with no corners, and the only way off the stairs up is into the room. Blank cells outside the walls can't be reached.

## Seeds

Every map is made from a 32-bit seed, shown in hex at the right end of the top row, which starts with the level. The game passes the seed to `RANDOMIZE` and makes the map from the random numbers that follow, and play itself uses no random numbers, so a seed and a level always give the same map. `R` makes the map again from its seed. `N` and the stairs choose a new seed from the BIOS tick count (except for the stairs in [multiplayer](#multiplayer)).

To play a map again later, run BROGUE with its seed, and its level if that isn't 1:

```
BROGUE 8CF79C81
BROGUE 8CF79C81 4
```

The maps changed when the Daleks were taken out, so a seed from an earlier version makes a different map now.

## Multiplayer

`BROGUE /M` (with the current switch character) plays with every other `BROGUE /M` running in another session, for example in consoles that START opens. They talk through a named pipe, `PIPE$:BROGUE`, which each one opens without FOR (as #2): every message goes whole to every other BROGUE that has the pipe open.

- Each message is 9 bytes, sent as one string and read with `INPUT$(9, #2)` when `LOC(2)` says one is waiting: the sender's session number plus 64 times the message's type, its seed (`MKL$`), its level, and 3 bytes that depend on the type:

  | Type | Meaning | Bytes 7-9 |
  |------|---------|-----------|
  | 0 | Position | The player's column and row (0 if it isn't playing a map), and the direction of the stone it just pushed (0 if none) |
  | 1 | Who's there? | The same as type 0; every BROGUE replies with its position |
  | 2 | Stones, please | The session asked, and the first stone wanted |
  | 3 | Stones | The session that asked, the next stone (0 if there are no more), and the number of bytes of stones that follow (2 for each) |
- A BROGUE that starts asks who's there and waits 2 seconds. The first reply that has a map gives it the seed and level to play; with no reply, it makes a map as usual, so the first BROGUE makes the map for the others.
- A BROGUE that joins another (by starting, or by taking the stairs or pressing `R` on a map that another player is already on, which it waits up to a second to hear about) makes the map from its seed and then asks that player for the map's stones, 2 bytes each (the column and the row). They come up to 40 at a time, since a pipe holds only 127 bytes; each group is asked for (up to 3 times, a second apart) only after the last one arrives, so none of them can be lost. They replace the map's own stones. A BROGUE that's starting then starts on a random floor cell of the first room that no other player is on (one that took the stairs, or pressed `R`, starts on the stairs up).
- Every BROGUE asks who's there again whenever it starts a map (including after `R`, `N`, or the stairs), and sends its position after every move and when it quits. Each one shows the other players that are on its own map (the same seed and level) by their session numbers (`1`-`9`, then `A`-`W`), except where a stone is.
- In multiplayer, the stairs choose the next seed from the current one (`RANDOMIZE SEED` followed by `RND%`), so players who take them play the same next map; `N` still chooses one from the tick count, so a player who presses it leaves the others.
- A player who pushes a stone sends the push's direction with its position, and every BROGUE on the same map pushes its own copy of that stone (the one next to that player, if it's still there) with the same rules, so it rolls the same way on every map. Players aren't on the map itself, so they don't stop a stone: one that rolls into a player squashes that player (on the player's own map, where the BROGUE then offers `R`, `N`, and `Q`), and rolls on.
- While it waits for a key, a BROGUE checks `INKEY$` and `LOC(2)` in turn, and LOC lets the other sessions run whenever no message is waiting, so a waiting BROGUE doesn't slow down the others.
- A BROGUE that's stopped with CTRL-C sends no last message, so its player stays on the others' maps until they start a new one.

## How a level is made

- Level *n* has 2 or 3 rooms, plus one for every 2 levels, up to 4, placed in a 2x2 grid and joined in a path (along the top row, then back along the bottom).
- A room is 8-18 cells across by 5-9 down, walls included, with a door (or stairs) in each of two walls, 2 or more cells from the corners.
- Each room gets 1 or more tries at a row or column of 1-3 bricks (more in a larger room), and then a try at a stone for every 3 cells of floor. Each is placed only where every cell next to it is floor, so nothing touches a wall or anything else, and there's always a way around.

## Example level

Level 1 of seed 8CF79C81 (`BROGUE 8CF79C81`), as it starts:

```
Level 1: Welcome tae this wee dungeon!                            Seed 8CF79C81
      ┌─────────────────┐
      │ . . . . . . . . │
      u . . . O . . . . │
      │ . . . . . . O . │
      │ . O . ▒ . . . . │                     ┌─────────────────────────────┐
      │ . . . ▒ . . O . └─────────────────────┘ . . . . . . . . . . . . . . │
      │ . O . ▒ . . . .                         . . O . . ▒▒▒ . . . . O . . │
      │ . . . . . . . . ┌─────────────────────┐ . . . . . . . . . . . . . . │
      └─────────────────┘                     └───────┐   ┌─────────────────┘
                                                      │   │
                                                      │   └─────┐
                                                      │         │
                                                      └─────┐   │
                                              ┌─────────────┘   └─────────────┐
                                              │ . . . . . . . . . . . . . . . │
                                              > . . . . . . O . . . . . . . . │
                                              │ . . O . O . . . ▒ . . . ▒ . . │
                                              │ . . . . . . . . ▒ . . . ▒ . . │
                                              │ . . ▒ . . O . . . . O . ▒ . . │
                                              │ . . . . . . . . . . . . . . . │
                                              └───────────────────────────────┘

Move: hjklyubn (or the cursor keys)  Retry: R  New: N  Quit: Q
```

## Not done yet

- Other elements and challenges: with only stones and bricks, a level can't be lost, except in multiplayer.
- Rooms with 3 or 4 doors.
- No check that a stone can't be pushed where it blocks the only way on (`R` puts the stones back).
