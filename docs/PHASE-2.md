# Phase 2, checked against the plan

The plan says phase 2 is "Time trial, timing and results", and lists eight
things from his document plus two he asked for afterwards. Each one, and where
it is.

| Promised | Done | Where |
| --- | --- | --- |
| Time Trial, with a lap count if he wants laps | yes | `10_race.lua`, the Race panel |
| Controller or Wheel selected before the run | yes | picked on the Race panel, stored on the run, shown in the results |
| Teleport to the start, and the run arms when he drives through the trigger | yes | `race.teleport`, and `armed` becomes `running` only on gate 1 |
| End Race stops all timing at once | yes | the button, the `rm_end_race` key, and `race.end` |
| A split recorded at every checkpoint | yes | `RM.race.gate`, one split per gate per lap |
| Missed checkpoints caught and penalised | yes | a later gate firing while an earlier one has no split |
| The full results screen | yes | `11_results.lua` builds it, the results veil draws it |
| No live leaderboard during the run | yes | there is no timer anywhere that recomputes a position |
| Penalties only apply during a race | yes | `RM.race.penalty` refuses outside `running`; the bar reads it from the race |
| His colour scheme | yes | done in phase 1's last commits, carried through the new screens |

## The results screen, against his eight panels

| Panel | State |
| --- | --- |
| Corrected time | the headline time in the table, and what the order is by |
| Click a name for that player's penalties, each with its reason | a row expands into them, each naming the gate it belongs to |
| Dirty time, information only | shown as **Raw time** in the expanded row, with a line saying it decides nothing |
| Overall best lap | above the table, with whose it was |
| Personal best lap, click to expand every lap | in the expanded row, best lap highlighted |
| Diff to the car ahead | the **Ahead** column |
| Diff to the leader | the **Leader** column |
| Personal best split, click to expand every split | best sector in the expanded row, and every sector under each lap |

## What a run does, start to finish

1. Pick a course, a mode and a lap count, and press **Go to the grid**. The
   button is refused if the course was captured on another map, because the
   gates would spawn under the world.
2. The server arms the run and sends the grid position. The car is put there
   and settled. Nothing is timed yet, so taking a minute to get ready costs
   nothing.
3. The checkpoint volumes go up. The gate being scored is yellow, the rest
   drop back, which on a course with junctions is the difference between
   knowing where it goes and guessing.
4. Crossing gate 1 starts the clock. It sits at the top of the screen and is
   counted locally, showing tenths.
5. Every gate gives a split. A cut is caught and priced, and says so on screen
   while there is still a lap left to care about it.
6. The last gate, or the line on the last lap, finishes the run.
7. Results appear when the last car on that course is off track. Until then
   the screen says how many are still out.

## Timing, and why it is done the awkward way

A crossing is stamped by the client, at the frame the trigger fires, and the
server converts it. The obvious alternative is to stamp it when the server
hears about it, which is simpler and unusable: it adds half a round trip to
every split, jitter makes that a different amount every time, and across a
thirty gate course it is seconds. It would also mean the player with the worse
connection loses time they never lost on the road. He is in the United States
and this is written from Pakistan; we would never have agreed on a lap time.

The client cannot cheat with it, because it never decides anything. It offers
a number and the server decides whether that number is possible: later than
the last split, not in the future, not further back than the connection could
hide, and not implying a speed no car reaches between two gates whose distance
apart is already known. A stamp that fails is not a kick. The arrival time is
used, the run is marked, and the results say so. Nobody is thrown off the
server because their connection hiccuped.

The offset comes from the same four timestamp exchange NTP uses, keeping the
lowest delay sample of the last eight rather than an average, because a slow
sample is one that sat in a queue and queuing is asymmetric. The probe rides a
message that was already being sent, so it costs no traffic at all.

## Heats, and the four ways they could have hung

Everyone racing the same course is a heat, and the results are built once when
the last of them is off track. That is what "no live leaderboard" buys: no
timer, no polling, no recomputed positions.

A heat that never closes would be worse than no results at all, so:

- a **disconnect** reads the run out before throwing it away
- **End Race** files a did not finish rather than nothing
- a run that has been sitting there past the idle timeout is **swept up** on
  the roster interval
- arming on a **second course** drops you out of the first, and waiting is
  counted per course rather than per player

## What is not in this phase

Qualifying and Race, the shared grid, are phase 4. The bottom bar actions are
phase 3: the buttons still say so, but they now also name what the action
would cost inside a run, because the penalty side of them is built.

Records and personal bests across sessions are phase 5. Nothing here is
written to disk except through the stores that already existed.

## Checked

161 server tests plus 78 for the heat and the results, all against the mock
host, so a run plays through without waiting for real seconds and the timing
can be checked to the millisecond.

What to check in the game is [TESTING-PHASE-2.md](TESTING-PHASE-2.md), which
starts where [TESTING.md](TESTING.md) leaves off.
