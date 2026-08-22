# Phase 1, checked against the plan

The plan says phase 1 is "Base and the checkpoint tool", and lists six things.
Each one, and where it is.

| Promised | Done | Where |
| --- | --- | --- |
| Server plugin, client mod and the link between them | yes | `server/RaceManager/`, `client/`, `03_bus.lua` and `net.lua` |
| Your name is set once on first join. No password, no signup. | yes | `04_identity.lua`, the name card in the overlay |
| The interface shell: top bar, bottom bar, player list | yes | `ui/modules/apps/RaceManager/` |
| Options and Discord finished | partly, as planned | Options panel. Demote self, leave server and the FPS meter are live. Language and XP tracking are listed in the plan as phase 6. |
| Checkpoint tool | yes | `07_tracks.lua`, `capture.lua`, `triggers.lua` |
| FPS measured with the mod off and on | yes | Taken on his server. 128 avg, 108 1% low with the mod on, against 125-130 without it. See [PERFORMANCE.md](PERFORMANCE.md). |

Promised outcome: "join, get named, see the interface, and capture all 29
checkpoints for Baja 1000 plus the Qualy and Time Attack routes." All of it
works on his server: joined, named, interface drawn, a five gate course
captured, saved, drawn on the map and driven through with every crossing
registering. The 29 gate layouts are his to capture now the tool is his.

## Top bar, against his eight buttons

| # | Button | Phase | State now |
| --- | --- | --- | --- |
| 1 | Race | 2 and 4 | button present, says which phase |
| 2 | Records | 5 | button present, says which phase |
| 3 | CoPilot and Chase | 6 | button present, says which phase |
| 4 | Challenges | 6 | button present, says which phase |
| 5 | Team | 4 | button present, says which phase |
| 6 | Radio | cut | not built. He cut it; the server uses BeamVoice. |
| 7 | Options | 1 and 6 | live for phase 1 |
| 8 | Discord | 1 | live, opens the link from config |

## Bottom bar, against his six

All five live buttons are drawn, all disabled until the car is stopped, and
the lights submenu opens on hover. The actions behind them are phase 3, which
is what the plan says. Each button carries its hold and penalty in a tooltip
so the design is visible now:

| # | Button | Hold | Penalty |
| --- | --- | --- | --- |
| 1 | Reposition | none | 1 min, Recovery |
| 2 | Spare tire | 30 sec | 30 sec, Flat Tire |
| 3 | Repair | 1 min | 30 sec, Repair |
| 4 | Fuel +25% | 20 sec | none |
| 5 | Lights | none | none |
| 6 | Winch | cut | He cut it. |

## Player list

Registered display name instead of the player id, plus level, speed and ping.
Speed and ping are read on the server from `MP.GetPositionRaw`.

"Airspeed" in his document is still assumed to mean current vehicle speed.
That is one of the open questions and it has not been confirmed.

## Not in phase 1, on purpose

Timing, splits, missed checkpoint detection, results, records, roles beyond
the permission gate, XP, speed zones, teams, challenges and CoPilot. Every one
of them belongs to a later phase in the plan.

## Rules held on every phase

| Rule | How |
| --- | --- |
| Checked line by line against his document | this file |
| Tested before handover | `tools/test_phase1.lua`, 64 checks. Two driver testing needs the test server. |
| FPS measured, mod off and on | done, and our meter cross checks against the NVIDIA overlay to within 2.4% |
| No work in the per frame loop | see [PERFORMANCE.md](PERFORMANCE.md) |
| Nothing created in the hot path | table pool, reused buffers |
| Interface redraws only on change, max ~10Hz | `ui.lua` |
| Messages small, batched, only on change | `03_bus.lua` |
| Disk on race end and a slow timer | 30s timer, shutdown, and on course or name change |
| Every handler wrapped | `RM.handler` and the channel dispatcher |
| Anything cheatable decided by the server | speed, ping, identity, roles, courses |

## Still needed from him

| Item | Needed for | Status |
| --- | --- | --- |
| Test server, admin, second account | two driver testing | server received, second account not confirmed |
| What the race classes are | phase 5, records sorting | waiting |
| All vehicles allowed, or a list | phase 4 | waiting |
| Confirm airspeed means current speed | phase 1, player list | waiting, assumed |
| Open source or private | licensing | unsettled, nothing declared |

We also need our own copy of BeamNG.drive to test any of the client half in
the game.
