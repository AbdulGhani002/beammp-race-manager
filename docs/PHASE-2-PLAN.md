# Phase 2 plan: time trial, timing and results

The core of the whole product. Records, XP, teams and challenges all sit on top
of what gets built here, so anything wrong in this phase is wrong in every
phase after it.

## What gets delivered

From his document, unchanged:

- Time Trial, with a lap count if he wants laps
- Controller or Wheel selected before the run
- Teleport to the start, and the run arms when he drives through the trigger
- End Race stops all timing at once
- A split recorded at every checkpoint
- Missed checkpoints caught and penalised
- The full results screen
- No live leaderboard during the run

Plus two things he asked for after the plan was written:

- **Penalties only apply during a race.** Free driving costs nothing. That
  decides the shape of the race state machine, so it belongs here rather than
  phase 3.
- **His colour scheme.** Dark red, black and grey, with a little orange and
  yellow for contrast. The results screen is the first thing worth styling.

## The one rule this phase turns on

**The server clock is the only clock.** Not one timing value comes from the
client. The client reports that it crossed a gate; the server decides when.

That is not caution for its own sake. The client mod ships to every player as a
readable zip, so a lap time the client calculates is a lap time the client can
choose.

The cost is the network round trip. A crossing is stamped on arrival, so a
player on 200ms ping has 200ms of lag in the stamp. Two ways to deal with it
and the second is better:

1. Stamp on arrival. Simple, and it penalises high ping.
2. The client sends its own frame timestamp alongside the crossing, the server
   keeps a rolling estimate of that player's offset from the heartbeat, and
   corrects. The client can still lie, but it can only lie inside a window the
   server already believes, and a lie that drifts gets caught.

Going with 2, with the window clamped. Worth writing down now because it is the
single decision the rest of the phase hangs on.

## State machine

One race state per player for time trial. Phase 4 turns this into a shared
grid, so the shape is chosen now to survive that.

```
idle -> armed -> running -> finished
             \-> abandoned
```

| From | To | On |
| --- | --- | --- |
| idle | armed | picks a course, teleports to the start |
| armed | running | drives through the start gate |
| running | running | crosses a gate, split recorded |
| running | finished | crosses the finish on the final lap |
| running | abandoned | End Race, disconnect, or leaves the level |
| finished | idle | closes the results |

**Penalties only exist in `running`.** That is his change, and it falls out of
the machine rather than being bolted on.

## Splits and laps

Stored on the server, per run:

```
run = {
  key, track, kind, mode,        -- mode is controller or wheel
  laps, currentLap,
  startedAt, finishedAt,
  splits = { [lap] = { [gateIndex] = seconds } },
  missed = { [lap] = { gateIndex, ... } },
  penalties = { { seconds, reason, at }, ... },
}
```

Splits are seconds from the start of the run, not deltas. Deltas are a
presentation choice and can be computed; a stored delta cannot be recovered
into an absolute if a gate is missed.

## Missed checkpoints

A gate is missed when a later gate fires while an earlier one has no split for
this lap. That catches both a genuine cut and a car tunnelling a gate at speed.

The penalty is per missed gate, and the reason carries the gate number so the
breakdown in the results reads as something a person can argue with.

Circuit courses wrap, so gate 1 firing after gate 29 is a lap, not a miss. The
lap boundary is the start gate, which is why the start line is stored
separately from the checkpoint list.

## Results screen

Only after everyone has finished. No live leaderboard, which was his call and
removes the largest network cost in the system.

| Panel | Notes |
| --- | --- |
| Corrected time | penalties included. This decides the result. |
| Click a name | that player's penalties, each with its reason |
| Dirty time | clean time, information only, decides nothing |
| Overall best lap | |
| Personal best lap | click to expand every lap |
| Diff to the car ahead | |
| Diff to the leader | |
| Personal best split | click to expand every split |

## Protocol additions

Client to server:

| Channel | Carries |
| --- | --- |
| `race.arm` | `{track, mode, laps}` |
| `race.end` | none |
| `cp.hit` | gains `{t}`, the client frame time, for offset correction |

Server to client:

| Channel | Carries |
| --- | --- |
| `race.state` | the state machine, on change only |
| `race.split` | the split just recorded, so the HUD can show it |
| `race.result` | the whole results payload, once |
| `race.teleport` | where to put the car when arming |

## Performance

Same rules, and one new risk. A split is one small message per gate crossing.
29 gates times a full grid is phase 4's problem, but the message shape is
decided here, so it is sized for that now: a split is an index and a number,
not a record.

Nothing is recalculated on a timer. A split is computed when a gate fires and
never again. The results payload is built once, when the last driver finishes.

FPS measured against the phase 1 baseline: **128 avg, 108 1% low.**

## Testing

The mock host gets a clock that can be driven by hand, so a run can be played
through in a test without waiting for real seconds. Cases worth having before
the code is written:

- A clean lap. Splits in order, corrected equals dirty.
- A missed gate. Penalty logged with the right gate number.
- A gate crossed twice. Second crossing ignored.
- Gates crossed out of order.
- Disconnect mid run. Run abandoned, nothing half written to disk.
- End Race mid run. All timing stops at once.
- A client sending a crossing for a gate it cannot have reached yet.
- A client sending a frame time far outside the believed window.
- Two runs on the same course by the same player. Personal best updates only
  when it should.

Then on the server, with two drivers, which is the part that is still blocked.

## What is needed from him

| Item | Needed for | Status |
| --- | --- | --- |
| Second account | two driver testing | agreed, never received. **Blocks sign off.** |
| Captured routes | something real to time | tool is his, waiting on him |
| Race classes | phase 5, but shapes the record now | waiting |
| Logo files | the results screen styling | sent, colours noted |

## Order of work

1. Race state machine, server side, with tests
2. Clock and offset correction
3. Splits and lap counting
4. Missed checkpoint detection
5. Arming, teleport, and the End Race button
6. Results payload
7. Results screen, in his colours
8. FPS measured against the baseline

CoPilot camera gets a quiet look during this phase. It is the least known part
of the whole job and week eleven is the wrong time to find out it is hard.
