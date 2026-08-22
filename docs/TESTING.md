# Testing phase 1

Everything below is done once, in order. Stages 0 to 5 are setup. Stage 6
onward is the actual test of what was built.

Server: `144.217.73.51:30199`

---

PLACEHOLDER_WHERE
---

## The three places

Everything below happens in one of three windows. Stages jump between them, so
it is worth knowing which is which before starting.

**A. The game.** The BeamNG window itself, started by the BeamMP launcher.

**B. The game console.** Inside BeamNG, press the **tilde key**, the one left
of `1` above Tab. A panel drops down with log output and a box you can type
Lua into. This is only for checking whether our mod loaded and for the
diagnostic commands. Press tilde again to close it.

**C. The panel console.** In Chrome, at
`panel.connecthosting.net/server/c0c0c399`, the **Console** tab. The black box
is the server log, and the **Type a command...** field underneath it is where
`rm` commands go. This is the server talking, not your game.

### Two different Options menus

This trips people up:

- **BeamNG Options** is `Esc` then Options. Game settings. **Key bindings live
  here**, under Controls.
- **Race Manager Options** is the **Options** button in our own top bar, on
  screen while you drive. The frame rate meter and the capture tool live here.

When a stage says Options, the table says which one.

### Which stage happens where

| Stage | Where | Exactly |
| --- | --- | --- |
| 0 Install | Desktop | BeamNG launcher, then the BeamMP installer |
| 1 Connect | **A** game | Main menu, More, Multiplayer, pick the server |
| 2 Mod loaded | **B** then **C** | tilde for the load line, then `rm players` in the panel |
| 3 Add the app | **A** game | `Esc`, UI Apps, edit layout, drag Race Manager on |
| 4 Pick a name | **A** game | the card in the middle of our overlay |
| 5 Become owner | **C** panel | `rm role <yourname> owner` |
| 6 Player list | **A** game | **Players** in our top bar, then drive |
| 7 Bind keys | **A** game | `Esc`, Options, Controls, filter Race Manager |
| 7 Capture | **A** game | our top bar, Options, Checkpoint capture |
| 8 Drive the gates | **A** drive, **C** watch | markers in game, `cp.hit` lines in the panel |
| 9 Measure FPS | **A** run it, **C** read it | our Options, Frame rate. Then `rm perf` in the panel |

Keep Chrome open on the Console tab on a second monitor if you have one. Half
of what tells you the mod is working shows up there, not in the game.

---

## Stage 0. Before BeamMP

1. **Run BeamNG once on its own** and let it reach the main menu, then quit.
   The first run creates the user folder that everything else writes into.
   From the launcher screen, **Launch (Default, D3D12 / D3D11)** is the right
   choice.

2. **Install the BeamMP launcher.** beammp.com, Download Now, run
   `BeamMP_Installer.msi`. Windows SmartScreen calls it an unrecognized app;
   More info, then Run anyway.

3. **Version.** BeamMP usually trails the newest BeamNG by a few weeks. If the
   launcher refuses to start with 0.39.4, roll the game back in Steam: right
   click BeamNG.drive, Properties, Betas, and pick the version BeamMP names in
   its error. Nothing we wrote depends on the game version, so whichever one
   BeamMP supports is fine.

---

## Stage 1. Connect

1. Start the **BeamMP launcher**. A terminal window opens. Leave it open, it
   is the bridge.
2. BeamNG starts on its own. In **Repository**, check that
   `multiplayerbeammp` is the only mod enabled. Other mods can break the join.
3. Main menu, **More**, **Multiplayer**. Log in or continue as guest.
4. Find **Mohammad Abdul's Development Server**, or use direct connect.

**The first join downloads about 480 MB**, because the map mod comes from the
server. Let it finish. The Race Manager client mod is 18 KB and arrives in the
same step.

---

## Stage 2. Did our mod actually load

This is the first thing worth checking, because everything else depends on it.

Open the in-game console with the **tilde key**. Look for:

```
Race Manager client 0.2.0-phase1 loaded
network bridge up
```

Then check from the other side. In the **panel console**:

```
rm status
rm players
```

`rm players` should list you. If it does, the handshake worked and the two
halves are talking.

**If the console line is missing**, the mod file loaded but the extension did
not start. Type this into the in-game console:

```lua
extensions.load("raceManager_main")
```

If that brings it to life, the mod entry script is not being found and I need
to move it. Tell me and it is a one line fix.

**If `rm players` is empty but you are in the server**, the extension is
running but never reached the server. Check:

```lua
extensions.raceManager_net.isConnected()
```

`false` means BeamMP had not finished loading when we tried. Force it:

```lua
extensions.raceManager_main.sayHello()
```

---

## Stage 3. Put the interface on screen

**Esc**, **UI Apps**, then the edit layout button.

Find **Race Manager** in the app list. Drag it on and stretch it to fill the
whole screen. It is one app that draws the top bar, the bottom bar, the player
list and every window, so there is nothing else to place. Save the layout.

A card should appear asking for your name.

