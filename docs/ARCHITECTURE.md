# Architecture

Three pieces that have to stay in step.

```
   BeamMP server                     every player's game
   -------------                     -------------------
   Resources/Server/RaceManager      Resources/Client/RaceManager.zip
                                       |
   99_main.lua      wiring             +-- scripts/modScript.lua
   11_results.lua   the heat           |     loads the extension
   10_race.lua      the race           |
   09_clock.lua     clock offset       +-- lua/ge/extensions/raceManager/
   08_console.lua   host console       |     main      lifecycle
   07_tracks.lua    courses            |     net       the pipe
   06_players.lua   the list           |     clock     stamps a crossing
   05_roles.lua     permissions        |     state     mirror of the server
   04_identity.lua  who you are        |     triggers  checkpoint volumes
   03_bus.lua       the pipe  <------->|     capture   the tool
   02_store.lua     disk               |     race      grid, clock, results
   01_util.lua      clock, pool        |     bottombar recovery, repair
   00_config.lua    settings           |     hud       puts us in the layout
                                       |     perf      fps meter
                                       |     ui        the only bridge to html
                                       |
                                       +-- ui/modules/apps/RaceManager/
                                             one overlay: bars, list, windows
                                             app.png is the picker thumbnail,
                                             logo-*.png the Baja Sim badges
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
client  --- rmC2S --->  server         { m: [ { c: "track.mark", d: {...} } ] }
client  <-- rmS2C ----  server         { t: 1234.5, m: [ ... ] }
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

## Who owns the clock

Three clocks matter and they are deliberately kept apart.

The **server clock** decides everything. A lap time is server seconds and
nothing else.

The **client clock** exists only to stamp the moment a trigger fires. It is
monotonic and otherwise meaningless: the server converts it through a per
player offset and then decides whether to believe the result. Nothing is timed
by when a message arrived, because that would charge every driver half their
own ping on every gate.

The **clock on screen** is neither. It is counted locally from a start the
server gave, and it is a display rather than a measurement, so it is allowed
to be a frame out. Pushing a real time down the wire ten times a second would
put our traffic on the same channel BeamMP uses for car positions, for a
number nobody is scored on.

## Nothing recomputes on a timer

The plugin still has one 100ms timer. Phase 2 added no work to it beyond a
sweep for runs nobody finished, which happens on the roster interval and looks
only at runs that are open.

A split is worked out when a gate fires and never again. A results payload is
built once, when the last car on a course is off track, and never again. There
is no leaderboard to recompute, no gap to recalculate and no position to poll,
which is what dropping the live leaderboard actually bought.

Anything that would need a new timer is a design mistake.
