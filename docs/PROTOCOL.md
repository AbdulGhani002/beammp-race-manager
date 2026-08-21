# Protocol

Two BeamMP event names carry everything.

| | |
| --- | --- |
| `rm:c2s` | client to server |
| `rm:s2c` | server to client |

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
| `cp.hit` | `{track,i}` | a checkpoint was crossed. Logged in phase 1, timed in phase 2. |
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
