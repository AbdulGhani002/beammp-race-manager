# Architecture

Three pieces that have to stay in step.

```
   BeamMP server                     every player's game
   -------------                     -------------------
   Resources/Server/RaceManager      Resources/Client/RaceManager.zip
                                       |
   99_main.lua      wiring             +-- scripts/modScript.lua
   08_console.lua   host console       |     loads the extension
   07_tracks.lua    courses            |
   06_players.lua   the list           +-- lua/ge/extensions/raceManager/
   05_roles.lua     permissions        |     main      lifecycle
   04_identity.lua  who you are        |     net       the pipe
   03_bus.lua       the pipe  <------->|     state     mirror of the server
   02_store.lua     disk               |     triggers  checkpoint volumes
   01_util.lua      clock, pool        |     capture   the tool
   00_config.lua    settings           |     perf      fps meter
                                       |     ui        the only bridge to html
                                       |
                                       +-- ui/modules/apps/RaceManager/
                                             one overlay: bars, list, windows
```

## Who decides what

The server decides everything that could be cheated. BeamMP hands the client
mod to every player as a readable zip, so anyone who joins can open it, read
it and rewrite it. Nothing that matters can live there.

That draws a hard line:

- The **server** owns the clock, identity, roles, courses, records, XP, and
  every rule.
- The **client** draws the screen and reports what the car is doing.

Speed and ping are a good example. Both could have been reported by the client.
Instead the server reads them out of `MP.GetPositionRaw`, which BeamMP already
maintains for vehicle sync. It costs a table lookup, it removes a message in
each direction per player, and a value the client never supplies is a value it
cannot invent.

## The pipe

One BeamMP event name in each direction, with channels inside.

```
client  --- rm:c2s --->  server        { m: [ { c: "track.mark", d: {...} } ] }
client  <-- rm:s2c ----  server        { t: 1234.5, m: [ ... ] }
```

BeamMP shares that channel with vehicle position sync. Flooding it makes every
driver look laggy, so the server batches: everything queued during a tick goes
out as one message per player when the tick ends.

The client does not batch, because everything it sends is caused by a keypress
or a trigger crossing and never by a frame. That keeps its send path off the
per frame loop entirely.

Every channel is listed in [PROTOCOL.md](PROTOCOL.md).

## Joining

`onPlayerJoining` fires before the game side extension exists, so it cannot be
the moment the interface is set up. The client says hello when it is actually
ready:

```
player connects
  server   onPlayerJoining     ->  session created, identity loaded
  client   extension loads     ->  sends "hello"
  server   "hello"             ->  sends "welcome", course list, any draft
  client   "welcome"           ->  draws, or asks for a name if there is none
```

A player who never sends hello is noted in the log after ninety seconds. They
are on the server without the interface, which is worth saying out loud rather
than leaving as a mystery.

## Identity

No passwords and no signup, because BeamMP already verified every player
through its own backend before they reached the server.

Identity is `beammp:<forum id>` plus a display name chosen once. Keying on the
forum id rather than the name or the session id matters: both of those get
reused, and a record attached to a reused key belongs to the wrong person.

Guests have no stable id, so they key on their name, they are marked unranked,
and nothing they do is attributed across sessions. Set `AllowGuests = false` in
`ServerConfig.toml` to remove the case entirely.

## Checkpoints

Captured by driving, stored on the server, and built into real trigger volumes
by the client at runtime. The map file is never modified, so players do not
need a custom map.

The volumes belong to the level. They are dropped when the level unloads and
rebuilt when a course is opened.

## Loading order

The server loads its Lua files alphabetically, which is why they are numbered.
Later files depend on earlier ones. `99_main.lua` wires everything and is the
only file that registers host events.

The client loads `main.lua`, which loads the rest with `ui` last, because `ui`
reads from all of them the moment it comes up.
