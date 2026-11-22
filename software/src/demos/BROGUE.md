# BROGUE puzzle rooms

[BROGUE.BAS](BROGUE.BAS) is a dungeon crawl in which every room is a small puzzle. This file records the rules, how the puzzles are stored and placed, and every puzzle in the game, drawn as the game draws it. The drawings use the Unicode versions of the PC characters that the game prints.

## Rules

- A depth is 2 to 6 rooms joined in a single path by hallways. The player (`u`) starts on the stairs up (`<`) in the first room, and the stairs down (`>`) are in the last room. Stepping on `>` starts the next depth.
- A room has floor (`.`), blocks (`▒`, which never move), and stones (`O`).
- Walking into a stone pushes it. It rolls one cell per clock tick in that direction until the next cell isn't floor: a wall, a block, another stone, or a blank cell. The player doesn't move on a push.
- A rolling stone can't be stopped early, and a stone can't be pushed at all unless the cell beyond it is floor. Stones never roll onto blank cells (doors and hallways), so a door can't be plugged from outside.
- `R` puts the room the player is in back the way it was and returns the player to the door they came in by. There is no undo.
- `N` makes a new map at the same depth, and `Q` quits.

## Symbols

| Game | Here | Meaning |
|---|---|---|
| `CHR$(196)`, `CHR$(179)`, and the corners | `─` `│` `┌` `┐` `└` `┘` | Walls |
| `CHR$(177)` | `▒` | Block |
| blank | blank | A door, the inside of a hallway, or the way in from a room's door to its puzzle |
| `.` | `.` | Floor |
| `O` | `O` | Stone |
| `<` `>` | `<` `>` | Stairs up and down |
| `u` | `u` | Player |

A VT100 console shows the same line-drawing characters, with a checkerboard for the blocks.

A door is a gap in a wall with a corner on either side, turned outward. A hallway is drawn as two walls that join those corners, with nothing inside, since what's in a hallway isn't known. The stairs sit in a wall with no corners. Blank cells outside the walls can't be reached.

This is a whole depth 3 map, with the player on the stairs up:

```
                                              ┌────┐
                                              │▒▒▒▒│
                                              │...▒│
                                              │..O u
                                              │...▒│
                                              │▒ ▒▒│
                                              └┐ ┌─┘
                                               │ │
                                               │ │
                                               │ │
                                               │ │
                                               │ │
                                               │ │
                                             ┌─┘ └─┐
                                             │▒.O.▒└───────┐            ┌───┐
                                             │▒..O         │            │▒▒▒│
                                             │▒...▒┌─────┐ └────────────┘...│
                                             └─────┘     │               .O.│
                                                         └──────────────┐▒.▒│
                                                                        └─>─┘
```

## How a puzzle is stored

