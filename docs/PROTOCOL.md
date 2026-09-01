# Protocol

Two BeamMP event names carry everything.

| | |
| --- | --- |
| `rmC2S` | client to server |
| `rmS2C` | server to client |

No colon in either name. BeamMP splits its own wire format on `:`, so an event
called `rm:c2s` is registered without complaint and then never delivered: the
client reports the send succeeded and the server never sees it. The old names
stay registered on the server so a player running a stale mod still works.

Both carry the same envelope:

```json
{ "t": 1234.567, "m": [ { "c": "channel.name", "d": { } } ] }
```

`t` is the server clock in seconds, present on server messages only. `m` is
the list of messages. `c` is the channel, `d` is whatever that channel carries.

## Client to server

| Channel | Carries | Notes |
| --- | --- | --- |
| `hello` | `{version}` | sent when the game side extension is ready. Everything else waits on the reply. |
| `name.set` | `{name}` | only works once |
| `roster.sub` | `{on}` | the player list is open or closed. While nobody is subscribed the server does not sample speed at all. |
| `track.begin` | `{id,name,kind,circuit,level,overwrite}` | admin only |
| `track.mark` | `{pos,yaw,w,h,d}` | drop a checkpoint |
| `track.undo` | none | remove the last one |
| `track.gate` | `{i,w,h,d}` | resize a gate, defaults to the last |
| `track.start` | `{pos,yaw}` | place the grid |
| `track.finish` | none | save the draft as a course |
| `track.cancel` | none | throw the draft away |
| `track.delete` | `{id}` | admin only |
| `track.get` | `{id}` | ask for one course in full |
| `options.demoteSelf` | none | |
| `cp.hit` | `{track,i,t}` | a checkpoint was crossed. `t` is the client clock at the frame the trigger fired, not when the message was sent. |
| `clock.pong` | `{t1,t2,t3}` | the reply to a probe. `t1` is what came in, `t2` is when it arrived, `t3` is when the reply left. |
| `race.arm` | `{id,mode,laps}` | go to the grid. `mode` is `controller` or `wheel`. |
| `race.end` | none | End Race. Files a did not finish. |
| `race.clear` | none | the results screen was closed, the run can be let go |
| `service.use` | `{which,flat}` | press a bottom bar button. `which` is `reposition`, `spare`, `repair` or `fuel`. `flat` is the car saying a tire is down, which is the only thing that lets `spare` through during a run. |
| `service.done` | `{which,ok,why}` | how the job went. `ok:false` gives the penalty back. |
| `race.create` | `{track,laps,mode,open}` | make a race. `open` true is public, false is invite only. |
| `race.join` | `{id}` | join an open race, or one you are invited to |
| `race.invite` | `{who}` | host only. `who` is a player id from the roster. |
| `race.leave` | none | leave the race you are in. a host leaving hands it to whoever joined first. |
| `race.start` | none | host only. arms everyone, places the grid, and the line goes live. |
| `pit.state` | `{inside}` | the car entered or left a pit volume |
| `track.pit` | `{pos,yaw,w,h,d}` | mark a pit on the draft |
| `track.pitundo` | none | remove the last pit |
| `track.zones` | `{id,zones:[{from,to,mph}]}` | admin only. replace the speed zones on a course. |
| `records.get` | `{id}` | ask for a course's record book |
| `perf` | `{label,seconds,frames,avg,min,max,p1low}` | an FPS run |

## Server to client

| Channel | Carries | Notes |
| --- | --- | --- |
| `welcome` | `{id,key,name,role,guest,ranked,level,config}` | `name` is null when they have never picked one |
| `name.result` | `{ok,name}` or `{ok,reason}` | |
| `roster.full` | list of rows | sent once when the list opens |
| `roster.delta` | list of changed rows | only rows where something actually moved |
| `roster.drop` | player id | somebody left |
| `track.list` | list of summaries | `{id,name,kind,level,circuit,count}`, no checkpoints |
| `track.full` | one whole course | only when asked for by `track.get` |
| `track.draft` | the draft | sent on join when a capture was left unfinished |
| `capture.result` | `{action,ok,reason,data}` | reply to any `track.*` |
| `options.result` | `{action,ok,value}` | |
| `toast` | `{kind,key,a}` | short message, the client turns the key into text |
| `clock.ping` | server clock as a number | rides a batch that was already going out, so it costs no messages |
| `race.state` | `{state,track,mode,laps,lap,gates,next,done,circuit,penalties,penaltyTime,waiting,why}` | the whole state, sent when it changes and never on a timer. `done` is gates finished on this lap; `next` is 1 while the lap waits on the line, not one past the last gate |
| `race.teleport` | `{pos,yaw}` | put the car on the grid |
| `race.split` | `{lap,gate,split,next,done,penalties,penaltyTime,lapTime,lapTimeLap,missed,refunded,started,lapDone,finished}` | one crossing. `split` is seconds from the start of the run. `done` and `next` mean the same here as in `race.state`. |
| `race.waiting` | `{left}` | you are in, this many are still on track |
| `race.results` | the whole payload | built once when the last car is off track, sent once |
| `race.result` | `{ok:false,reason}` | why an arm was refused |
| `service.hold` | `{which,hold,penalty}` | the job is allowed. `hold` is seconds the car is held still, 0 outside a run. `penalty` is the seconds already added to the clock. |
| `service.run` | `{which,full}` | the hold is up, do the job. `full` true means the pit rate: the tank fills instead of gaining a quarter. |
| `service.failed` | `{which,why}` | it was refused, or the game could not do it |
| `race.lobbies` | list of `{id,track,name,host,laps,open,drivers}` | the open races, sent to everyone when they change |
| `race.lobby` | `{id,track,name,laps,mode,open,host,members}` or nothing | the race you are in. nothing means you left it or it started. |
| `records.data` | `{id,modes}` | the book: per mode the top runs, the lap record, and where the asker sits |
| `zone.warn` | `{charged,zone:{mph,from,to}}` | over the limit in a speed zone. `charged` false is the warning, true is the thirty seconds. |


