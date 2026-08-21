# BeamMP Race Manager

Race management for a private BeamMP server: timing, records, roles, XP,
challenges and a checkpoint capture tool. Built from scratch against the
BeamMP and BeamNG APIs.

**Status: phase 1 of six.** What is here now is the base and the checkpoint
tool. Racing, timing and results are phase 2.

## The three pieces

| Piece | Lives in | Runs on |
| --- | --- | --- |
| Server plugin | `server/RaceManager/` | the BeamMP server, Lua 5.3 |
| Client mod | `client/` | every player's game, LuaJIT |
| Interface | `client/ui/modules/apps/RaceManager/` | the game's UI, AngularJS |

The server decides anything that could be cheated. BeamMP ships the client mod
to every player as a readable zip, so the client only draws the screen and
reports what the car is doing.

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
```

64 checks covering joining, naming, the player list, the capture tool, the
permission gate, persistence, and what a rewritten client can throw at it.

## Documentation

| | |
| --- | --- |
| [INSTALL.md](docs/INSTALL.md) | deploying and setting it up in game |
| [CHECKPOINT-TOOL.md](docs/CHECKPOINT-TOOL.md) | capturing a course |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | how the three pieces fit |
| [PROTOCOL.md](docs/PROTOCOL.md) | every message, both directions |
| [PERFORMANCE.md](docs/PERFORMANCE.md) | the rules and how they are met |
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
