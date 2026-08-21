# Performance

He described "barely noticeable but extremely distracting tick lag" in other
race mods, and we promised measured FPS with every delivery and free fixes for
any drop he can feel. These are rules, not preferences.

## No work in the per frame loop

The server has one timer. It runs every 100ms and everything periodic divides
into it. While the server is empty it does nothing but check whether anything
needs writing.

On the client, three modules define `onUpdate`, and each one leaves on its
first line unless you are actively using it:

| Module | Costs anything when |
| --- | --- |
| `ui` | something changed since the last push. Otherwise one boolean test. |
| `capture` | the capture tool is open with at least one gate placed. |
| `perf` | an FPS measurement is running. |

Checkpoints are trigger volumes, not distance checks. The engine does the
overlap test in its own code and wakes Lua only on a crossing. Twenty-nine
gates against a full grid costs nothing per frame, and a car at race speed
cannot tunnel through a real volume the way it can outrun a radius check.

## Nothing is allocated in a hot path

Allocating in a loop that runs all session creates garbage, the collector runs,
and the game pauses for a few milliseconds. That pause is the tick lag.

- The bus and the roster take their tables from a pool and give them back.
- The roster delta is one buffer, reused every tick, cleared in place.
- `MP.GetPlayers()` builds a fresh table on every call, so broadcasts walk the
  session table that is already in memory instead.
- The FPS sample buffer is allocated once. Growing an array while sampling
  frame times would be measuring the measurement.

## The interface redraws only when a number changes

Capped at ten times a second, and only when something is actually different.
Nobody reads a lap time at 120fps.

## Messages are small, batched, and only on change

BeamMP shares its channel with vehicle position sync, so flooding it makes
every driver look laggy.

- One event name in each direction, channels inside.
- Everything queued during a tick goes out as one message per player.
- A roster row is sent only when a field on it actually moved: speed by at
  least 2 mph, ping by at least 10 ms.
- Speed is not sampled at all while nobody has the player list open.
- The course menu is a summary. Twenty-nine checkpoints across three courses
  go out when a course is actually opened, not on every change.
- **No live leaderboard during a race.** Results come after the finish. That
  was his call and it removes the single largest network cost in the system.

## Disk is written on a timer, never per event

Every thirty seconds if anything is dirty, on shutdown, and immediately when a
course or a name changes, because losing either is worse than the write.

Each write goes to a temp file, the old file is moved aside, the new one is
moved into place, and only then is the old one removed. A crash at any point
leaves the old file or the new one and never a truncated one.

## One bad value cannot take anything down

Every host event handler and every channel handler runs inside `pcall`. A
handler that raises is logged and the tick carries on. The logging is
throttled, because a fault repeating sixty times a second costs more than the
fault does.

## Measuring

**Options, Frame rate, Measure now.** Thirty seconds, then the result goes to
the server.

Run it once with the mod off and once with it on, in the same place, in the
same car, with the same number of people on the server. Read them back with:

```
rm perf
```

Average is the headline, but the number to watch is the **1% low**: the worst
one percent of frames is where a stutter actually shows up. A mod that costs
two average FPS but eight off the 1% low is one you can feel, and that is
exactly the failure being guarded against here.

The phase 1 numbers are the baseline every later delivery is measured against.