Each puzzle is one `DATA` statement (two if it's long): its difficulty, its door type, two door positions, its number of rows, and then the rows. In a row, `.` is floor, `#` is a block, and `O` is a stone. The walls aren't stored.

Every puzzle has two doors, and there are two door types:

- Type 0 has a door in the left wall and a door in the right wall. The two positions are their rows.
- Type 1 has a door in the left wall and a door in the bottom wall. The positions are the left door's row and the bottom door's column.

Rows and columns count from 1 inside the walls. A door is never in the first or last row (or column) of its wall, because the game draws a corner on either side of it.

This is Rockfall (difficulty 7, type 0, doors at rows 2 and 4, 5 rows):

```
DATA 7,0,2,4,5,".#....","O..#..",".O.#..",".OO..O","..O..."
```

```
┌──────┐
┘.▒....│
 O..▒..│
┐.O.▒..└
│.OO..O 
│..O...┌
└──────┘
```

## How a puzzle is placed

The path through the map decides which two walls of a room have doors. If they are opposite walls, the room gets a type 0 puzzle, and if they meet at a corner, a type 1 puzzle. In the first and last rooms, the stairs take the place of one door, so those rooms can use either type.

The game then flips and turns the puzzle at random, using any of the 8 ways that puts its doors on the right walls. Every puzzle can be solved starting from either door, so it doesn't matter which door the player arrives at.

The room is up to 3 columns and 2 rows larger than the puzzle, and the puzzle sits at a random position inside it. The rest of the room is filled with blocks, and blank cells run from each of the room's doors straight in to the puzzle's door. Since stones stop at blank cells, the puzzle plays exactly as it does at its own size, and there is no way around it. A few of the filler blocks that touch nothing but other blocks and walls are opened up as floor that can't be reached, so that the filler looks less regular.

This is Rockfall again, flipped left to right in a larger room, as the first room of a depth:

```
┌─────────┐
│▒▒▒▒▒▒▒▒.│
│.▒....▒.▒│
│▒▒..▒..O <
┘▒▒..▒.O.▒│
   O..OO.▒│
┐▒▒...O..▒│
│▒▒▒▒▒▒▒▒▒│
└─────────┘
```

## How a depth is put together

- Depth *n* has 2 or 3 rooms, plus one for every 2 depths, up to 6.
- Each room gets a puzzle of the right type with a difficulty from *n*-2 to *n* (10 is the highest), chosen at random. A puzzle is used once per map. If none fits, the range widens by one in each direction until one does.

## How difficulty is rated

A solver searched every position that can be reached in each puzzle, starting from each door. It found two numbers for each direction:

- Pushes: the fewest pushes that get the player to the other door.
- Dead ends: the share of reachable positions from which the other door can no longer be reached without `R`.

The rating is the average of the two push counts, multiplied by 1 plus the average of the two dead-end shares, rounded, with a top value of 10. So a puzzle rated 4 might need 4 forgiving pushes, or 3 pushes where nearly half of what the player could try is a mistake.

Eight of the easier puzzles were drawn by hand (Boulder, Fence, Stairway, Corner, Scatter, Gate, Closet, and Colonnade). The others were found by a search that changed a random room one cell at a time, kept each change that made it take more pushes, and then removed every block and stone that the solution didn't need.

## The puzzles

There are 25 puzzles: 13 of type 0 and 12 of type 1. Each is shown at its own size, unturned. "Pushes" gives the count from the left door first, then from the other door, and "dead ends" likewise.

| # | Name | Rating | Type | Size | Stones | Pushes | Dead ends |
|---|---|---|---|---|---|---|---|
| 1 | Boulder | 1 | 0 | 3×4 | 1 | 1, 1 | 0%, 0% |
| 2 | Fence | 1 | 0 | 5×3 | 3 | 1, 1 | 12%, 12% |
| 3 | Stairway | 1 | 0 | 5×5 | 5 | 1, 1 | 29%, 29% |
| 4 | Corner | 1 | 1 | 3×3 | 1 | 1, 1 | 0%, 0% |
| 5 | Plug | 1 | 1 | 3×3 | 1 | 1, 1 | 25%, 0% |
| 6 | Scatter | 1 | 1 | 4×4 | 3 | 1, 1 | 4%, 40% |
| 7 | Gate | 2 | 0 | 5×3 | 1 | 2, 2 | 0%, 0% |
| 8 | Sentries | 2 | 0 | 3×5 | 2 | 2, 2 | 22%, 22% |
| 9 | Gallery | 2 | 1 | 3×3 | 2 | 2, 2 | 25%, 25% |
| 10 | Ambush | 3 | 0 | 4×4 | 3 | 3, 2 | 49%, 13% |
| 11 | Closet | 4 | 0 | 3×3 | 3 | 3, 3 | 40%, 40% |
| 12 | Cellar | 4 | 1 | 4×5 | 3 | 3, 3 | 31%, 12% |
| 13 | Turnstile | 4 | 1 | 4×4 | 3 | 2, 3 | 29%, 78% |
| 14 | Colonnade | 5 | 0 | 7×5 | 10 | 4, 4 | 13%, 13% |
| 15 | Rubble | 5 | 1 | 4×5 | 3 | 3, 4 | 43%, 25% |
| 16 | Hallway | 6 | 0 | 8×3 | 6 | 5, 5 | 23%, 23% |
| 17 | Rockfall | 7 | 0 | 6×5 | 6 | 5, 6 | 35%, 36% |
| 18 | Crypt | 7 | 1 | 6×5 | 4 | 5, 6 | 8%, 47% |
| 19 | Quarry | 8 | 0 | 6×5 | 5 | 6, 5 | 30%, 59% |
| 20 | Nook | 8 | 1 | 6×5 | 6 | 4, 5 | 93%, 48% |
| 21 | Vault | 8 | 1 | 7×5 | 7 | 7, 7 | 4%, 23% |
| 22 | Sluice | 9 | 0 | 7×5 | 7 | 7, 7 | 38%, 18% |
| 23 | Knot | 9 | 1 | 7×7 | 8 | 8, 8 | 10%, 14% |
| 24 | Gauntlet | 10 | 0 | 8×5 | 6 | 9, 8 | 22%, 27% |
| 25 | Labyrinth | 10 | 1 | 6×6 | 9 | 9, 8 | 10%, 57% |

### Rating 1

```
1. Boulder   2. Fence   3. Stairway   4. Corner
┌───┐        ┌─────┐    ┌─────┐       ┌───┐
┘...│        ┘..O..└    ┘O....│       ┘...│
 O..└         ..O..      .O...│        O..│
┐...         ┐..O..┌    ┐..O..└       ┐...│
│...┌        └─────┘    │...O.        └┐ ┌┘
└───┘                   │....O┌
                        └─────┘

5. Plug   6. Scatter
┌───┐     ┌────┐
┘...│     ┘.O..│
 .O.│      O...│
┐▒.▒│     ┐..O.│
└┐ ┌┘     │....│
          └─┐ ┌┘
```

### Rating 2

```
7. Gate   8. Sentries   9. Gallery
┌─────┐   ┌───┐         ┌───┐
┘..▒..└   ┘...│         ┘...│
 ..O..     O..│          O..│
┐..▒..┌   ┐...└         ┐.O.│
└─────┘   │..O          └┐ ┌┘
          │...┌
          └───┘
```

### Rating 3

```
10. Ambush
┌────┐
│.▒..│
┘..O.└
 O.O.
┐...▒┌
└────┘
```

### Rating 4

```
11. Closet   12. Cellar   13. Turnstile
┌───┐        ┌────┐       ┌────┐
┘.O.└        ┘....│       ┘▒...│
 .O.          O...│        .O..│
┐.O.┌        ┐.▒..│       ┐.O..│
└───┘        │▒.O.│       │▒.O.│
             │.O.▒│       └─┐ ┌┘
             └┐ ┌─┘
```

### Rating 5

```
14. Colonnade   15. Rubble
┌───────┐       ┌────┐
│..O.O..│       ┘.▒..│
┘..O.O..└        .O..│
 ..O.O..        ┐.OO.│
┐..O.O..┌       │▒..▒│
│..O.O..│       │..▒.│
└───────┘       └┐ ┌─┘
```

### Rating 6

```
16. Hallway
┌────────┐
┘..O..▒..└
 .O.OO.O.
┐..▒..O..┌
└────────┘
```

### Rating 7

```
17. Rockfall   18. Crypt
┌──────┐       ┌──────┐
┘.▒....│       │......│
 O..▒..│       │▒.▒▒..│
┐.O.▒..└       ┘.O..O▒│
│.OO..O         O.▒...│
│..O...┌       ┐.▒..O.│
└──────┘       └───┐ ┌┘
```

### Rating 8

```
19. Quarry   20. Nook   21. Vault
┌──────┐     ┌──────┐   ┌───────┐
┘...O..│     │...▒..│   │..▒....│
 O...▒.└     ┘....O.│   │.OO.▒..│
┐..▒.O.       ..O.OO│   ┘..OO.▒.│
│▒.O.O.┌     ┐▒▒OO..│    .▒.OO..│
│...▒..│     │....▒.│   ┐.▒...O.│
└──────┘     └┐ ┌───┘   └────┐ ┌┘
```

### Rating 9

```
22. Sluice   23. Knot
┌───────┐    ┌───────┐
│..▒....│    │......▒│
┘..▒.O..│    ┘...▒.O.│
 .▒.OO.O└     O.▒.O..│
┐O.OO.▒.     ┐..▒.O.▒│
│....▒..┌    │.▒.▒OO.│
└───────┘    │▒....O.│
             │..O.▒..│
             └─┐ ┌───┘
```

### Rating 10

```
24. Gauntlet   25. Labyrinth
┌────────┐     ┌──────┐
│...▒....└     │..O..▒│
┘..O.▒..O      ┘.O.O..│
 O.O.O.▒.┌      O..▒O.│
┐..▒.O..▒│     ┐.▒▒..O│
│...▒....│     │▒..OO.│
└────────┘     │..O..▒│
               └─┐ ┌──┘
```

## Not done yet

- Rooms with 3 or 4 doors. The map only makes single paths, so every room has 2 doors (or a door and stairs). The data format has room for more door types.
- Ratings 3, 5, and 6 have few puzzles, and no rating has many. More puzzles per rating would make maps repeat less.
- Undo, and other things to push or collect. The Atomix levels that started this need goals as well as obstacles, which these rooms don't have yet.
