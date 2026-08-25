# Testing phase 2

Phase 1's walkthrough gets you connected, named and owner. This starts from
there: you are in the game, the interface is on screen, and at least one
course is saved. If not, do [TESTING.md](TESTING.md) first.

Server: `144.217.73.51:30199`

---

## Before the game: the automated side

These run on the plugin without the game and take a few seconds. If any of
them fail, do not bother going in.

```bash
lua54 tools/test_phase1.lua && lua54 tools/test_phase2.lua && lua54 tools/test_results.lua
```

```bash
python tools/check_ui.py && bash tools/check_bindings.sh
```

To look at the interface in a browser, with made up state instead of a server:

```bash
bash tools/preview/serve.sh
```

Then open `http://127.0.0.1:8777`. The buttons at the bottom left switch
between idle, armed, running, waiting and results.

---

## Stage 1. Bind the end race key

`Esc` → Options → Controls → search `race`. Bind **Race Manager: end race**.
The others should already be bound from phase 1.

You never have to use it, but it is the thing you will want when the car is
upside down in a ditch and you do not want to open a window.

## Stage 2. Arm a run

Top bar → **Race**.

Expect: a course dropdown, the number of checkpoints and whether it is a
circuit, a controller or wheel picker, and a lap box on a circuit only.

- Pick a point to point course. The lap box should disappear and a line should
  say it is one run.
- Pick a course captured on another map, if you have one. **Go to the grid**
  should grey out and say which map to load.

Press **Go to the grid** on the course you want.

Expect: the car is put eight metres in front of gate 1, facing it, and settled
on its suspension. That is worked out from gate 1 rather than from where you
left the grid, so it is right even on a course whose grid was parked past its
own first gate. The Race panel says you are on the grid, and
the top of the screen says **Drive through the start line**. The clock is not
running. The gates are drawn, gate 1 in yellow and the rest dimmer.

**If the car does not move**, check the game console for
`could not place the car on the grid`, and tell me which line it is.

## Stage 3. Start the clock

Drive forward through gate 1. You should never have to reverse into it: if you
do, tell me, because that is the bug this stage exists to catch.

Expect: the message at the top is replaced by a running clock showing tenths.
Under it, the lap if you asked for more than one, and **Next gate 2**. Gate 2
turns yellow.

Sit still for ten seconds and watch the clock. It should count up smoothly and
evenly, not jump or stall.

## Stage 4. Splits

Drive the course normally.

At each gate expect the next gate number to move on, the yellow to move with
it, and a split to appear under the clock for a few seconds.

The split is the time from the start of the run, not from the last gate. So it
only ever goes up.

## Stage 5. Cut a corner on purpose

Skip two checkpoints, deliberately, and carry on.

Expect: a message saying **Missed 2 checkpoints**, and the penalty count under
the clock going to 2. The next gate should be the one after the ones you
skipped, not the ones you missed.

This is the one that was not being caught before the last deploy, so it is
worth doing on purpose rather than hoping.

## Stage 6. Finish

Cross the line on the last lap.

Expect: the clock disappears, the gates disappear, and the results screen comes
up. If somebody else is still on the same course, instead you get **You are in**
and how many drivers are still out, and the results wait for them.

## Stage 7. Read the results

On the results screen check:

- the order is by the time **with** penalties, so a cut lap can lose to a
  slower clean one
- **Leader** and **Ahead** are both there, and the leader's are dashes
- the best lap at the top names whose it was, and it is **never** a lap that
  cut a gate. Cut two checkpoints on a quick lap and it must not take the best
  lap off a slower clean one: a short lap is not a fast lap, and phase 5 reads
  records straight out of this
- click your own row: raw time, best split, every penalty with the gate it was
  for, and the laps
- click a lap: every sector, including the last one back to the line, with the
  cut gates showing a dash rather than a number

The dashes matter. If a gate was cut, the sector into it, the sector after it,
and the one it sits between cannot be known, and the screen should say so
rather than print a number that spans the hole.

## Stage 8. Go again, and close

**Go again** should put you straight back on the grid on the same course
without going through the picker.

**Close** should put you back to idle with the gates gone.

## Stage 9. End Race

Arm, start, cross a couple of gates, then press End Race, or the key.

Expect: the run stops immediately, and it shows in the results as a did not
finish with a reason, not as a missing row.

## Stage 10. Two drivers

Both arm on the same course.

- The first one to finish should see **You are in, waiting on 1 driver**.
- Nothing should appear until the second is off track.
- Both should then get the same results, with both rows on it.

Then repeat, but have the second driver quit the server mid run instead. The
first driver should get their results as soon as the second disconnects, with
the second listed as a did not finish. **Nobody should be left waiting on
somebody who is not coming back.**

## Stage 11. The frame rate

Options → Frame rate → **Measure now**, standing in the same place you took
the phase 1 baseline, same car, nothing recording.

Phase 1 was **128 average, 108 one per cent low**. Phase 2 is meant to stay
within 3 and 5 of that. Do it once parked and once mid run, because the run is
where the new work happens.

## Stage 12. The server side

In the panel console:

```
rm races
```

Mid run this lists who is racing, their lap, their gate, how long they have
been out and how many penalties they have. After everyone is in it says no
heat is open.

```
rm status
```

Lua memory should be under 1 MB with a full grid. Phase 1 idled at 206 KB.

---

## What is most likely to break

**The clock source.** The client picks one at load and logs which. In the game
console look for `clock source:`. Engine runtime is the one we want. If it
says accumulated frame time, timing still works but tell me, because that one
stops counting while the game is paused.

**The teleport.** Two different engine calls are tried. If neither works the
run can still be driven, you just have to get to the line yourself.

**Every run marked.** If results show **MARKED** on everybody, the clock probe
is not getting answered. `rm status` and the game console will show whether
pongs are coming back.

**Gates in the wrong place.** That means the course was captured on a
different map. The Race panel is supposed to refuse this, so if it let you
through, that is the bug, not the gates.
