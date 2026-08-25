# Changelog

One entry per phase, because one phase is one milestone.

## 0.2.0-phase2

Phase 2: time trial, timing and results. See [PHASE-2.md](docs/PHASE-2.md) for
this checked line by line against what was promised.

**Timing**
- Race state machine: idle, armed, running, finished, abandoned.
- A crossing is stamped by the client at the frame the trigger fires and
  converted on the server through a per player offset, from the same four
  timestamp exchange NTP uses. Stamping on arrival would charge every driver
  half their own ping on every gate, and jitter would make it a different
  amount each time.
- A claimed stamp still has to be later than the last split, not in the
  future, not further back than the connection could hide, and not imply a
  speed no car reaches between two gates whose distance apart is known. One
  that fails is not a kick: the arrival time is used and the run is marked.
- Splits per gate per lap, lap times measured to the line rather than to the
  last gate before it, and missed checkpoints caught and priced.
- Penalties only exist inside a run. Free driving costs nothing.

**Racing**
- Pick a course, controller or wheel, and a lap count. Refused if the course
  was captured on a map you are not on, because the gates would spawn under
  the world.
- Teleport to the grid, and the clock starts on the start line and not before.
- Checkpoint volumes are built for the run, with the gate being scored drawn
  in yellow and the rest dropped back.
- End Race, on a button and on a key, stops everything at once.

**Gate geometry, after the first real run**

- The trigger volume was built at half the size of the gate drawn on screen,
  because `setScale` takes the whole size and it was being given half. A car
  could drive through the middle of a 20 metre gate and miss a 10 metre box.
- A gate stored the heading the car had when the key went down, so a gate
  tapped mid corner faced where the car was pointing rather than lying across
  the road. One came out 89 degrees off and could not be driven through from
  any direction. Angles are now read off the racing line when a course is
  saved, and capped so a switchback cannot swing a gate back along the road.
- On a loop the numbering is rolled round so gate 1 is the gate the grid points
  at. A grid left half way round a course put gate 1 behind the car, and the
  only way to start a run was to reverse into it.
- Cars line up in front of gate 1 and facing it rather than on the saved grid,
  which was left by driving somewhere and stopping and can sit past the gate it
  is meant to be in front of.
- Courses already on disk are put through the same pass when they load.

**Found by racing it**

- Cutting the gates at the end of a lap left the run unfinishable. The line was
  read as gate 1 arriving out of turn and thrown away, so nothing closed the
  run: the clock kept going, the line did nothing however many times it was
  crossed, and the only way out was to quit the server. The line closes the lap
  now and prices what was cut. It still wants most of the lap done first, so
  turning round two gates in is a reverse over the line rather than a lap.
- The clock on screen carries the penalties. It was showing time on the road
  only, with the penalties as a count, so a cut looked free until the results
  came up and there was nothing left to do about it.

**Results**
- Everyone racing a course is a heat. The payload is built once, when the last
  of them is off track, and sent once. There is no live leaderboard and
  nothing recomputes on a timer.
- Corrected time decides the order. Raw time is shown and decides nothing.
  Gaps to the leader and to the car ahead, overall best lap, personal best lap
  and personal best sector.
- A lap that cut a gate cannot hold the best lap, personal or overall. It is a
  shorter lap, so it would have taken the record almost every time. It is
  still timed and still shown; it just sets nothing.
- A driver still on track is no longer told they are waiting on somebody. The
  count included their own run, so racing alone said you were waiting on
  yourself while your own clock was going.
- A row opens into every penalty with the gate it was for, and a lap opens
  into every sector, including the run from the last gate back to the line.
- Four ways a heat could have hung are closed: a disconnect, End Race, a run
  nobody finished, and arming on a second course.

**Interface**
- Baja Sim palette across every surface, and the badges themselves cut out of
  their black background and used on the name cards, in the top bar and as the
  app picker thumbnail.
- Windows can be moved and resized, and the bottom bar has keybinds.

**Checked**
- 239 automated tests against the mock host, which drives the clock by hand so
  a run plays through without waiting for real seconds.
- A consistency check that reads the template, the controller and the lua and
  makes sure every call, every field and every image on one side exists on the
  other.
- The interface runs in a browser with made up state, which caught sectors
  being labelled with the wrong gate and a player list whose speed and ping
  columns sat outside the panel.

**Repository**
- The project has its own folder rather than sharing a general one.

## 0.2.0-phase1

Phase 1: base and the checkpoint tool. Deployed, running, and confirmed in
game on the client server.

**Server plugin**
- Identity from the verified BeamMP account plus a display name picked once.
  No password, no signup.
- Roles: owner, admin, staff, player. Owner can only be granted from the host
  console, which is already behind the panel login.
- Player list with name, level, speed and ping. Speed and ping are read on the
  server from `MP.GetPositionRaw`, so the client is never asked for either.
- Course store with captures kept as drafts, so an interrupted capture is not
  lost.
- Console commands: status, players, tracks, track, drafts, role, perf, save.
- One 100ms tick. Batched outbound messages, a token bucket on inbound, a
  table pool so the tick loop does not allocate.
- Atomic writes with the old copy kept until the swap is complete.

**Client mod**
- Network bridge sharing the server envelope shape.
- Checkpoint capture: drive the route, press a key at each point, undo, resize
  a gate, set the grid, save, then drive it back to check it.
- Checkpoints spawn as real BeamNGTrigger volumes at runtime. The map file is
  never touched.
- FPS meter recording avg, min, max and 1% low to the server.

**Interface**
- One full screen overlay: top bar, bottom bar, player list, name card,
  options and the capture window.
- Buttons that are not built yet say which phase they arrive in.
- Bottom bar disabled until the car is stopped, with the hold and penalty for
  each button in its tooltip.

**Testing**
- Mock BeamMP host, so the plugin runs without the game.
- 71 checks over the whole phase, including what a rewritten client can throw
  at the server.
- Tested end to end on the client server: joined, named, promoted, captured a
  five gate course, saved it, saw the gates and drove through every one of
  them with each crossing registering.

**Frame rate**
- 128 avg, 108 1% low with the mod on, against 125 to 130 without it. No
  measurable cost.
- Our own meter agrees with the NVIDIA overlay to within 2.4%, so the number
  reported from phase 2 onward can be trusted.

### Changed from the first attempt

An earlier phase 1 was deployed but never committed. It is archived in
beammp-race-manager-v0. The full list of what changed is in
[docs/CHANGES-FROM-V0.md](docs/CHANGES-FROM-V0.md). The ones that mattered:
the first player to join an empty server became owner, nothing rate limited
the inbound pipe, speed came from the client, a saved course could be
overwritten by accident, and the atomic write had a window where a crash lost
the file.

### Not in this phase

Timing, splits, missed checkpoint detection, results, records, XP, speed
zones, teams, challenges and CoPilot. All are scheduled in later phases.

### Still needed

The race class list, whether all vehicles are allowed, and confirmation that
"airspeed" means current speed.
