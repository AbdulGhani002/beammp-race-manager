-- Phase 4 against the mock host: the lobby, the pit and the speed zones.
--
--   lua tools/test_phase4.lua

local M = dofile("tools/mock/beammp.lua")

local pass, fail = 0, 0
local failures = {}

local function ok(cond, what)
  if cond then pass = pass + 1
  else
    fail = fail + 1
    failures[#failures + 1] = what
    print("  FAIL  " .. what)
  end
end

local function eq(got, want, what)
  ok(got == want, ("%s (got %s, wanted %s)"):format(what, tostring(got), tostring(want)))
end

local function near(got, want, tol, what)
  ok(type(got) == "number" and math.abs(got - want) <= tol,
     ("%s (got %s, wanted %s +/- %s)"):format(what, tostring(got), tostring(want), tostring(tol)))
end

local function section(t) print("") print("== " .. t) end

os.execute("cmd /c rmdir /s /q Resources 2>nul")
M.loadPlugin()

local function tick(n) for _ = 1, (n or 1) do M.fire("rm:tick") end end

M.fire("onInit")

-- three players and a course
local function player(pid, name, beammp, ip)
  M.addPlayer(pid, name, beammp, false, ip)
  M.fire("onPlayerJoining", pid)
  M.clientSend(pid, "hello", { version = RM.VERSION })
  M.clientSend(pid, "name.set", { name = name })
end

player(0, "Host", "6001", "203.0.113.1")
player(1, "Second", "6002", "203.0.113.2")
player(2, "Third", "6003", "203.0.113.3")
RM.console.handle("rm role Host owner")

M.clientSend(0, "track.begin",
  { id = "loop", name = "Loop", kind = "race", level = "utah_sc", circuit = true })
tick(1)
for i = 1, 5 do
  M.advance(1)
  M.clientSend(0, "track.mark", { pos = { x = i * 100, y = 0, z = 0 }, yaw = 0 })
  tick(1)
end

section("a pit is marked like a gate but lives apart from the lap")
M.clientSend(0, "track.pit", { pos = { x = 250, y = 30, z = 0 }, yaw = 0 })
tick(1)
local draft = RM.tracks.getDraft and RM.tracks.getDraft(0) or nil
M.clientSend(0, "track.finish")
tick(1)
local track = RM.tracks.get("loop")
eq(#track.checkpoints, 5, "five gates on the lap")
eq(#track.pits, 1, "and one pit beside it")
eq(track.checkpoints[3].i, 3, "the gates kept their numbers")

-- Out in the open desert the game cannot prove which road a gate is on, so the
-- gate keeps the width it was captured with. On a wide course that is too
-- narrow to span it, and re-driving thirteen gates to fix that is not a fix.
section("one width across every gate on a saved course, from the console")
do
  local t = RM.tracks.get("loop")
  local was = t.checkpoints[1].size and t.checkpoints[1].size.w
  ok(type(was) == "number", "the gates start at the width they were marked with")

  local out = RM.console.handle("rm gatewidth loop 34")
  ok(out:find("34 metres across"), "the console says what it did")
  eq(t.checkpoints[1].size.w, 34, "the first gate is wider")
  eq(t.checkpoints[#t.checkpoints].size.w, 34, "and so is the last")

  ok(RM.console.handle("rm gatewidth loop 900"):find("bad_width"),
     "a silly width is refused rather than saved")
  ok(RM.console.handle("rm gatewidth nope 34"):find("no_such_track"),
     "and a course that is not there is too")
  ok(RM.console.handle("rm gatewidth"):find("usage"), "half a command prints the usage")

  RM.tracks.setWidthDirect("loop", was)
  eq(t.checkpoints[1].size.w, was, "and it can be put back")
end

section("the lobby: make, join, start")
local okL, lobby = RM.lobby.create(0, { track = "loop", laps = 1, mode = "controller", open = true })
ok(okL, "the host makes a public race")
eq(select(2, RM.lobby.create(1, { track = "loop", laps = 1 })), "course_in_use",
   "a second race on the same course is refused")
eq(select(2, RM.lobby.create(0, { track = "loop", laps = 1 })), "already_in_one",
   "and so is making one while in one")

ok(RM.lobby.join(1, lobby.id), "a public race takes anyone")
eq(select(2, RM.lobby.join(1, lobby.id)), "already_in_one", "but only once")

eq(select(2, RM.lobby.start(1)), "not_the_host", "only the host starts it")

local okS, _, order = RM.lobby.start(0)
ok(okS, "the host starts it")
eq(#order, 2, "with both drivers in it")
eq(order[1], 0, "the host has the first grid spot")
eq(RM.lobby.of(0), nil, "the lobby is gone once it starts")

section("making or joining a race puts you on the grid straight away")
-- so the cars gather behind the line as they turn up, in the seats they got,
-- rather than all standing wherever they spawned until the host presses Start
M.clearOutbox(0)
M.clientSend(0, "race.create", { track = "loop", laps = 1, open = true })
tick(1)
local hostSpot = M.lastMessage(0, "race.teleport")
ok(hostSpot ~= nil and hostSpot.pos ~= nil, "the host is put on the grid on making the race")
local mine = RM.lobby.of(0)
M.clearOutbox(1)
M.clientSend(1, "race.join", { id = mine.id })
tick(1)
local joinSpot = M.lastMessage(1, "race.teleport")
ok(joinSpot ~= nil and joinSpot.pos ~= nil, "and so is somebody who joins it")
ok(hostSpot and joinSpot and (math.abs(hostSpot.pos.x - joinSpot.pos.x) > 0.5
   or math.abs(hostSpot.pos.y - joinSpot.pos.y) > 0.5),
   "in a different seat, not on top of the host")
RM.lobby.leave(1)
RM.lobby.leave(0)

section("the host sets the class once and everybody is armed in it")
-- his bot announces a race with a class, so the race carries one rather than
-- every driver being told to pick the same thing
eq(select(2, RM.lobby.create(0, { track = "loop", laps = 1, class = "Class 4" })),
   "no_such_class", "a class he never sent is refused when the race is made")

local okC, withClass =
  RM.lobby.create(0, { track = "loop", laps = 1, open = true,
                       class = "Trophy Truck" })
ok(okC, "a real one is taken")
eq(withClass.class, "Trophy Truck", "and the race holds it")
eq(RM.lobby.wire(0).class, "Trophy Truck", "so the lobby card can show it")
ok(RM.lobby.join(1, withClass.id), "somebody joins")

M.clientSend(0, "race.start", {})
tick(1)
eq(RM.race.get(0) and RM.race.get(0).class, "Trophy Truck",
   "the host is armed in it")
eq(RM.race.get(1) and RM.race.get(1).class, "Trophy Truck",
   "and so is the driver who only joined, without being asked")
RM.race.clear(0)
RM.race.clear(1)
RM.results.forget(0)
RM.results.forget(1)

section("an invite only race")
local okI, inv = RM.lobby.create(1, { track = "loop", laps = 1, open = false })
ok(okI, "Second makes an invite race")
eq(select(2, RM.lobby.join(2, inv.id)), "not_invited", "a stranger is refused")
ok(RM.lobby.invite(1, 2), "the host invites Third")
eq(select(2, RM.lobby.invite(2, 0)), "no_lobby", "only somebody in the race can invite")
ok(RM.lobby.join(2, inv.id), "and Third gets in")

section("the race outlives its host")
ok(RM.lobby.leave(1), "the host walks out")
local left = RM.lobby.of(2)
ok(left ~= nil, "the race is still there")
eq(left.host, 2, "and Third inherits it")
ok(RM.lobby.leave(2), "the last driver leaves")
eq(RM.lobby.count(), 0, "and the race dissolves")

section("joining after the start is too late")
local okL2, l2 = RM.lobby.create(1, { track = "loop", laps = 1, open = true })
ok(okL2, "a fresh race")
RM.lobby.start(1)
eq(select(2, RM.lobby.join(2, l2.id)), "no_such_race", "the field closed with the start")

section("grid spots are a grid, not a pile")
local a = RM.tracks.gridSpot(track, 0)
local b = RM.tracks.gridSpot(track, 1)
local c = RM.tracks.gridSpot(track, 3)
local ab = math.sqrt((a.pos.x - b.pos.x)^2 + (a.pos.y - b.pos.y)^2)
local ac = math.sqrt((a.pos.x - c.pos.x)^2 + (a.pos.y - c.pos.y)^2)
ok(ab >= 4, "two cars are metres apart, not on top of each other")
ok(ac >= 6, "the fourth car is a row back")
eq(a.yaw, b.yaw, "and everyone faces the same way")

section("in the pit nothing is added to your time")
for pid = 0, 2 do RM.race.clear(pid) RM.service.forget(pid) end
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
M.advance(5)
RM.race.gate(0, 1, RM.now())

ok(RM.race.setPit(0, true), "the car enters the pit")
eq(RM.race.inPit(0), true, "and the run knows")

M.clearOutbox(0)
M.clientSend(0, "service.use", { which = "repair" })
tick(1)
local hold = M.lastMessage(0, "service.hold")
ok(hold ~= nil, "repair is allowed in the pit")
near(hold.hold, RM.config.holds.repair, 0.01, "the hold still applies in full")
eq(hold.penalty, nil, "and nothing goes on the clock")
eq(#RM.race.get(0).penalties, 0, "nothing on the run either")

M.advance(RM.config.holds.repair + 1)
tick(1)
local run = M.lastMessage(0, "service.run")
ok(run ~= nil, "the job still runs")
M.clientSend(0, "service.done", { which = "repair", ok = true })

section("pit fuel is the whole tank")
M.clearOutbox(0)
M.clientSend(0, "service.use", { which = "fuel" })
tick(1)
M.advance(RM.config.holds.fuel + 1)
tick(1)
local fuelRun = M.lastMessage(0, "service.run")
ok(fuelRun ~= nil, "fuel runs")
eq(fuelRun.full, true, "at the pit rate, which is the whole tank")
M.clientSend(0, "service.done", { which = "fuel", ok = true })

section("a spare in the pit needs no flat")
-- the car says what its rack holds and what it ever held; in the pit a car
-- with a rack is reseeded from that, so a spare there does not wait on a
-- rerack first
M.clearOutbox(0)
M.clientSend(0, "service.use", { which = "spare", spares = 2, cap = 2 })
tick(1)
ok(M.lastMessage(0, "service.hold") ~= nil, "the pit takes the car as it is")

M.advance(RM.config.holds.spareTire + 1)
tick(1)
M.clientSend(0, "service.done", { which = "spare", ok = true })

M.clearOutbox(0)
M.clientSend(0, "service.use", { which = "spare", spares = 0, cap = 0 })
tick(1)
do
  local said = M.lastMessage(0, "service.failed")
  eq(said and said.why, "no_rack", "and a car that never had a rack is told so")
end

section("leaving the pit puts the prices back")
ok(RM.race.setPit(0, false), "the car drives out")
M.clearOutbox(0)
M.clientSend(0, "service.use", { which = "repair" })
tick(1)
local paid = M.lastMessage(0, "service.hold")
eq(paid.penalty, nil, "a repair outside costs no time either, his rule: the hold is the cost")
near(RM.race.penaltyTotal(RM.race.get(0)), 0, 0.01, "and nothing is on the run")
M.advance(RM.config.holds.repair + 1)
tick(1)
M.clientSend(0, "service.done", { which = "repair", ok = true })

section("speed zones: a warning first, the charge only if you stay over")
RM.tracks.setZonesDirect("loop", { { from = 2, to = 4, mph = 37 } })
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
M.advance(5)
RM.race.gate(0, 1, RM.now())
M.advance(2)
RM.race.gate(0, 2, RM.now())

eq(RM.zones.at("loop", 3) and RM.zones.at("loop", 3).mph, 37, "the stretch to gate 3 is covered")
eq(RM.zones.at("loop", 2), nil, "the stretch to gate 2 is not")

eq(RM.zones.sample(0, 30), nil, "under the limit is nothing")
eq(RM.zones.sample(0, 50), "warn", "over it is a warning")
eq(RM.zones.sample(0, 50), "warn", "and still a warning inside the grace")
local charged = nil
for _ = 1, 12 do
  local v = RM.zones.sample(0, 50)
  if v == "charged" then charged = true break end
end
ok(charged, "staying over charges")
eq(RM.zones.sample(0, 50), "over", "and only once")
eq(#RM.race.get(0).penalties, 1, "one speeding penalty on the run")
eq(RM.race.get(0).penalties[1].reason, "speeding", "named for what it was")

eq(RM.zones.sample(0, 20), nil, "dropping under resets the meter")
eq(RM.zones.sample(0, 50), "warn", "so going over again warns again")

section("the zone through the roster: the speed the server reads is the speed it judges")
-- the checks above fed the rule a number by hand. this is the whole path:
-- BeamMP reports the car's velocity, the roster turns it into mph, and the
-- tick judges it, warning the screen first and charging after the grace.
RM.zones.sample(0, 20)
M.fire("onVehicleSpawn", 0, 1, "pickup:0-1:{\"jbm\":\"pickup\"}")
eq(RM.identity.session(0).activeVid, 1, "the car just spawned is the one read")
local before = #RM.race.get(0).penalties
eq(RM.players.subscriberCount(), 0, "nobody has the player list open, and it must not matter")
M.setVelocity(0, 1, 25, 0, 0)
M.clearOutbox(0)
tick(10)
local warned = M.lastMessage(0, "zone.warn")
ok(warned ~= nil and warned.charged == false, "fifty six mph in a thirty seven zone warns the screen")
eq(warned and warned.zone and warned.zone.mph, 37, "and says which limit")
eq(#RM.race.get(0).penalties, before, "with no charge yet")
tick(40)
local charged = M.lastMessage(0, "zone.warn")
ok(charged ~= nil and charged.charged == true, "staying over through the grace charges")
eq(#RM.race.get(0).penalties, before + 1, "one more speeding penalty on the run")
ok(M.lastMessage(0, "race.state") ~= nil, "and the run state goes out with it")
M.setVelocity(0, 1, 5, 0, 0)
M.clearOutbox(0)
tick(10)
eq(M.lastMessage(0, "zone.warn"), nil, "eleven mph is nothing to say")

section("a box the car cannot read the limit off is still judged, from the server's own copy")
-- his courses carry the limit on the box. One that does not would have gone
-- unjudged: the client sends in with no limit and the server had nothing.
RM.tracks.setZonesDirect("loop", {})
do
  local t = RM.tracks.get("loop")
  t.szGates = { { i = 1, mph = 20, pos = { x = 250, y = 0, z = 0 }, yaw = 0,
                  size = { w = 20, h = 8, d = 40 } } }
end
M.setVelocity(0, 1, 5, 0, 0)
tick(10)
M.clearOutbox(0)
M.clientSend(0, "sz.state", { inside = true, i = 1 })
tick(1)
local blind = M.lastMessage(0, "zone.warn")
ok(blind ~= nil and blind.event == "on", "the zone is on")
eq(blind and blind.zone and blind.zone.mph, 20, "at the limit the server holds for box one")
M.clearOutbox(0)
M.clientSend(0, "sz.state", { inside = false })
tick(1)
ok(M.lastMessage(0, "zone.warn") ~= nil, "and it comes off again")
do
  local t = RM.tracks.get("loop")
  t.szGates = {}
end

section("a box zone: the car's own measure says in, the server judges it, and says out")
-- the client's poll says in, once, and the server takes its word: it knows
-- nothing of where a box is, only that the car is in one at this limit. No
-- run state goes out for that; the screen has nothing to redraw, the zone
-- word is enough, and a run state on every box edge was a flood.
RM.tracks.setZonesDirect("loop", {})
M.setVelocity(0, 1, 5, 0, 0)
tick(10)
M.clearOutbox(0)
M.clientSend(0, "sz.state", { inside = true, mph = 20, i = 1 })
tick(1)
local on = M.lastMessage(0, "zone.warn")
ok(on ~= nil and on.event == "on", "the zone is on")
eq(on and on.zone and on.zone.mph, 20, "at the box's limit")
eq(on and on.zone and on.zone.box, true, "and known as a box")
eq(M.lastMessage(0, "race.state"), nil, "and no run state went out for it")
before = #RM.race.get(0).penalties
M.setVelocity(0, 1, 13, 0, 0)
M.clearOutbox(0)
tick(10)
local w = M.lastMessage(0, "zone.warn")
ok(w ~= nil and w.charged == false and w.event == nil, "twenty nine mph in a twenty box warns")
eq(w and w.zone and w.zone.mph, 20, "with the box's limit")
tick(40)
local c = M.lastMessage(0, "zone.warn")
ok(c ~= nil and c.charged == true, "staying over through the grace charges")
eq(#RM.race.get(0).penalties, before + 1, "one more speeding penalty on the run")
M.setVelocity(0, 1, 5, 0, 0)
tick(10)
M.clearOutbox(0)
M.clientSend(0, "sz.state", { inside = false })
tick(1)
local off = M.lastMessage(0, "zone.warn")
ok(off ~= nil and off.event == "off", "the zone is off")
eq(M.lastMessage(0, "race.state"), nil, "and again no run state for it")
M.setVelocity(0, 1, 13, 0, 0)
M.clearOutbox(0)
tick(10)
eq(M.lastMessage(0, "zone.warn"), nil, "out of the box, twenty nine mph is nothing to say")
eq(#RM.race.get(0).penalties, before + 1, "and nothing more is charged")

section("a zone that ends where it starts is refused, not kept")
RM.tracks.setZonesDirect("loop", { { from = 3, to = 3, mph = 37 }, { from = 4, to = 2, mph = 37 },
                                   { from = 2, to = 4, mph = 37 } })
eq(#RM.tracks.get("loop").zones, 1, "only the one that runs somewhere is kept")
eq(RM.tracks.get("loop").zones[1].from, 2, "from gate 2")
eq(RM.tracks.get("loop").zones[1].to, 4, "to gate 4")

section("two zones back to back each cover their own stretch")
RM.tracks.setZonesDirect("loop", { { from = 2, to = 3, mph = 37 }, { from = 3, to = 5, mph = 20 } })
eq(RM.zones.at("loop", 3) and RM.zones.at("loop", 3).mph, 37, "the drive to gate 3 is the first")
eq(RM.zones.at("loop", 4) and RM.zones.at("loop", 4).mph, 20, "the drive to gate 4 is the second")
eq(RM.zones.at("loop", 5) and RM.zones.at("loop", 5).mph, 20, "and so is the drive to gate 5")
eq(RM.zones.at("loop", 2), nil, "before either there is nothing")

section("a zone to the last gate ends there: the run back to the line is free")
RM.tracks.setZonesDirect("loop", { { from = 4, to = 5, mph = 20 } })
eq(RM.zones.at("loop", 5) and RM.zones.at("loop", 5).mph, 20, "the drive to gate 5 is limited")
eq(RM.zones.at("loop", 6), nil, "the drive from gate 5 back to the line is not")

section("the limit itself is not over it")
RM.tracks.setZonesDirect("loop", { { from = 2, to = 4, mph = 37 } })
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 2 })
M.advance(5)
RM.race.gate(0, 1, RM.now())
M.advance(2)
RM.race.gate(0, 2, RM.now())
eq(RM.zones.sample(0, 37), nil, "thirty seven in a thirty seven zone is fine")
eq(RM.zones.sample(0, 38), "warn", "thirty eight is not")

section("the second lap is judged like the first")
for _ = 1, 12 do RM.zones.sample(0, 50) end
eq(#RM.race.get(0).penalties, 1, "charged once on lap one")
M.advance(2) RM.race.gate(0, 3, RM.now())
M.advance(2) RM.race.gate(0, 4, RM.now())
M.advance(2) RM.race.gate(0, 5, RM.now())
eq(RM.zones.sample(0, 50), nil, "out of the zone, the speed is nobody's business")
M.advance(2) RM.race.gate(0, 1, RM.now())
M.advance(2) RM.race.gate(0, 2, RM.now())
eq(RM.race.get(0).currentLap, 2, "on lap two")
eq(RM.zones.sample(0, 50), "warn", "the same zone warns again")
for _ = 1, 12 do RM.zones.sample(0, 50) end
eq(#RM.race.get(0).penalties, 2, "and charges again")
RM.race.clear(0)

section("saving a course over one that had zones says the zones went with it")
RM.tracks.setZonesDirect("loop", { { from = 2, to = 4, mph = 37 } })
M.clientSend(0, "track.begin",
  { id = "loop", name = "Loop", kind = "race", level = "utah_sc", circuit = true, overwrite = true })
tick(1)
for i = 1, 3 do
  M.advance(1)
  M.clientSend(0, "track.mark", { pos = { x = i * 100, y = 0, z = 0 }, yaw = 0 })
  tick(1)
end
M.clearOutbox(0)
M.clientSend(0, "track.finish", {})
tick(1)
local fin = M.lastMessage(0, "capture.result")
eq(fin and fin.action, "finish", "the save came back")
eq(fin and fin.data and fin.data.droppedZones, 1, "and says one zone was dropped")
eq(#RM.tracks.get("loop").zones, 0, "the new course has none")
eq(RM.tracks.get("loop").droppedZones, nil, "and the count is not kept on the course")
-- the loop is five gates again for what follows
M.clientSend(0, "track.begin",
  { id = "loop", name = "Loop", kind = "race", level = "utah_sc", circuit = true, overwrite = true })
tick(1)
for i = 1, 5 do
  M.advance(1)
  M.clientSend(0, "track.mark", { pos = { x = i * 100, y = 0, z = 0 }, yaw = 0 })
  tick(1)
end
M.clearOutbox(0)
M.clientSend(0, "track.finish", {})
tick(1)
eq(M.lastMessage(0, "capture.result").data.droppedZones, nil, "no zones on the old one, nothing to say")

section("the zone console")
RM.tracks.setZonesDirect("loop", {})
RM.console.handle("rm zone loop 2 4 37")
eq(#RM.tracks.get("loop").zones, 1, "rm zone adds one")
RM.console.handle("rm zoneclear loop")
eq(#RM.tracks.get("loop").zones, 0, "rm zoneclear empties it")

section("a run ending forgets the pit")
RM.race.clear(0)
RM.race.arm(0, { id = "loop", mode = "controller", laps = 1 })
M.advance(5)
RM.race.gate(0, 1, RM.now())
RM.race.setPit(0, true)
M.fire("onPlayerDisconnect", 0)
eq(RM.race.get(0), nil, "the run went with the player")
eq(RM.lobby.count(), 0, "and no lobby is left behind")

print("")
print(("%d passed, %d failed"):format(pass, fail))
for _, f in ipairs(failures) do print("  - " .. f) end
os.exit(fail == 0 and 0 or 1)
