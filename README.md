# BeamMP Race Manager

Race management for a private BeamMP server: timing, records, roles, XP,
challenges and a checkpoint capture tool. Built from scratch against the
BeamMP and BeamNG APIs.

**Status: phase 2 of six, built and deployed.** Phase 1 is the base and the
checkpoint tool, verified in game on the client server. Phase 2 is the time
trial: grid, honest split timing, missed checkpoints, penalties and the full
results screen. Qualifying and Race on a shared grid are phase 4.

## The three pieces

| Piece | Lives in | Runs on |
| --- | --- | --- |
| Server plugin | `server/RaceManager/` | the BeamMP server, Lua 5.3 |
| Client mod | `client/` | every player's game, LuaJIT |
| Interface | `client/ui/modules/apps/RaceManager/` | the game's UI, AngularJS |

The server decides anything that could be cheated. BeamMP ships the client mod
to every player as a readable zip, so the client only draws the screen and
reports what the car is doing.

## What phase 2 delivers

- **Time trial.** Pick a course, controller or wheel, a lap count. You are put
  on the grid and the clock starts on the start line.
- **Honest split timing.** A crossing is stamped by the client at the frame
  the trigger fires and converted on the server. Stamping it on arrival would
  charge every driver half their own ping on every gate, and the player on the
  worse connection would quietly lose seconds they never lost on the road.
- Missed checkpoints caught and priced, penalties only inside a run
- End Race, on a button and on a key
- **The results screen.** Corrected time decides it, raw time is shown and
  decides nothing. Gaps to the leader and the car ahead, best lap, and every
  penalty and sector one click away.
- No live leaderboard, which was his call and removes the largest network cost
  in the system

Checked line by line against the plan in [docs/PHASE-2.md](docs/PHASE-2.md).
What to test in game is [docs/TESTING-PHASE-2.md](docs/TESTING-PHASE-2.md).

## What phase 1 delivers

- Server plugin, client mod, and the link between them
- Identity from the verified BeamMP account plus a display name picked once.
  No password, no signup.
- The interface shell: top bar, bottom bar, player list
- Options and Discord finished
- Player list with name, level, speed and ping
- **The checkpoint capture tool.** Drive the route, press a key at each point.
  The positions save to the server. The mod builds the trigger volumes from
  that file at runtime, so the map file is never touched and players do not
  need a custom map.
- FPS measurement, mod off and mod on, recorded on the server

## Build

```
powershell -ExecutionPolicy Bypass -File tools/build.ps1
```

Produces `build/racemanager-deploy.zip`. Upload it to the panel file manager
at `/home/container`, use Unarchive, restart. Full walkthrough in
[docs/INSTALL.md](docs/INSTALL.md).

## Test

The plugin runs against a mock BeamMP host, so the server half can be checked
without the game:

```
lua54 tools/test_phase1.lua
lua54 tools/test_phase2.lua
lua54 tools/test_results.lua
```

The interface is checked against itself, because three bugs in this project
have had the same shape, where the template names something that is not there,
and none of them fail loudly:

```
python tools/check_ui.py
```

And it can be run in a browser with made up state instead of a server, which
is where a layout problem should be found rather than in the game:

```
bash tools/preview/serve.sh
```

Key bindings name their lua function as a string, so a typo fails silently in
game and the key simply does nothing. This checks every one of them points at
a function that exists:

```
bash tools/check_bindings.sh
```

Plans are LaTeX, compiled with Tectonic, which pulls what it needs on first run
and caches it. No TeX install to maintain:

```
bash tools/build_plans.sh
```

91 checks over phase 1: joining, naming, the player list, the capture tool,
the permission gate, persistence, and what a rewritten client can throw at it.

70 more over phase 2, with the clock driven by hand so a run plays through
without waiting for real seconds: clock offset, lap timing, cut corners, a
stamp claiming the impossible, ten drivers at once, and heap growth while a
car is on track.

## Documentation

| | |
| --- | --- |
| [INSTALL.md](docs/INSTALL.md) | deploying and setting it up in game |
| [CHECKPOINT-TOOL.md](docs/CHECKPOINT-TOOL.md) | capturing a course |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | how the three pieces fit |
| [PROTOCOL.md](docs/PROTOCOL.md) | every message, both directions |
| [PERFORMANCE.md](docs/PERFORMANCE.md) | the rules and how they are met |
| [TESTING.md](docs/TESTING.md) | the stage by stage test run |
| [phase-2-plan.pdf](docs/plans/phase-2-plan.pdf) | what phase 2 builds, and the decisions it turns on |
| [PHASE-1.md](docs/PHASE-1.md) | scope check against the plan |
| [CHANGES-FROM-V0.md](docs/CHANGES-FROM-V0.md) | what changed from the first attempt |

## Layout

```
server/RaceManager/     server plugin, loaded alphabetically
client/scripts/         BeamNG mod entry point
client/lua/ge/          game side extension
client/ui/modules/apps/ the interface
tools/build.ps1         builds the deploy bundle
tools/test_phase1.lua   runs the plugin against a mock host
tools/mock/             the mock host
docs/                   everything above
```

## Licence

None yet. Open source or private is unsettled with the client, so nothing is
declared until it is agreed in writing.
