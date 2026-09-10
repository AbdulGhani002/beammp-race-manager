RM = RM or {}

RM.VERSION = "0.6.10-front-row"

RM.config = {
  nameMinLen  = 3,
  nameMaxLen  = 20,
  namePattern = "^[%w_%-%. ]+$",

  -- guests have no stable BeamMP id, so nothing they do can be attributed
  -- across sessions. set AllowGuests = false in ServerConfig.toml to drop the case.
  guestsRanked = false,

  -- How a guest is recognised on a later visit.
  --   "ip"   the connection, hashed. survives the new name BeamMP hands out
  --          every session, which is the only thing that works while the
  --          forum is down and nobody can register.
  --   "name" the name BeamMP gave them. a different person every join.
  -- Put this back to "name" once accounts work again: a real BeamMP id is
  -- better than an address that changes when a router reboots.
  guestKey = "ip",

  tickMs     = 100,
  rosterMs   = 500,
  autosaveMs = 30000,

  -- A first join downloads the map before the mod can say anything, and that
  -- is minutes on a big one. Only worth complaining well after that.
  helloTimeoutMs = 600000,

  -- roster gates. a row only goes out when one of these actually moves.
  speedDeltaMph = 2,
  pingDeltaMs   = 10,

  -- outbound queue depth per player, and inbound limits per player
  maxBatchMsgs  = 24,
  maxInboundMsgs = 16,
  inboundPerSec  = 40,

  roles  = { owner = 4, admin = 3, staff = 2, player = 1 },

  -- identity keys, e.g. "beammp:12345". empty means nobody is owner until you
  -- run "rm owner <name>" in the host console, which only you can reach.
  owners = {},

  -- his document names every penalty except this one, so it is a guess until
  -- he says otherwise. flagged in the phase 2 plan.
  penalties = { recovery = 60.0, flatTire = 30.0, repair = 30.0, missedGate = 30.0,
                speeding = 30.0 },

  -- a run is thrown away if nobody crosses anything for this long
  raceIdleTimeoutMs = 900000,

  -- A course that folds back on itself puts the volume for one gate a few
  -- metres from another twenty six gates away, and driving the road near the
  -- start clips the one belonging to the end of the lap. Cutting a corner
  -- skips a gate or two; it does not skip twenty six. Anything past this is a
  -- volume that was brushed rather than a gate that was driven through, so it
  -- is ignored rather than priced.
  maxGateSkip = 4,

  -- nothing on wheels does this, so a split implying it is a lie
  maxPlausibleMph = 300,

  -- how far a client stamp may sit outside what the server believes
  clockTrustMs = 2000,
  -- how long the car is held still while each job is done. only inside a run.
  holds     = { reposition = 5.0, spareTire = 30.0, repair = 60.0, fuel = 20.0,
                rerack = 30.0 },

  -- how many spare changes a car gets before it has to pit. nil means
  -- however many tires are actually on its rack, which is what he asked
  -- for: a truck with two spares gets two, one with none gets none.
  spareChanges = nil,

  -- a quarter of a tank per press
  fuelStep  = 0.25,

  -- the default limit offered when you add a zone, and how long you have to
  -- stay over it before it costs you. one bump over a crest is free.
  speedZoneMph   = 37,
  speedGraceSec  = 3.0,
  -- what a finish pays by place, and how much a level costs. two hundred
  -- for the win, two less each place after, never under the floor.
  xpCurve      = { first = 200, step = 2, floor = 20 },
  xpPerLevel   = 1000,

  -- The race classes, as he sent them on 2026-09-04, in his order.
  --
  -- A class is entered, not worked out from the car: he runs every vehicle,
  -- and two people in the same truck can be in different classes. So the
  -- driver picks one when they arm, and the books sort on what was entered.
  --
  -- The optional cars list is the other way round, for the day he wants a
  -- class pinned to particular vehicles. Empty means anybody may enter it.
  --   { division = "Unlimited", name = "Trophy Truck", cars = { "pickup" } }
  classes = {
    { division = "Limited",   name = "Class 10" },
    { division = "Limited",   name = "Class 12" },
    { division = "Limited",   name = "Class 5" },
    { division = "Limited",   name = "Class 7 Stock" },
    { division = "Limited",   name = "UTV Pro Turbo" },
    { division = "Limited",   name = "UTV Pro NA" },
    { division = "Limited",   name = "UTV Pro Open" },
    { division = "Limited",   name = "Class 5/1600, 1600 & Class 9" },
    { division = "Limited",   name = "Class 11" },
    { division = "Limited",   name = "Trophy Truck Spec" },
    { division = "Limited",   name = "1450" },
    { division = "Limited",   name = "Class 2000" },
    { division = "Unlimited", name = "Class 1" },
    { division = "Unlimited", name = "Class 6200" },
    { division = "Unlimited", name = "Class 7 Unlimited" },
    { division = "Unlimited", name = "Class 8" },
    { division = "Unlimited", name = "Trophy Truck" },
  },


  -- The Stella box on the dash. How close a car has to be to ask the one in
  -- front to let it by, how long that driver has to answer, how long the
  -- green light lasts, and how far a stopped car's warning reaches.
  stella = { passWindowM = 300, passReplySecs = 30, passGoSecs = 20,
             hazardRangeM = 250 },

  maxCheckpoints = 200,
  maxTracks      = 64,
  maxPerfRuns    = 200,

  -- Baja Sim's own server, given to us on 2026-08-25. The button tries the
  -- browser, but that binding is a no-op in some builds and a fullscreen game
  -- swallows the window anyway, so the panel shows the invite to copy. That is
  -- the part that always works.
  discordUrl = "https://discord.gg/7JHKJbHNt",
}

-- what the client is allowed to see
RM.config.public = {
  version       = RM.VERSION,
  penalties     = RM.config.penalties,
  maxCheckpointsPerLap = RM.config.maxCheckpoints,
  holds         = RM.config.holds,
  fuelStep      = RM.config.fuelStep,
  speedZoneMph  = RM.config.speedZoneMph,
  speedGraceSec = RM.config.speedGraceSec,
  discordUrl    = RM.config.discordUrl,
  nameMinLen    = RM.config.nameMinLen,
  nameMaxLen    = RM.config.nameMaxLen,
  maxCheckpoints = RM.config.maxCheckpoints,
  classes       = RM.config.classes,
}
