# What changed from the first attempt

An earlier phase 1 was written and deployed to the server but never committed
anywhere. Its server half was recovered off the box and is archived separately
so nothing is lost.

The shape of it was right: one tick, a batched bus, a dirty-flush store, table
pooling, pcall-wrapped handlers. That structure is kept. What follows is what
was wrong with it or missing from it.

## Security

**The first player to join an empty server became owner.** With no owners in
the config, whoever walked in first got full control. Owner can now only be
minted from the host console, which is already behind the panel login, so a
line typed there is the server owner by definition.

**Nothing limited what a client could send.** The mod ships to every player as
a readable zip, so anyone can rewrite it and put whatever they like on the
pipe. There is now a token bucket per player and a cap on batch length, so a
rewritten client cannot spend the server tick budget.

**Speed came from the client.** It was display only and marked as such, but a
value the client supplies is a value it can invent. Both speed and ping now
come from `MP.GetPositionRaw`, which BeamMP already maintains.

**A saved course could be overwritten by accident.** Starting a capture with
an existing name silently replaced it on save. Replacing now has to be asked
for.

**Nobody could change their own role.** Added, because granting yourself a
role you already outrank is still a way to confuse the audit trail.

## Correctness

**The atomic write had a window where the data was gone.** If the rename
failed it deleted the original and retried, so a crash between the two left
nothing. It now moves the old file aside, moves the new one in, and only then
removes the old. There is also a recovery path that reads the backup if the
main file is missing at load.

**Recorded FPS runs grew without a bound.** Now capped.

**Two capture presses on the same spot both counted.** A held key or a double
tap put two gates in one place. Anything within 5m of the previous gate is now
rejected.

**Names were checked against every stored player on every attempt.** Fine at
ten players, not at ten thousand. There is an index now.

**A player who never loaded the client mod was invisible.** They are on the
server without an interface. It is now said once in the log after ninety
seconds rather than left as a mystery.

## Network

**The whole course list went to every client on every change.** Twenty-nine
checkpoints across three courses, pushed to everyone, whenever anything moved.
The menu is a summary now; a course is sent in full when it is opened.

**Ping was measured with a round trip heartbeat.** Two messages per player
every three seconds. `MP.GetPositionRaw` already returns ping, so the whole
heartbeat mechanism is gone.

**Broadcasts called `MP.GetPlayers()`.** That builds a fresh table on every
call. They walk the session table already in memory instead.

## Allocation

**The roster delta allocated a table every tick it changed.** That is the hot
path the whole design is trying to keep clean. It is one reused buffer now.

**`sendNow` allocated two tables per call.** Pooled.

## Things that were simply missing

- Gate size could not be corrected after a gate was placed
- A course could not be asked for individually
- No console commands beyond status, players, tracks and save. There are now
  commands for one course in detail, drafts in progress, recorded FPS runs,
  and granting roles.
- No test of any kind. There is now a mock BeamMP host and a 64 check run over
  the whole phase.
- No build script. Zipping by hand on Windows also silently writes backslash
  separators into the zip, which a Linux host and BeamNG both read as one long
  filename, so the mod fails to load with no useful error.
- No documentation.

## The client half

The first attempt's client mod could not be recovered off the server, so the
client here is new. It keeps the same module split, which was sensible, and
changes one thing: five separate UI apps became one overlay. Five apps means
five things to place in the layout editor, five sets of update traffic, and
five places to keep the ten times a second cap. One overlay is one placement
and one channel.
