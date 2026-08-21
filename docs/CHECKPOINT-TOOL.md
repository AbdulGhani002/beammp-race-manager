# Capturing a course

You drive the route and press a key at each point. Nothing is written to the
map file, so players never need a custom map.

## Before you start

You need to be **admin** or **owner**. See step 6 of [INSTALL.md](INSTALL.md).

## Capturing

1. Spawn the car you want to survey in. Any car works; the gate is built
   around the car, not around the model.
2. Open **Options**, then **Checkpoint capture**.
3. Type the course name, for example `Baja 1000`.
4. Pick the kind: Race, Qualifying or Time attack.
5. Tick **Circuit** if the finish is the start line. Almost every course is.
6. **Start capturing.**

Now drive. At every checkpoint, stop where you want the gate and press your
mark key. The counter goes up. The window shows how far you have driven since
the last one, which is a useful sanity check on a long stage.

The gate is built square to the car: the way the car is pointing when you press
the key is the way drivers pass through it. Line the car up along the racing
line, not across it.

## While you are capturing

| | |
| --- | --- |
| **Mark here** | drop a gate where the car is standing |
| **Undo last** | remove the gate you just placed |
| **Set start line** | put the grid where the car is standing |
| **Gate size** | width, height and depth in metres |
| **Save course** | finish and write it |
| **Throw it away** | discard the whole draft |

**Gate size** applies to the next gate you place and corrects the one you just
placed. The default is 20m wide, 8m tall, 3m deep. Widen it for a gate at the
bottom of a fast descent where cars arrive spread out; narrow it where you want
drivers on one line.

If you do not set a start line, the first checkpoint becomes it.

## Nothing is lost

The draft lives on the server, not in your game. Alt-F4, a crash, a
disconnect, a server restart: come back and the capture window has your
checkpoints and picks up where it stopped. Twenty-four gates into a
twenty-nine gate layout costs zero gates.

One draft per person. Two admins can capture two different courses at once.

## Checking the course

When you save, the gates appear on the map as blue markers with their numbers.
Drive through them: each one registers as you pass. That is the same trigger
mechanism the race will use, so if it fires here it will fire in a race.

**Hide gates** when you are done looking.

You can bring any saved course back with **Show** in the course list.

## Things the tool refuses to do

| Message | Why |
| --- | --- |
| That is on top of the last checkpoint | two gates within 5m. Usually a held key or a double tap. |
| A course with that name exists | tick **Replace** if you meant it |
| Could not read the car position | you are not in a car |
| A course needs at least two checkpoints | one gate is not a route |
| Get in a car first | spectating, or the car has not spawned |

## What gets saved

```json
{
  "baja-1000": {
    "id": "baja-1000",
    "name": "Baja 1000",
    "kind": "race",
    "level": "utah",
    "circuit": true,
    "start": { "pos": { "x": 0, "y": 0, "z": 0 }, "yaw": 1.57 },
    "checkpoints": [
      { "i": 1, "pos": { "x": 0, "y": 0, "z": 0 }, "yaw": 1.57,
        "size": { "w": 20, "h": 8, "d": 3 } }
    ]
  }
}
```

`yaw` is radians, measured the way the game measures it. `size` is metres.

Read it back from the console at any time:

```
rm track baja-1000
```

## Why triggers and not waypoints

Waypoints are a navigation system. Checking distance to a waypoint every frame
means twenty-nine checks per car per frame, and a car at race speed can cross
the whole check radius between two frames and never register.

A trigger volume is a real object. The engine does the overlap test in its own
code and only wakes our Lua when something actually crosses. That is one call
per crossing instead of thousands per second, and it cannot be tunnelled
through at speed.