**If Race Manager is not in the app list**, the UI app did not register. Tell
me, and send the tilde console output.

---

## Stage 4. Pick your name

Type it and press Continue. Rules: 3 to 20 characters, letters, numbers,
space, dot, dash and underscore.

Worth trying while you are here, because each one should give a clear message
rather than doing nothing:

- Two characters, too short
- Something with an at sign or exclamation mark, refused characters
- Reopen the card later, it should say the name is already set

The panel console logs the name being taken.

---

## Stage 5. Make yourself owner

Nobody is owner on a fresh server, so nobody can capture a course yet. In the
**panel console**, with the name you just picked:

```
rm role Abdul owner
```

Then `rm players` and check the role column says owner. In game, the Options
panel should now show a **Course tools** section.

This is deliberate. The panel console is behind your host login, so it is the
only place that can hand out owner, and nobody who walks onto the server can
become one.

---

## Stage 6. Player list

Click **Players** in the top bar.

- Your row appears, highlighted
- Level shows 1
- Drive, and the speed column moves
- Ping shows a number, coloured green, amber or red

Speed and ping are read on the server, not sent by your game. Watch the panel
console while you drive: no message storm, because a row only goes out when
the speed moves by at least 2 mph or the ping by at least 10 ms.

Close the list and the server stops sampling speed entirely.

---

## Stage 7. Capture a course

This is the phase 1 centrepiece.

First bind the keys: **Esc, Options, Controls**, filter for `Race Manager`.
Suggested: mark on `K`, undo on `L`, set start on `J`.

Then:

1. **Options**, **Checkpoint capture**
2. Name it `Test Loop` for a first run. Do the real Baja 1000 once you trust it.
3. Kind: Race. Tick Circuit.
4. **Start capturing**

Now drive. Stop where you want each gate, line the car up **along** the racing
line, and press `K`. The counter goes up, and the window shows how far you
have driven since the last gate.

Things to test on purpose:

| Try this | Should happen |
| --- | --- |
| Press `K` twice without moving | refused, that is on top of the last one |
| Press `K` while not in a car | get in a car first |
| **Undo last** | counter drops by one |
| Set gate width to 40, **Apply** | the gate just placed is corrected |
| **Set start line** | grid moves to where you are |
| **Save course** with only one gate | refused, needs at least two |
| Alt-F4 mid capture, rejoin | the capture window comes back with your gates |

That last one is the important one. The draft lives on the server, so
twenty-four gates into a twenty-nine gate layout costs nothing.

Place at least three gates, then **Save course**.

---

## Stage 8. Do the gates actually work

On save, the checkpoints appear on the map as blue markers with numbers.

**Drive through each one.** In the panel console you should see a `cp.hit`
line per crossing. That is the same trigger mechanism the race will use in
phase 2, so if it fires here it will fire in a race.

Then check the data landed:

```
rm tracks
rm track test-loop
```

`rm track` prints every checkpoint with its coordinates, yaw and gate size.

**If the markers appear but driving through does nothing**, the volumes were
created but the crossing callback is not firing. Run this in the tilde console
while sitting inside a gate:

```lua
dump(extensions.raceManager_triggers.count())
```

A number greater than zero means the volumes exist and only the callback needs
fixing. Tell me the number.

Finally, **Hide gates**, then reopen the course with **Show** from the saved
course list and confirm they come back.

---

## Stage 9. The FPS baseline

We promised measured frame rate with the mod off and on, every delivery. These
are the numbers every later phase gets compared against.

**Mod on:** Options, Frame rate, **Measure now**. Thirty seconds. Do it parked
in a fixed spot, in a specific car, then repeat driving a lap.

**Mod off:** the honest version needs the mod gone from the server, not just
the window closed. Say the word and I will rename
`Resources/Client/RaceManager.zip` aside and restart, you rejoin and measure
with the Steam overlay or BeamNG's own frame counter in the same spot and the
same car, then I put it back.

Read the results with:

```
rm perf
```

Average is the headline, but **1% low** is the number that matters. A mod that
costs two average FPS but eight off the 1% low is one you can feel, and that
stutter is exactly what he complained about in other race mods.

---

## Stage 10. Two drivers

Still blocked. The second account was agreed but never received, and nothing
in the player list, the roster updates or the permission gate is properly
tested until two people are on at once.

Worth chasing before phase 2, because timing and results cannot be signed off
single handed.

---

## What is most likely to break

Every line of the server half is tested against a mock host, 64 checks, all
passing. The client half could not be run without the game, so the risk is
concentrated in the places where our Lua meets BeamNG:

| Area | Symptom if wrong |
| --- | --- |
| Where BeamNG looks for the mod entry script | nothing loads at all, stage 2 |
| UI app registration | app missing from the list, stage 3 |
| Reading car position and heading | cannot read the car position, stage 7 |
| Spawning trigger volumes | no markers, stage 8 |
| The crossing callback shape | markers appear but never fire, stage 8 |
| The electrics stream for the stopped check | bottom bar always greyed out |

All six are small, isolated fixes. Send me what the tilde console says and
which stage it stopped at.
