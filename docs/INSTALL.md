# Installing

## 1. Build

```
powershell -ExecutionPolicy Bypass -File tools/build.ps1
```

You get `build/racemanager-deploy.zip`, about 34 KB. Inside it:

```
Resources/Client/RaceManager.zip          the mod every player downloads
Resources/Server/RaceManager/*.lua        the plugin
```

## 2. Upload

1. Panel, **Files** tab. You should be at `/home/container`.
2. **Upload**, pick `racemanager-deploy.zip`.
3. Click the three dots on the uploaded file, **Unarchive**.
4. Delete the zip once it has unpacked.

It writes over the plugin files and the client mod. It does **not** touch
`Resources/Server/RaceManager/data/`, so display names, captured courses and
unfinished drafts all survive the update.

## 3. Set the Discord link

Edit `Resources/Server/RaceManager/00_config.lua` in the panel editor:

```lua
discordUrl = "https://discord.gg/your-real-invite",
```

## 4. Restart

**Restart** on the Console tab. You should see:

```
[RaceManager] [INFO] store 'players' loaded
[RaceManager] [INFO] store 'tracks' loaded
[RaceManager] [INFO] Race Manager 0.2.0-phase1 ready. tick 100ms, roster 500ms, autosave 30000ms
[RaceManager] [WARN] no owner set yet. type: rm role <name> owner
```

If you do not see the RaceManager lines, the plugin did not load. Check that
the files are directly inside `Resources/Server/RaceManager/` and not one
folder deeper.

## 5. Join, and get your name

Start BeamNG, join the server. The mod downloads automatically.

Add the interface: **Esc, UI Apps, edit layout**, drag **Race Manager** onto
the screen and stretch it to fill. It is one app that draws the whole overlay,
so there is nothing else to place.

On first join you get a card asking for your name. That is the name everyone
sees, and you pick it once. There is no password and no signup: BeamMP already
verified who you are before you reached the server.

## 6. Make yourself owner

Nobody is owner on a fresh server, which means nobody can capture a course
yet. Type this into the **panel console**, using the name you just picked:

```
rm role Darren Hardesty owner
```

The panel console is already behind your host login, so it is the only place
that can hand out owner. Nobody who walks onto the server can become one.

## 7. Bind the capture keys

**Esc, Options, Controls**, filter for "Race Manager". Four actions:

| Action | Suggested key |
| --- | --- |
| Mark checkpoint | `K` |
| Undo last checkpoint | `L` |
| Set start line | `J` |
| Player list | `Tab` is taken by BeamMP, try `P` |

Only the mark key really matters. The rest have buttons in the window too.

Now go to [CHECKPOINT-TOOL.md](CHECKPOINT-TOOL.md) and capture Baja 1000.

## Console commands

Typed into the panel console, not the game chat.

```
rm status              plugin health, one line
rm players             who is on, level, speed, ping, role
rm tracks              saved courses
rm track baja-1000     every checkpoint of one course, with coordinates
rm drafts              captures in progress
rm role <name> <role>  owner | admin | staff | player
rm perf                recorded FPS runs
rm save                write every store to disk now
rm help                this list
```

## Where things are kept

```
Resources/Server/RaceManager/data/
  players.json        identity, display name, role, xp, level
  tracks.json         saved courses and their checkpoints
  trackdrafts.json    captures in progress, one per person
  perf.json           recorded FPS runs
```

Written on a thirty second timer, on shutdown, and immediately whenever a
course or a name changes. Each write goes to a temp file and is swapped in, so
a crash mid-write leaves the old file or the new one and never a broken one.

---

## Deploying from the panel API

The file manager works, but two things about it are worth knowing before you
fight them.

**Downloads are blocked.** Chrome refuses repeated automatic downloads from
that origin, and the panel's own Download button goes through a scripted
anchor, so it counts as automatic too. Getting a file *off* the box is
painful. Getting one *on* is not, which is why the deploy is one upload rather
than a sync.

**`files/contents` truncates** at roughly 1.2 KB per call, so reading a large
file back through it is not worth attempting.

Everything else can be driven from the page with `fetch` and the `XSRF-TOKEN`
cookie sent as an `X-XSRF-TOKEN` header:

```
POST /api/client/servers/<id>/files/decompress   {root, file}
POST /api/client/servers/<id>/files/delete       {root, files[]}
PUT  /api/client/servers/<id>/files/rename       {root, files[{from,to}]}
POST /api/client/servers/<id>/files/write?file=  raw body
POST /api/client/servers/<id>/power              {signal: "restart"}
GET  /api/client/servers/<id>/files/list?directory=
```

So the whole deploy is: upload the bundle through the file input, wait for it
to land, `decompress`, confirm the client zip grew, delete the bundle, restart.

**Wait for the upload before decompressing.** Calling `decompress` too early
returns 500, and if the delete runs anyway the bundle is gone without ever
having been extracted. Poll `files/list` until the size is right.

## Verifying a deploy

```
rm help
```

Every command should be listed, including any added in that build. Then:

```
rm status
```

Version, player count, bus counters and handler errors. `handler errors 0` is
the one that matters.

Byte comparison is the strongest check. `files/list` reports sizes, so compare
one against the local file:

```
wc -c server/RaceManager/04_identity.lua
```

If those match, the file on the box is the file you built.