## The results payload

Built once, on the server, when the last driver on that course is off track,
and never recomputed. Nothing in it is worked out by the interface.

```
{ track, trackName, circuit, gates,
  bestLap: { time, lap, name },
  finished: [ {
    pos, name, key, mode, clean, corrected, toLeader, toAhead, suspect,
    penalties: [ { seconds, reason, gate, lap, at } ],
    bestLap:    { time, lap },
    bestSector: { time, gate, lap },
    laps: [ { lap, time, start, splits[], sectors[], missed[] } ]
  } ],
  dnf: [ { name, key, why, lap } ] }
```

`clean` is the time before penalties and decides nothing. `corrected` is
`clean` plus every penalty, and that is the result.

`splits[g]` is seconds from the start of the run to gate `g`, not a delta. A
stored delta cannot be recovered into an absolute once a gate is missed, and
an absolute can always be turned into a delta.

`sectors[g]` is the time taken to get into gate `g`, worked out from the
splits. `sectors[gates+1]` is the run from the last gate back to the line.

A gate that was cut has `false` in `splits`, and the sectors either side of it
are `false` too, because neither can be known. False and not null: a hole in
the middle of the array turns it into an object once it is encoded, and then
the interface indexes it by number and finds nothing.

Both arrays are indexed from one on the server and arrive indexed from zero in
the interface, so the sector into gate `g` is at `sectors[g - 1]` there.

## Timing

A crossing is stamped by the client at the frame the trigger fires. Stamping
it when the server hears about it would add half a round trip to every split,
and jitter makes that a different amount each time, so the driver with the
worse connection loses seconds over a lap they never lost on the road.

The server converts the stamp with a per player offset, from the same four
timestamp exchange NTP uses, keeping the sample with the lowest delay of the
last eight rather than an average. A slow sample is one that sat in a queue,
and queuing is asymmetric, which is exactly what poisons an averaged offset.

A converted stamp still has to survive four checks: later than the previous
split, not in the future, not further back than the connection could hide, and
not implying a speed no car reaches between two gates whose distance apart we
already know. A stamp that fails is not a kick. The arrival time is used
instead and the run is marked, which shows in the results as `suspect`.

## Reason codes

Sent rather than sentences, so the interface can word them and later translate
them.

**Naming:** `too_short`, `too_long`, `bad_chars`, `taken`, `already_named`,
`no_session`, `no_record`

**Capture:** `not_allowed`, `bad_request`, `bad_id`, `bad_kind`, `bad_level`,
`already_exists`, `too_many_tracks`, `no_draft`, `bad_pos`, `bad_yaw`,
`too_close`, `too_many`, `nothing_to_undo`, `no_such_checkpoint`,
`need_two_checkpoints`, `no_such_track`

**Roles:** `bad_role`, `no_such_player`, `cannot_change_own_role`,
`target_outranks_you`, `cannot_grant_that_high`, `already_player`,
`owner_cannot_self_demote`

## What the server assumes about the client

Nothing. The mod ships to every player as a readable zip, so the inbound path
treats every message as hostile until it has been checked:

- Anything that is not a decodable envelope is dropped.
- A batch longer than `maxInboundMsgs` is truncated.
- Each player has a token bucket, `inboundPerSec` per second. Over that,
  messages are refused and the refusal is logged once per two hundred.
- Every field is type checked before it is used. Positions are rejected if
  they are not finite numbers or if they are further than 100 km from origin,
  which catches both NaN and a deliberately absurd coordinate.
- Every handler runs inside `pcall`. A handler that raises is logged, with the
  logging itself throttled, and the tick carries on.

The test suite sends junk that is not JSON, wrong types in every field,
unknown channels, a five hundred message batch and a flood, and asserts that
no handler raised.

## The race log

Every finished race appends one line of JSON to
`Resources/Server/RaceManager/data/results.jsonl`. It is for their Discord bot,
which runs on the same box and reads the file directly. Append only, never read
back by the plugin.

```json
{
  "v": 1,
  "at": 1787376096,
  "track": "baja-1000",
  "trackName": "Baja 1000",
  "circuit": true,
  "gates": 30,
  "bestLap": { "time": 618.441, "lap": 1, "name": "Dard" },
  "finished": [
    {
      "pos": 1, "name": "Dard",
      "correctedTotal": 642.118, "rawTotal": 642.118,
      "penaltySeconds": 0, "penaltyCount": 0,
      "bestLap": 642.118, "bestLapNumber": 1,
      "toLeader": 0, "toAhead": 0,
      "laps": 1, "mode": "wheel", "marked": false
    }
  ],
  "dnf": [ { "name": "Vince", "why": "ended by the driver", "lap": 1 } ]
}
```

`correctedTotal` is the whole race with penalties already in it, and is what
the finishing order is by. `rawTotal` is the time on the road and decides
nothing. `marked` means the clock could not vouch for part of the run.

`v` is the schema version. Fields may be added; nothing already there changes
meaning. If that ever has to break, `v` goes up and the bot can tell.
