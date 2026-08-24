# Changelog

One entry per phase, because one phase is one milestone.

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

FPS numbers taken on the server with the game, a second account for two driver
testing, the race class list, whether all vehicles are allowed, and
confirmation that "airspeed" means current speed.
